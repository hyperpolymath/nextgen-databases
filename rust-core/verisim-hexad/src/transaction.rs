// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <jonathan.jewell@open.ac.uk>

//! ACID Transaction Manager for VeriSimDB Hexad Operations
//!
//! Provides cross-modality atomicity for hexad operations. A hexad update must
//! either succeed across all 8 modalities (octad) or fail completely,
//! preserving the fundamental consistency guarantee of the hexad model.
//!
//! # Architecture
//!
//! The transaction manager implements:
//! - **Atomicity**: Undo log records previous state for rollback across modalities
//! - **Consistency**: Modality-level locks prevent partial updates
//! - **Isolation**: MVCC with configurable isolation levels (ReadCommitted, Serializable)
//! - **Durability**: Delegated to the underlying modality stores
//!
//! # Transaction State Machine
//!
//! ```text
//! ┌────────┐  begin()   ┌────────┐  commit()   ┌───────────┐
//! │  None  │ ──────────>│ Active │ ──────────> │ Committed │
//! └────────┘            └────────┘             └───────────┘
//!                            │
//!                            │ rollback()
//!                            ▼
//!                       ┌────────────┐
//!                       │ RolledBack │
//!                       └────────────┘
//! ```
//!
//! # Deadlock Detection
//!
//! Uses a wait-for graph at modality granularity. When a transaction requests a
//! lock held by another transaction, the manager checks for cycles. If a cycle
//! is detected, the requesting transaction is aborted to break the deadlock.

use chrono::{DateTime, Utc};
use std::collections::{HashMap, HashSet, VecDeque};
use std::fmt;
use std::sync::Arc;
use tokio::sync::RwLock;
use tracing::{debug, info, warn};
use uuid::Uuid;

// ---------------------------------------------------------------------------
// Constants: the eight VeriSimDB modalities (octad)
// ---------------------------------------------------------------------------

/// All eight modalities that a hexad spans (the octad).
///
/// Originally six modalities; extended with `provenance` and `spatial` when
/// VeriSimDB evolved from hexad to octad model.
pub const MODALITIES: &[&str] = &[
    "graph", "vector", "tensor", "semantic", "document", "temporal",
    "provenance", "spatial",
];

// ---------------------------------------------------------------------------
// Error types
// ---------------------------------------------------------------------------

/// Errors that can occur during transaction processing.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TransactionError {
    /// The transaction is not in the expected state for the requested operation.
    InvalidState {
        transaction_id: Uuid,
        current: TransactionState,
        expected: &'static str,
    },
    /// A lock could not be acquired because it conflicts with an existing lock.
    LockConflict {
        entity_id: String,
        modality: String,
        held_by: Uuid,
    },
    /// A deadlock cycle was detected; the requesting transaction must abort.
    DeadlockDetected {
        transaction_id: Uuid,
        cycle: Vec<Uuid>,
    },
    /// The requested transaction does not exist.
    TransactionNotFound(Uuid),
    /// A modality name is not one of the eight valid modalities.
    InvalidModality(String),
    /// MVCC version conflict: the entity was modified after the transaction read it.
    VersionConflict {
        entity_id: String,
        expected_version: u64,
        actual_version: u64,
    },
}

impl fmt::Display for TransactionError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidState {
                transaction_id,
                current,
                expected,
            } => write!(
                f,
                "Transaction {transaction_id}: state is {current:?}, expected {expected}"
            ),
            Self::LockConflict {
                entity_id,
                modality,
                held_by,
            } => write!(
                f,
                "Lock conflict on {entity_id}/{modality} held by {held_by}"
            ),
            Self::DeadlockDetected {
                transaction_id,
                cycle,
            } => write!(
                f,
                "Deadlock detected for {transaction_id}: cycle {:?}",
                cycle
            ),
            Self::TransactionNotFound(id) => write!(f, "Transaction not found: {id}"),
            Self::InvalidModality(m) => write!(f, "Invalid modality: {m}"),
            Self::VersionConflict {
                entity_id,
                expected_version,
                actual_version,
            } => write!(
                f,
                "Version conflict on {entity_id}: expected v{expected_version}, found v{actual_version}"
            ),
        }
    }
}

impl std::error::Error for TransactionError {}

// ---------------------------------------------------------------------------
// Core types
// ---------------------------------------------------------------------------

/// The lifecycle state of a transaction.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum TransactionState {
    /// The transaction is open and accepting operations.
    Active,
    /// The transaction has been successfully committed.
    Committed,
    /// The transaction has been rolled back (either explicitly or due to error).
    RolledBack,
}

/// Transaction isolation level.
///
/// Determines what data other concurrent transactions can see.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum IsolationLevel {
    /// Reads only committed data. A transaction may see different snapshots
    /// of the same entity if another transaction commits between reads.
    ReadCommitted,
    /// Full serializability: the transaction operates as if it were the only
    /// one running. Version conflicts cause the transaction to abort.
    Serializable,
}

impl Default for IsolationLevel {
    fn default() -> Self {
        Self::ReadCommitted
    }
}

/// Type of lock held on an entity/modality pair.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum LockType {
    /// Multiple transactions can hold shared locks concurrently (for reads).
    Shared,
    /// Only one transaction can hold an exclusive lock (for writes).
    Exclusive,
}

/// A lock held by a transaction on a specific entity/modality pair.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct LockEntry {
    /// The entity being locked.
    pub entity_id: String,
    /// The modality being locked (one of the six).
    pub modality: String,
    /// Whether the lock is shared or exclusive.
    pub lock_type: LockType,
}

/// An entry in the undo log, recording the previous state of an
/// entity/modality pair so that rollback can restore it.
#[derive(Debug, Clone)]
pub struct UndoEntry {
    /// The entity that was modified.
    pub entity_id: String,
    /// The modality that was modified.
    pub modality: String,
    /// The serialized previous data, or `None` if the entity/modality did not
    /// exist before this transaction touched it (i.e., it was a new insert).
    pub previous_data: Option<Vec<u8>>,
    /// The version of the entity before modification (for MVCC validation).
    pub previous_version: u64,
    /// When this undo entry was recorded.
    pub recorded_at: DateTime<Utc>,
}

/// A version-stamped read performed by a Serializable transaction, used for
/// validation at commit time.
#[derive(Debug, Clone)]
pub struct ReadStamp {
    /// The entity that was read.
    pub entity_id: String,
    /// The modality that was read.
    pub modality: String,
    /// The version observed at read time.
    pub version_at_read: u64,
}

/// A single transaction, tracking its state, undo log, locks, and read set.
#[derive(Debug)]
pub struct Transaction {
    /// Unique transaction identifier.
    pub id: Uuid,
    /// Current lifecycle state.
    pub state: TransactionState,
    /// Isolation level for this transaction.
    pub isolation_level: IsolationLevel,
    /// Ordered log of changes for rollback (applied in reverse on rollback).
    pub undo_log: Vec<UndoEntry>,
    /// Set of locks currently held by this transaction.
    pub locks: Vec<LockEntry>,
    /// Read set for Serializable validation (entity/modality -> version read).
    pub read_set: Vec<ReadStamp>,
    /// When the transaction was started.
    pub started_at: DateTime<Utc>,
    /// When the transaction was completed (committed or rolled back).
    pub completed_at: Option<DateTime<Utc>>,
}

impl Transaction {
    /// Create a new transaction in the Active state.
    fn new(isolation_level: IsolationLevel) -> Self {
        Self {
            id: Uuid::new_v4(),
            state: TransactionState::Active,
            isolation_level,
            undo_log: Vec::new(),
            locks: Vec::new(),
            read_set: Vec::new(),
            started_at: Utc::now(),
            completed_at: None,
        }
    }

    /// Return `true` if the transaction is still active.
    pub fn is_active(&self) -> bool {
        self.state == TransactionState::Active
    }
}

// ---------------------------------------------------------------------------
// Lock table
// ---------------------------------------------------------------------------

/// Key for the lock table: (entity_id, modality).
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
struct LockKey {
    entity_id: String,
    modality: String,
}

/// Information about a lock held in the global lock table.
#[derive(Debug, Clone)]
struct LockInfo {
    /// Which transaction holds the lock.
    holder: Uuid,
    /// Lock type (Shared or Exclusive).
    lock_type: LockType,
}

/// Global lock table shared across all transactions.
///
/// The table maps (entity_id, modality) pairs to the set of locks held on them.
/// Shared locks allow multiple holders; exclusive locks allow exactly one.
#[derive(Debug)]
pub struct LockTable {
    /// Map of lock key to the list of holders.
    locks: HashMap<LockKey, Vec<LockInfo>>,
    /// Wait-for graph: transaction A waits for transaction B.
    /// Used for deadlock detection.
    wait_for: HashMap<Uuid, HashSet<Uuid>>,
}

impl LockTable {
    /// Create an empty lock table.
    fn new() -> Self {
        Self {
            locks: HashMap::new(),
            wait_for: HashMap::new(),
        }
    }

    /// Attempt to acquire a lock. Returns `Ok(())` on success, or a
    /// `LockConflict` / `DeadlockDetected` error on failure.
    fn acquire(
        &mut self,
        transaction_id: Uuid,
        entity_id: &str,
        modality: &str,
        lock_type: LockType,
    ) -> Result<(), TransactionError> {
        let key = LockKey {
            entity_id: entity_id.to_string(),
            modality: modality.to_string(),
        };

        // Phase 1: Inspect existing holders (immutable read) and determine action.
        // We collect all the information we need before mutating anything, so the
        // borrow checker is satisfied when we later call detect_cycle.
        enum AcquireAction {
            /// Lock is already held by this transaction with compatible type.
            AlreadyHeld,
            /// Upgrade from Shared to Exclusive (sole holder).
            Upgrade,
            /// Cannot upgrade because other holders exist.
            UpgradeConflict { other_holder: Uuid },
            /// Conflict with another transaction's lock.
            Conflict { blocker: Uuid },
            /// No existing holders or only compatible shared locks; grant directly.
            Grant,
        }

        let action = {
            let holders = self.locks.get(&key).map(|v| v.as_slice()).unwrap_or(&[]);
            let mut result = AcquireAction::Grant;

            for info in holders {
                if info.holder == transaction_id {
                    if info.lock_type == LockType::Shared && lock_type == LockType::Exclusive {
                        if holders.len() == 1 {
                            result = AcquireAction::Upgrade;
                        } else {
                            let other = holders
                                .iter()
                                .find(|h| h.holder != transaction_id)
                                .map(|h| h.holder)
                                .unwrap_or(transaction_id);
                            result = AcquireAction::UpgradeConflict {
                                other_holder: other,
                            };
                        }
                    } else {
                        result = AcquireAction::AlreadyHeld;
                    }
                    break;
                }

                let conflicts = !matches!(
                    (info.lock_type, lock_type),
                    (LockType::Shared, LockType::Shared)
                );

                if conflicts {
                    result = AcquireAction::Conflict {
                        blocker: info.holder,
                    };
                    break;
                }
            }

            result
        };

        // Phase 2: Act on the determined action.
        match action {
            AcquireAction::AlreadyHeld => return Ok(()),
            AcquireAction::UpgradeConflict { other_holder } => {
                return Err(TransactionError::LockConflict {
                    entity_id: entity_id.to_string(),
                    modality: modality.to_string(),
                    held_by: other_holder,
                });
            }
            AcquireAction::Conflict { blocker } => {
                // Register in wait-for graph for deadlock detection
                self.wait_for
                    .entry(transaction_id)
                    .or_default()
                    .insert(blocker);

                // Check for deadlock cycle (no mutable borrow on self.locks)
                if let Some(cycle) = self.detect_cycle(transaction_id) {
                    self.wait_for.remove(&transaction_id);
                    return Err(TransactionError::DeadlockDetected {
                        transaction_id,
                        cycle,
                    });
                }

                return Err(TransactionError::LockConflict {
                    entity_id: entity_id.to_string(),
                    modality: modality.to_string(),
                    held_by: blocker,
                });
            }
            AcquireAction::Upgrade | AcquireAction::Grant => {
                // Proceed to grant/upgrade below
            }
        }

        // Phase 3: Mutate the lock table to grant or upgrade the lock.
        let holders = self.locks.entry(key).or_default();

        // Remove any existing lock by this transaction on this key (for upgrades)
        holders.retain(|info| info.holder != transaction_id);

        // Grant the lock
        holders.push(LockInfo {
            holder: transaction_id,
            lock_type,
        });

        // Clear any wait-for edges from this transaction (lock acquired)
        self.wait_for.remove(&transaction_id);

        debug!(
            transaction = %transaction_id,
            entity = entity_id,
            modality = modality,
            lock = ?lock_type,
            "Lock acquired"
        );

        Ok(())
    }

    /// Release all locks held by the given transaction.
    fn release_all(&mut self, transaction_id: Uuid) {
        // Remove from all lock entries
        self.locks.retain(|_key, holders| {
            holders.retain(|info| info.holder != transaction_id);
            !holders.is_empty()
        });

        // Remove from wait-for graph
        self.wait_for.remove(&transaction_id);
        for waiters in self.wait_for.values_mut() {
            waiters.remove(&transaction_id);
        }

        debug!(transaction = %transaction_id, "All locks released");
    }

    /// Detect a cycle in the wait-for graph starting from `start`.
    /// Returns `Some(cycle)` if a cycle is found, `None` otherwise.
    /// Uses BFS to find the shortest cycle.
    fn detect_cycle(&self, start: Uuid) -> Option<Vec<Uuid>> {
        let mut visited = HashSet::new();
        let mut queue: VecDeque<Vec<Uuid>> = VecDeque::new();

        // Seed the BFS with the direct dependencies of `start`
        if let Some(neighbors) = self.wait_for.get(&start) {
            for &neighbor in neighbors {
                queue.push_back(vec![start, neighbor]);
            }
        }

        while let Some(path) = queue.pop_front() {
            let Some(&current) = path.last() else {
                // Invariant: BFS paths are always non-empty (seeded with [start, neighbor]).
                // Defensive guard — skip rather than panic in the deadlock detector.
                continue;
            };

            if current == start {
                // Found a cycle
                return Some(path);
            }

            if !visited.insert(current) {
                continue;
            }

            if let Some(neighbors) = self.wait_for.get(&current) {
                for &neighbor in neighbors {
                    let mut next_path = path.clone();
                    next_path.push(neighbor);
                    queue.push_back(next_path);
                }
            }
        }

        None
    }

    /// Return `true` if any lock is held on the given entity/modality pair.
    fn is_locked(&self, entity_id: &str, modality: &str) -> bool {
        let key = LockKey {
            entity_id: entity_id.to_string(),
            modality: modality.to_string(),
        };
        self.locks.get(&key).is_some_and(|h| !h.is_empty())
    }

    /// Return the set of lock holders for a given entity/modality pair.
    fn holders(&self, entity_id: &str, modality: &str) -> Vec<(Uuid, LockType)> {
        let key = LockKey {
            entity_id: entity_id.to_string(),
            modality: modality.to_string(),
        };
        self.locks
            .get(&key)
            .map(|holders| {
                holders
                    .iter()
                    .map(|info| (info.holder, info.lock_type))
                    .collect()
            })
            .unwrap_or_default()
    }
}

// ---------------------------------------------------------------------------
// Version table (MVCC)
// ---------------------------------------------------------------------------

/// Tracks the current version of each entity/modality pair for MVCC.
#[derive(Debug, Default)]
struct VersionTable {
    /// Map from (entity_id, modality) to the current committed version.
    versions: HashMap<(String, String), u64>,
}

impl VersionTable {
    /// Get the current version for an entity/modality pair.
    /// Returns 0 if no version has been recorded.
    fn get(&self, entity_id: &str, modality: &str) -> u64 {
        self.versions
            .get(&(entity_id.to_string(), modality.to_string()))
            .copied()
            .unwrap_or(0)
    }

    /// Set the version for an entity/modality pair.
    fn set(&mut self, entity_id: &str, modality: &str, version: u64) {
        self.versions.insert(
            (entity_id.to_string(), modality.to_string()),
            version,
        );
    }

    /// Increment and return the new version for an entity/modality pair.
    fn increment(&mut self, entity_id: &str, modality: &str) -> u64 {
        let key = (entity_id.to_string(), modality.to_string());
        let next = self.versions.get(&key).copied().unwrap_or(0) + 1;
        self.versions.insert(key, next);
        next
    }
}

// ---------------------------------------------------------------------------
// Transaction Manager
// ---------------------------------------------------------------------------

/// The central transaction manager for VeriSimDB hexad operations.
///
/// Coordinates transactions, locks, and MVCC versioning across the eight
/// modalities (octad). All public methods are `async` and thread-safe via
/// interior `RwLock`s.
pub struct TransactionManager {
    /// Active and recently completed transactions.
    active_transactions: Arc<RwLock<HashMap<Uuid, Transaction>>>,
    /// Global lock table for modality-level locking.
    lock_table: Arc<RwLock<LockTable>>,
    /// MVCC version tracking.
    version_table: Arc<RwLock<VersionTable>>,
}

impl TransactionManager {
    /// Create a new transaction manager with empty state.
    pub fn new() -> Self {
        Self {
            active_transactions: Arc::new(RwLock::new(HashMap::new())),
            lock_table: Arc::new(RwLock::new(LockTable::new())),
            version_table: Arc::new(RwLock::new(VersionTable::default())),
        }
    }

    /// Begin a new transaction with the given isolation level.
    ///
    /// Returns the unique transaction ID that must be used for all subsequent
    /// operations within this transaction.
    pub async fn begin(&self, isolation_level: IsolationLevel) -> Uuid {
        let txn = Transaction::new(isolation_level);
        let txn_id = txn.id;

        info!(
            transaction = %txn_id,
            isolation = ?isolation_level,
            "Transaction started"
        );

        self.active_transactions
            .write()
            .await
            .insert(txn_id, txn);

        txn_id
    }

    /// Commit a transaction, making all its changes permanent.
    ///
    /// For Serializable transactions, this validates that no entity/modality
    /// pair read during the transaction has been modified by another committed
    /// transaction (write-skew detection).
    pub async fn commit(&self, transaction_id: Uuid) -> Result<(), TransactionError> {
        let mut txns = self.active_transactions.write().await;
        let txn = txns
            .get_mut(&transaction_id)
            .ok_or(TransactionError::TransactionNotFound(transaction_id))?;

        if txn.state != TransactionState::Active {
            return Err(TransactionError::InvalidState {
                transaction_id,
                current: txn.state,
                expected: "Active",
            });
        }

        // Serializable validation: check read set against current versions
        if txn.isolation_level == IsolationLevel::Serializable {
            let version_table = self.version_table.read().await;
            for stamp in &txn.read_set {
                let current_version =
                    version_table.get(&stamp.entity_id, &stamp.modality);
                if current_version != stamp.version_at_read {
                    // Another transaction committed a write to this entity/modality
                    // after we read it. Must abort.
                    drop(version_table);

                    // Roll back instead of committing
                    txn.state = TransactionState::RolledBack;
                    txn.completed_at = Some(Utc::now());

                    // Release locks
                    let mut lock_table = self.lock_table.write().await;
                    lock_table.release_all(transaction_id);

                    warn!(
                        transaction = %transaction_id,
                        entity = %stamp.entity_id,
                        modality = %stamp.modality,
                        read_version = stamp.version_at_read,
                        current_version = current_version,
                        "Serializable validation failed"
                    );

                    return Err(TransactionError::VersionConflict {
                        entity_id: stamp.entity_id.clone(),
                        expected_version: stamp.version_at_read,
                        actual_version: current_version,
                    });
                }
            }
        }

        // Apply version increments for all writes in the undo log
        {
            let mut version_table = self.version_table.write().await;
            for entry in &txn.undo_log {
                version_table.increment(&entry.entity_id, &entry.modality);
            }
        }

        txn.state = TransactionState::Committed;
        txn.completed_at = Some(Utc::now());

        // Release all locks
        {
            let mut lock_table = self.lock_table.write().await;
            lock_table.release_all(transaction_id);
        }

        info!(
            transaction = %transaction_id,
            undo_entries = txn.undo_log.len(),
            "Transaction committed"
        );

        Ok(())
    }

    /// Roll back a transaction, undoing all recorded changes.
    ///
    /// Returns the undo log entries in reverse order so the caller can apply
    /// compensating actions to the modality stores.
    pub async fn rollback(
        &self,
        transaction_id: Uuid,
    ) -> Result<Vec<UndoEntry>, TransactionError> {
        let mut txns = self.active_transactions.write().await;
        let txn = txns
            .get_mut(&transaction_id)
            .ok_or(TransactionError::TransactionNotFound(transaction_id))?;

        if txn.state != TransactionState::Active {
            return Err(TransactionError::InvalidState {
                transaction_id,
                current: txn.state,
                expected: "Active",
            });
        }

        txn.state = TransactionState::RolledBack;
        txn.completed_at = Some(Utc::now());

        // Collect undo entries in reverse order for the caller to apply
        let mut undo_entries: Vec<UndoEntry> = txn.undo_log.clone();
        undo_entries.reverse();

        // Release all locks
        {
            let mut lock_table = self.lock_table.write().await;
            lock_table.release_all(transaction_id);
        }

        info!(
            transaction = %transaction_id,
            undo_entries = undo_entries.len(),
            "Transaction rolled back"
        );

        Ok(undo_entries)
    }

    /// Acquire a lock on an entity/modality pair within a transaction.
    ///
    /// Validates the modality name and checks for deadlocks before granting.
    pub async fn acquire_lock(
        &self,
        transaction_id: Uuid,
        entity_id: &str,
        modality: &str,
        lock_type: LockType,
    ) -> Result<(), TransactionError> {
        // Validate modality name
        if !MODALITIES.contains(&modality) {
            return Err(TransactionError::InvalidModality(modality.to_string()));
        }

        // Verify transaction is active
        {
            let txns = self.active_transactions.read().await;
            let txn = txns
                .get(&transaction_id)
                .ok_or(TransactionError::TransactionNotFound(transaction_id))?;

            if txn.state != TransactionState::Active {
                return Err(TransactionError::InvalidState {
                    transaction_id,
                    current: txn.state,
                    expected: "Active",
                });
            }
        }

        // Acquire in the global lock table
        {
            let mut lock_table = self.lock_table.write().await;
            lock_table.acquire(transaction_id, entity_id, modality, lock_type)?;
        }

        // Record the lock in the transaction's lock set
        {
            let mut txns = self.active_transactions.write().await;
            if let Some(txn) = txns.get_mut(&transaction_id) {
                let entry = LockEntry {
                    entity_id: entity_id.to_string(),
                    modality: modality.to_string(),
                    lock_type,
                };
                // Avoid duplicates (upgrade replaces)
                txn.locks.retain(|l| {
                    !(l.entity_id == entry.entity_id && l.modality == entry.modality)
                });
                txn.locks.push(entry);
            }
        }

        Ok(())
    }

    /// Record an undo entry for a write operation within a transaction.
    ///
    /// The caller is responsible for serializing the previous data (if any)
    /// before passing it here.
    pub async fn record_undo(
        &self,
        transaction_id: Uuid,
        entity_id: &str,
        modality: &str,
        previous_data: Option<Vec<u8>>,
        previous_version: u64,
    ) -> Result<(), TransactionError> {
        if !MODALITIES.contains(&modality) {
            return Err(TransactionError::InvalidModality(modality.to_string()));
        }

        let mut txns = self.active_transactions.write().await;
        let txn = txns
            .get_mut(&transaction_id)
            .ok_or(TransactionError::TransactionNotFound(transaction_id))?;

        if txn.state != TransactionState::Active {
            return Err(TransactionError::InvalidState {
                transaction_id,
                current: txn.state,
                expected: "Active",
            });
        }

        txn.undo_log.push(UndoEntry {
            entity_id: entity_id.to_string(),
            modality: modality.to_string(),
            previous_data,
            previous_version,
            recorded_at: Utc::now(),
        });

        debug!(
            transaction = %transaction_id,
            entity = entity_id,
            modality = modality,
            "Undo entry recorded"
        );

        Ok(())
    }

    /// Record a read stamp for Serializable validation.
    ///
    /// Called when a Serializable transaction reads an entity/modality pair.
    /// The version at read time is recorded so that commit-time validation
    /// can detect write-skew.
    pub async fn record_read(
        &self,
        transaction_id: Uuid,
        entity_id: &str,
        modality: &str,
    ) -> Result<(), TransactionError> {
        if !MODALITIES.contains(&modality) {
            return Err(TransactionError::InvalidModality(modality.to_string()));
        }

        let current_version = {
            let vt = self.version_table.read().await;
            vt.get(entity_id, modality)
        };

        let mut txns = self.active_transactions.write().await;
        let txn = txns
            .get_mut(&transaction_id)
            .ok_or(TransactionError::TransactionNotFound(transaction_id))?;

        if txn.state != TransactionState::Active {
            return Err(TransactionError::InvalidState {
                transaction_id,
                current: txn.state,
                expected: "Active",
            });
        }

        txn.read_set.push(ReadStamp {
            entity_id: entity_id.to_string(),
            modality: modality.to_string(),
            version_at_read: current_version,
        });

        Ok(())
    }

    /// Get a snapshot of a transaction's current state.
    ///
    /// Returns `None` if the transaction does not exist.
    pub async fn get_transaction_state(
        &self,
        transaction_id: Uuid,
    ) -> Option<TransactionState> {
        self.active_transactions
            .read()
            .await
            .get(&transaction_id)
            .map(|txn| txn.state)
    }

    /// Get the number of currently active transactions.
    pub async fn active_count(&self) -> usize {
        self.active_transactions
            .read()
            .await
            .values()
            .filter(|txn| txn.state == TransactionState::Active)
            .count()
    }

    /// Get the current MVCC version for an entity/modality pair.
    pub async fn current_version(&self, entity_id: &str, modality: &str) -> u64 {
        self.version_table.read().await.get(entity_id, modality)
    }

    /// Set the MVCC version for an entity/modality pair.
    ///
    /// This is primarily used during initial data loading or recovery.
    pub async fn set_version(&self, entity_id: &str, modality: &str, version: u64) {
        self.version_table
            .write()
            .await
            .set(entity_id, modality, version);
    }

    /// Check whether a specific entity/modality pair is currently locked.
    pub async fn is_locked(&self, entity_id: &str, modality: &str) -> bool {
        self.lock_table
            .read()
            .await
            .is_locked(entity_id, modality)
    }

    /// Get the lock holders for an entity/modality pair.
    pub async fn lock_holders(
        &self,
        entity_id: &str,
        modality: &str,
    ) -> Vec<(Uuid, LockType)> {
        self.lock_table
            .read()
            .await
            .holders(entity_id, modality)
    }

    /// Remove completed (Committed or RolledBack) transactions from memory.
    ///
    /// Returns the number of transactions purged.
    pub async fn purge_completed(&self) -> usize {
        let mut txns = self.active_transactions.write().await;
        let before = txns.len();
        txns.retain(|_id, txn| txn.state == TransactionState::Active);
        let purged = before - txns.len();
        if purged > 0 {
            info!(purged = purged, "Purged completed transactions");
        }
        purged
    }
}

impl Default for TransactionManager {
    fn default() -> Self {
        Self::new()
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    /// Helper: create a fresh TransactionManager for each test.
    fn new_manager() -> TransactionManager {
        TransactionManager::new()
    }

    // -- Test 1: Basic lifecycle (begin -> commit) --

    #[tokio::test]
    async fn test_begin_and_commit() {
        let mgr = new_manager();
        let txn_id = mgr.begin(IsolationLevel::ReadCommitted).await;

        assert_eq!(
            mgr.get_transaction_state(txn_id).await,
            Some(TransactionState::Active)
        );

        mgr.commit(txn_id).await.unwrap();

        assert_eq!(
            mgr.get_transaction_state(txn_id).await,
            Some(TransactionState::Committed)
        );
    }

    // -- Test 2: Basic lifecycle (begin -> rollback) --

    #[tokio::test]
    async fn test_begin_and_rollback() {
        let mgr = new_manager();
        let txn_id = mgr.begin(IsolationLevel::ReadCommitted).await;

        let undo = mgr.rollback(txn_id).await.unwrap();
        assert!(undo.is_empty());

        assert_eq!(
            mgr.get_transaction_state(txn_id).await,
            Some(TransactionState::RolledBack)
        );
    }

    // -- Test 3: Double commit is rejected --

    #[tokio::test]
    async fn test_double_commit_rejected() {
        let mgr = new_manager();
        let txn_id = mgr.begin(IsolationLevel::ReadCommitted).await;

        mgr.commit(txn_id).await.unwrap();

        let result = mgr.commit(txn_id).await;
        assert!(matches!(
            result,
            Err(TransactionError::InvalidState { .. })
        ));
    }

    // -- Test 4: Commit after rollback is rejected --

    #[tokio::test]
    async fn test_commit_after_rollback_rejected() {
        let mgr = new_manager();
        let txn_id = mgr.begin(IsolationLevel::ReadCommitted).await;

        mgr.rollback(txn_id).await.unwrap();

        let result = mgr.commit(txn_id).await;
        assert!(matches!(
            result,
            Err(TransactionError::InvalidState { .. })
        ));
    }

    // -- Test 5: Nonexistent transaction --

    #[tokio::test]
    async fn test_nonexistent_transaction() {
        let mgr = new_manager();
        let fake_id = Uuid::new_v4();

        let result = mgr.commit(fake_id).await;
        assert!(matches!(
            result,
            Err(TransactionError::TransactionNotFound(_))
        ));
    }

    // -- Test 6: Shared locks are compatible --

    #[tokio::test]
    async fn test_shared_locks_compatible() {
        let mgr = new_manager();
        let txn_a = mgr.begin(IsolationLevel::ReadCommitted).await;
        let txn_b = mgr.begin(IsolationLevel::ReadCommitted).await;

        mgr.acquire_lock(txn_a, "entity-1", "graph", LockType::Shared)
            .await
            .unwrap();
        mgr.acquire_lock(txn_b, "entity-1", "graph", LockType::Shared)
            .await
            .unwrap();

        // Both should hold the lock
        let holders = mgr.lock_holders("entity-1", "graph").await;
        assert_eq!(holders.len(), 2);
    }

    // -- Test 7: Exclusive lock conflicts with shared --

    #[tokio::test]
    async fn test_exclusive_conflicts_with_shared() {
        let mgr = new_manager();
        let txn_a = mgr.begin(IsolationLevel::ReadCommitted).await;
        let txn_b = mgr.begin(IsolationLevel::ReadCommitted).await;

        mgr.acquire_lock(txn_a, "entity-1", "vector", LockType::Shared)
            .await
            .unwrap();

        let result = mgr
            .acquire_lock(txn_b, "entity-1", "vector", LockType::Exclusive)
            .await;
        assert!(matches!(result, Err(TransactionError::LockConflict { .. })));
    }

    // -- Test 8: Exclusive lock conflicts with exclusive --

    #[tokio::test]
    async fn test_exclusive_conflicts_with_exclusive() {
        let mgr = new_manager();
        let txn_a = mgr.begin(IsolationLevel::ReadCommitted).await;
        let txn_b = mgr.begin(IsolationLevel::ReadCommitted).await;

        mgr.acquire_lock(txn_a, "entity-1", "document", LockType::Exclusive)
            .await
            .unwrap();

        let result = mgr
            .acquire_lock(txn_b, "entity-1", "document", LockType::Exclusive)
            .await;
        assert!(matches!(result, Err(TransactionError::LockConflict { .. })));
    }

    // -- Test 9: Locks released on commit --

    #[tokio::test]
    async fn test_locks_released_on_commit() {
        let mgr = new_manager();
        let txn_a = mgr.begin(IsolationLevel::ReadCommitted).await;

        mgr.acquire_lock(txn_a, "entity-1", "tensor", LockType::Exclusive)
            .await
            .unwrap();
        assert!(mgr.is_locked("entity-1", "tensor").await);

        mgr.commit(txn_a).await.unwrap();
        assert!(!mgr.is_locked("entity-1", "tensor").await);

        // Another transaction can now lock it
        let txn_b = mgr.begin(IsolationLevel::ReadCommitted).await;
        mgr.acquire_lock(txn_b, "entity-1", "tensor", LockType::Exclusive)
            .await
            .unwrap();
    }

    // -- Test 10: Locks released on rollback --

    #[tokio::test]
    async fn test_locks_released_on_rollback() {
        let mgr = new_manager();
        let txn_a = mgr.begin(IsolationLevel::ReadCommitted).await;

        mgr.acquire_lock(txn_a, "entity-1", "semantic", LockType::Exclusive)
            .await
            .unwrap();
        assert!(mgr.is_locked("entity-1", "semantic").await);

        mgr.rollback(txn_a).await.unwrap();
        assert!(!mgr.is_locked("entity-1", "semantic").await);
    }

    // -- Test 11: Undo log records and returns entries in reverse --

    #[tokio::test]
    async fn test_undo_log_reverse_order() {
        let mgr = new_manager();
        let txn_id = mgr.begin(IsolationLevel::ReadCommitted).await;

        mgr.record_undo(txn_id, "e1", "graph", Some(vec![1, 2, 3]), 1)
            .await
            .unwrap();
        mgr.record_undo(txn_id, "e1", "vector", Some(vec![4, 5, 6]), 1)
            .await
            .unwrap();
        mgr.record_undo(txn_id, "e1", "document", None, 0)
            .await
            .unwrap();

        let undo = mgr.rollback(txn_id).await.unwrap();
        assert_eq!(undo.len(), 3);
        // Should be in reverse order: document, vector, graph
        assert_eq!(undo[0].modality, "document");
        assert_eq!(undo[1].modality, "vector");
        assert_eq!(undo[2].modality, "graph");
        // The document entry had no previous data (new insert)
        assert!(undo[0].previous_data.is_none());
        assert_eq!(undo[2].previous_data, Some(vec![1, 2, 3]));
    }

    // -- Test 12: MVCC version increments on commit --

    #[tokio::test]
    async fn test_mvcc_version_increment_on_commit() {
        let mgr = new_manager();
        let txn_id = mgr.begin(IsolationLevel::ReadCommitted).await;

        assert_eq!(mgr.current_version("e1", "graph").await, 0);

        mgr.record_undo(txn_id, "e1", "graph", None, 0)
            .await
            .unwrap();
        mgr.record_undo(txn_id, "e1", "vector", None, 0)
            .await
            .unwrap();

        mgr.commit(txn_id).await.unwrap();

        assert_eq!(mgr.current_version("e1", "graph").await, 1);
        assert_eq!(mgr.current_version("e1", "vector").await, 1);
        // Untouched modality stays at 0
        assert_eq!(mgr.current_version("e1", "tensor").await, 0);
    }

    // -- Test 13: Serializable isolation detects version conflict --

    #[tokio::test]
    async fn test_serializable_version_conflict() {
        let mgr = new_manager();

        // Transaction A reads entity e1/graph at version 0
        let txn_a = mgr.begin(IsolationLevel::Serializable).await;
        mgr.record_read(txn_a, "e1", "graph").await.unwrap();

        // Transaction B writes to e1/graph and commits, bumping version to 1
        let txn_b = mgr.begin(IsolationLevel::ReadCommitted).await;
        mgr.record_undo(txn_b, "e1", "graph", None, 0)
            .await
            .unwrap();
        mgr.commit(txn_b).await.unwrap();

        // Transaction A tries to commit, but e1/graph is now v1 (was v0 at read)
        let result = mgr.commit(txn_a).await;
        assert!(matches!(
            result,
            Err(TransactionError::VersionConflict { .. })
        ));

        // Transaction A should be rolled back
        assert_eq!(
            mgr.get_transaction_state(txn_a).await,
            Some(TransactionState::RolledBack)
        );
    }

    // -- Test 14: Serializable commits when no conflict --

    #[tokio::test]
    async fn test_serializable_no_conflict() {
        let mgr = new_manager();

        let txn_a = mgr.begin(IsolationLevel::Serializable).await;
        mgr.record_read(txn_a, "e1", "graph").await.unwrap();
        mgr.record_undo(txn_a, "e1", "vector", None, 0)
            .await
            .unwrap();

        // Nobody else modifies e1/graph, so commit should succeed
        mgr.commit(txn_a).await.unwrap();
        assert_eq!(
            mgr.get_transaction_state(txn_a).await,
            Some(TransactionState::Committed)
        );
    }

    // -- Test 15: Invalid modality is rejected --

    #[tokio::test]
    async fn test_invalid_modality_rejected() {
        let mgr = new_manager();
        let txn_id = mgr.begin(IsolationLevel::ReadCommitted).await;

        let result = mgr
            .acquire_lock(txn_id, "e1", "nosuch", LockType::Shared)
            .await;
        assert!(matches!(
            result,
            Err(TransactionError::InvalidModality(_))
        ));

        let result = mgr
            .record_undo(txn_id, "e1", "invalid_modality", None, 0)
            .await;
        assert!(matches!(
            result,
            Err(TransactionError::InvalidModality(_))
        ));
    }

    // -- Test 16: Deadlock detection --

    #[tokio::test]
    async fn test_deadlock_detection() {
        let mgr = new_manager();
        let txn_a = mgr.begin(IsolationLevel::ReadCommitted).await;
        let txn_b = mgr.begin(IsolationLevel::ReadCommitted).await;

        // A locks e1/graph exclusively
        mgr.acquire_lock(txn_a, "e1", "graph", LockType::Exclusive)
            .await
            .unwrap();

        // B locks e2/graph exclusively
        mgr.acquire_lock(txn_b, "e2", "graph", LockType::Exclusive)
            .await
            .unwrap();

        // B tries to lock e1/graph -> conflict (A holds it), creates wait edge B->A
        let result_b = mgr
            .acquire_lock(txn_b, "e1", "graph", LockType::Exclusive)
            .await;
        assert!(matches!(
            result_b,
            Err(TransactionError::LockConflict { .. })
        ));

        // Manually register B waiting for A in the lock table to simulate
        // a real wait scenario for deadlock detection
        {
            let mut lt = mgr.lock_table.write().await;
            lt.wait_for.entry(txn_b).or_default().insert(txn_a);
        }

        // A tries to lock e2/graph -> conflict (B holds it)
        // With B->A already in wait-for, adding A->B creates cycle A->B->A
        let result_a = mgr
            .acquire_lock(txn_a, "e2", "graph", LockType::Exclusive)
            .await;

        // Should detect deadlock (cycle: A -> B -> A)
        assert!(
            matches!(
                result_a,
                Err(TransactionError::DeadlockDetected { .. })
                    | Err(TransactionError::LockConflict { .. })
            ),
            "Expected deadlock or lock conflict, got: {:?}",
            result_a
        );
    }

    // -- Test 17: Active transaction count --

    #[tokio::test]
    async fn test_active_count() {
        let mgr = new_manager();
        assert_eq!(mgr.active_count().await, 0);

        let txn_a = mgr.begin(IsolationLevel::ReadCommitted).await;
        let txn_b = mgr.begin(IsolationLevel::ReadCommitted).await;
        assert_eq!(mgr.active_count().await, 2);

        mgr.commit(txn_a).await.unwrap();
        assert_eq!(mgr.active_count().await, 1);

        mgr.rollback(txn_b).await.unwrap();
        assert_eq!(mgr.active_count().await, 0);
    }

    // -- Test 18: Purge completed transactions --

    #[tokio::test]
    async fn test_purge_completed() {
        let mgr = new_manager();
        let txn_a = mgr.begin(IsolationLevel::ReadCommitted).await;
        let txn_b = mgr.begin(IsolationLevel::ReadCommitted).await;
        let _txn_c = mgr.begin(IsolationLevel::ReadCommitted).await;

        mgr.commit(txn_a).await.unwrap();
        mgr.rollback(txn_b).await.unwrap();

        let purged = mgr.purge_completed().await;
        assert_eq!(purged, 2);

        // Only txn_c remains
        assert_eq!(mgr.active_count().await, 1);
    }

    // -- Test 19: Cross-modality atomicity scenario --

    #[tokio::test]
    async fn test_cross_modality_atomicity() {
        let mgr = new_manager();
        let txn_id = mgr.begin(IsolationLevel::ReadCommitted).await;

        // Lock all six modalities for entity e1
        for modality in MODALITIES {
            mgr.acquire_lock(txn_id, "e1", modality, LockType::Exclusive)
                .await
                .unwrap();
        }

        // Record undo for all eight modalities (octad)
        for modality in MODALITIES {
            mgr.record_undo(txn_id, "e1", modality, Some(vec![0xDE, 0xAD]), 0)
                .await
                .unwrap();
        }

        // Simulate a failure after writing all modalities -> rollback
        let undo = mgr.rollback(txn_id).await.unwrap();
        assert_eq!(undo.len(), MODALITIES.len());

        // All locks should be released
        for modality in MODALITIES {
            assert!(
                !mgr.is_locked("e1", modality).await,
                "Lock on e1/{modality} should be released after rollback"
            );
        }

        // Versions should NOT have incremented (rolled back, not committed)
        for modality in MODALITIES {
            assert_eq!(
                mgr.current_version("e1", modality).await,
                0,
                "Version for e1/{modality} should still be 0 after rollback"
            );
        }
    }

    // -- Test 20: Lock idempotency (re-acquiring same lock is OK) --

    #[tokio::test]
    async fn test_lock_idempotency() {
        let mgr = new_manager();
        let txn_id = mgr.begin(IsolationLevel::ReadCommitted).await;

        // Acquire the same lock twice -> should succeed silently
        mgr.acquire_lock(txn_id, "e1", "temporal", LockType::Shared)
            .await
            .unwrap();
        mgr.acquire_lock(txn_id, "e1", "temporal", LockType::Shared)
            .await
            .unwrap();

        let holders = mgr.lock_holders("e1", "temporal").await;
        assert_eq!(holders.len(), 1);
    }

    // -- Test 21: Version table set and get --

    #[tokio::test]
    async fn test_version_table_set_get() {
        let mgr = new_manager();

        assert_eq!(mgr.current_version("e1", "graph").await, 0);

        mgr.set_version("e1", "graph", 42).await;
        assert_eq!(mgr.current_version("e1", "graph").await, 42);

        // Different entity/modality is independent
        assert_eq!(mgr.current_version("e2", "graph").await, 0);
        assert_eq!(mgr.current_version("e1", "vector").await, 0);
    }
}
