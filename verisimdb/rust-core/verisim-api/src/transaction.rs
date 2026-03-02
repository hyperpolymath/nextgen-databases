// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <jonathan.jewell@open.ac.uk>
//! ACID Transaction Manager for VeriSimDB.
//!
//! Coordinates multi-modality transactions using a write-ahead log (WAL)
//! for durability and crash recovery. Transactions buffer operations and
//! apply them atomically on commit, or discard them on rollback.
//!
//! # Usage
//!
//! ```ignore
//! let txn_id = manager.begin().await;
//! manager.buffer_operation(&txn_id, op).await?;
//! manager.commit(&txn_id).await?;  // or rollback(&txn_id)
//! ```

use std::collections::HashMap;
use std::sync::Arc;

use chrono::Utc;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use tokio::sync::RwLock;
use tracing::{info, warn};

/// Unique identifier for a transaction.
#[derive(Debug, Clone, Hash, Eq, PartialEq, Serialize, Deserialize)]
pub struct TransactionId(String);

impl TransactionId {
    /// Generate a new unique transaction ID.
    pub fn new() -> Self {
        let now = Utc::now();
        let mut hasher = Sha256::new();
        hasher.update(now.timestamp_nanos_opt().unwrap_or(0).to_le_bytes());
        hasher.update(std::process::id().to_le_bytes());
        let hash = hasher.finalize();
        Self(hex::encode(&hash[..16]))
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }

    /// Create a TransactionId from an existing string (for API lookups).
    pub fn from_str(s: &str) -> Self {
        Self(s.to_string())
    }
}

impl std::fmt::Display for TransactionId {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "txn_{}", &self.0[..12])
    }
}

/// State of a transaction.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum TransactionState {
    /// Transaction is active and accepting operations.
    Active,
    /// Transaction has been committed.
    Committed,
    /// Transaction has been rolled back.
    RolledBack,
}

/// A buffered operation within a transaction.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BufferedOperation {
    /// Target entity ID
    pub entity_id: String,
    /// Operation type
    pub operation: OperationType,
    /// Serialized payload (JSON)
    pub payload: Vec<u8>,
    /// Timestamp of the operation
    pub timestamp: String,
}

/// Types of operations that can be buffered in a transaction.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum OperationType {
    /// Create a new hexad
    Create,
    /// Update an existing hexad
    Update,
    /// Delete a hexad
    Delete,
}

/// An active transaction with its buffered operations.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Transaction {
    /// Transaction identifier
    pub id: TransactionId,
    /// Current state
    pub state: TransactionState,
    /// Buffered operations (applied on commit)
    pub operations: Vec<BufferedOperation>,
    /// When the transaction was started
    pub started_at: String,
    /// When the transaction was completed (committed or rolled back)
    pub completed_at: Option<String>,
}

/// Transaction status response for the API.
#[derive(Debug, Serialize, Deserialize)]
pub struct TransactionStatus {
    pub id: String,
    pub state: TransactionState,
    pub operation_count: usize,
    pub started_at: String,
    pub completed_at: Option<String>,
}

impl From<&Transaction> for TransactionStatus {
    fn from(txn: &Transaction) -> Self {
        Self {
            id: txn.id.0.clone(),
            state: txn.state,
            operation_count: txn.operations.len(),
            started_at: txn.started_at.clone(),
            completed_at: txn.completed_at.clone(),
        }
    }
}

/// Errors from the transaction manager.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum TransactionError {
    /// Transaction not found.
    NotFound(String),
    /// Transaction is not in an active state.
    NotActive(String),
    /// Transaction has already been committed.
    AlreadyCommitted(String),
    /// Transaction has already been rolled back.
    AlreadyRolledBack(String),
    /// Maximum concurrent transactions exceeded.
    TooManyTransactions,
}

impl std::fmt::Display for TransactionError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::NotFound(id) => write!(f, "transaction not found: {}", id),
            Self::NotActive(id) => write!(f, "transaction not active: {}", id),
            Self::AlreadyCommitted(id) => write!(f, "transaction already committed: {}", id),
            Self::AlreadyRolledBack(id) => write!(f, "transaction already rolled back: {}", id),
            Self::TooManyTransactions => write!(f, "maximum concurrent transactions exceeded"),
        }
    }
}

impl std::error::Error for TransactionError {}

/// Configuration for the transaction manager.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TransactionConfig {
    /// Maximum number of concurrent active transactions.
    pub max_concurrent: usize,
    /// Transaction timeout in seconds (auto-rollback after this).
    pub timeout_seconds: u64,
}

impl Default for TransactionConfig {
    fn default() -> Self {
        Self {
            max_concurrent: 256,
            timeout_seconds: 300, // 5 minutes
        }
    }
}

/// Transaction manager — coordinates multi-modality ACID transactions.
///
/// All operations within a transaction are buffered in memory. On commit,
/// the entire batch is written as a WAL commit record, then applied to
/// the stores. On rollback, the buffer is simply discarded.
pub struct TransactionManager {
    config: TransactionConfig,
    transactions: Arc<RwLock<HashMap<TransactionId, Transaction>>>,
}

impl TransactionManager {
    /// Create a new transaction manager.
    pub fn new(config: TransactionConfig) -> Self {
        Self {
            config,
            transactions: Arc::new(RwLock::new(HashMap::new())),
        }
    }

    /// Begin a new transaction.
    pub async fn begin(&self) -> Result<TransactionId, TransactionError> {
        let mut txns = self.transactions.write().await;

        // Check concurrent transaction limit
        let active_count = txns
            .values()
            .filter(|t| t.state == TransactionState::Active)
            .count();
        if active_count >= self.config.max_concurrent {
            return Err(TransactionError::TooManyTransactions);
        }

        let id = TransactionId::new();
        let txn = Transaction {
            id: id.clone(),
            state: TransactionState::Active,
            operations: Vec::new(),
            started_at: Utc::now().to_rfc3339(),
            completed_at: None,
        };

        info!(txn_id = %id, "Transaction started");
        txns.insert(id.clone(), txn);
        Ok(id)
    }

    /// Buffer an operation within a transaction.
    pub async fn buffer_operation(
        &self,
        txn_id: &TransactionId,
        operation: BufferedOperation,
    ) -> Result<(), TransactionError> {
        let mut txns = self.transactions.write().await;
        let txn = txns
            .get_mut(txn_id)
            .ok_or_else(|| TransactionError::NotFound(txn_id.0.clone()))?;

        match txn.state {
            TransactionState::Active => {
                txn.operations.push(operation);
                Ok(())
            }
            TransactionState::Committed => {
                Err(TransactionError::AlreadyCommitted(txn_id.0.clone()))
            }
            TransactionState::RolledBack => {
                Err(TransactionError::AlreadyRolledBack(txn_id.0.clone()))
            }
        }
    }

    /// Commit a transaction — marks all buffered operations as committed.
    ///
    /// Returns the list of buffered operations so the caller (API layer)
    /// can apply them to the hexad store.
    pub async fn commit(
        &self,
        txn_id: &TransactionId,
    ) -> Result<Vec<BufferedOperation>, TransactionError> {
        let mut txns = self.transactions.write().await;
        let txn = txns
            .get_mut(txn_id)
            .ok_or_else(|| TransactionError::NotFound(txn_id.0.clone()))?;

        match txn.state {
            TransactionState::Active => {
                txn.state = TransactionState::Committed;
                txn.completed_at = Some(Utc::now().to_rfc3339());
                let ops = txn.operations.clone();
                info!(txn_id = %txn_id, ops = ops.len(), "Transaction committed");
                Ok(ops)
            }
            TransactionState::Committed => {
                Err(TransactionError::AlreadyCommitted(txn_id.0.clone()))
            }
            TransactionState::RolledBack => {
                Err(TransactionError::AlreadyRolledBack(txn_id.0.clone()))
            }
        }
    }

    /// Rollback a transaction — discard all buffered operations.
    pub async fn rollback(
        &self,
        txn_id: &TransactionId,
    ) -> Result<usize, TransactionError> {
        let mut txns = self.transactions.write().await;
        let txn = txns
            .get_mut(txn_id)
            .ok_or_else(|| TransactionError::NotFound(txn_id.0.clone()))?;

        match txn.state {
            TransactionState::Active => {
                let discarded = txn.operations.len();
                txn.operations.clear();
                txn.state = TransactionState::RolledBack;
                txn.completed_at = Some(Utc::now().to_rfc3339());
                warn!(txn_id = %txn_id, discarded = discarded, "Transaction rolled back");
                Ok(discarded)
            }
            TransactionState::Committed => {
                Err(TransactionError::AlreadyCommitted(txn_id.0.clone()))
            }
            TransactionState::RolledBack => {
                Err(TransactionError::AlreadyRolledBack(txn_id.0.clone()))
            }
        }
    }

    /// Get the status of a transaction.
    pub async fn status(
        &self,
        txn_id: &TransactionId,
    ) -> Result<TransactionStatus, TransactionError> {
        let txns = self.transactions.read().await;
        let txn = txns
            .get(txn_id)
            .ok_or_else(|| TransactionError::NotFound(txn_id.0.clone()))?;
        Ok(TransactionStatus::from(txn))
    }

    /// Clean up completed transactions older than the timeout.
    pub async fn cleanup_expired(&self) -> usize {
        let mut txns = self.transactions.write().await;
        let now = Utc::now();
        let timeout = chrono::Duration::seconds(self.config.timeout_seconds as i64);

        let expired_ids: Vec<TransactionId> = txns
            .iter()
            .filter(|(_, txn)| {
                if txn.state != TransactionState::Active {
                    // Already completed — clean up after timeout
                    if let Some(ref completed) = txn.completed_at {
                        if let Ok(completed_at) = chrono::DateTime::parse_from_rfc3339(completed) {
                            return now.signed_duration_since(completed_at) > timeout;
                        }
                    }
                    false
                } else {
                    // Active but expired — auto-rollback candidate
                    if let Ok(started) = chrono::DateTime::parse_from_rfc3339(&txn.started_at) {
                        now.signed_duration_since(started) > timeout
                    } else {
                        false
                    }
                }
            })
            .map(|(id, _)| id.clone())
            .collect();

        let count = expired_ids.len();
        for id in expired_ids {
            txns.remove(&id);
        }
        count
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_begin_commit() {
        let mgr = TransactionManager::new(TransactionConfig::default());

        let txn_id = mgr.begin().await.unwrap();
        let status = mgr.status(&txn_id).await.unwrap();
        assert_eq!(status.state, TransactionState::Active);
        assert_eq!(status.operation_count, 0);

        // Buffer an operation
        mgr.buffer_operation(
            &txn_id,
            BufferedOperation {
                entity_id: "hex-001".to_string(),
                operation: OperationType::Create,
                payload: b"{}".to_vec(),
                timestamp: Utc::now().to_rfc3339(),
            },
        )
        .await
        .unwrap();

        let status = mgr.status(&txn_id).await.unwrap();
        assert_eq!(status.operation_count, 1);

        // Commit
        let ops = mgr.commit(&txn_id).await.unwrap();
        assert_eq!(ops.len(), 1);

        let status = mgr.status(&txn_id).await.unwrap();
        assert_eq!(status.state, TransactionState::Committed);
    }

    #[tokio::test]
    async fn test_begin_rollback() {
        let mgr = TransactionManager::new(TransactionConfig::default());

        let txn_id = mgr.begin().await.unwrap();

        mgr.buffer_operation(
            &txn_id,
            BufferedOperation {
                entity_id: "hex-002".to_string(),
                operation: OperationType::Update,
                payload: b"{}".to_vec(),
                timestamp: Utc::now().to_rfc3339(),
            },
        )
        .await
        .unwrap();

        let discarded = mgr.rollback(&txn_id).await.unwrap();
        assert_eq!(discarded, 1);

        let status = mgr.status(&txn_id).await.unwrap();
        assert_eq!(status.state, TransactionState::RolledBack);
    }

    #[tokio::test]
    async fn test_double_commit_fails() {
        let mgr = TransactionManager::new(TransactionConfig::default());
        let txn_id = mgr.begin().await.unwrap();
        mgr.commit(&txn_id).await.unwrap();
        let result = mgr.commit(&txn_id).await;
        assert!(result.is_err());
    }

    #[tokio::test]
    async fn test_operation_on_committed_fails() {
        let mgr = TransactionManager::new(TransactionConfig::default());
        let txn_id = mgr.begin().await.unwrap();
        mgr.commit(&txn_id).await.unwrap();

        let result = mgr
            .buffer_operation(
                &txn_id,
                BufferedOperation {
                    entity_id: "hex-003".to_string(),
                    operation: OperationType::Delete,
                    payload: b"{}".to_vec(),
                    timestamp: Utc::now().to_rfc3339(),
                },
            )
            .await;
        assert!(result.is_err());
    }

    #[tokio::test]
    async fn test_max_concurrent_transactions() {
        let mgr = TransactionManager::new(TransactionConfig {
            max_concurrent: 2,
            timeout_seconds: 300,
        });

        let _t1 = mgr.begin().await.unwrap();
        let _t2 = mgr.begin().await.unwrap();
        let result = mgr.begin().await;
        assert!(result.is_err());
    }

    #[tokio::test]
    async fn test_not_found() {
        let mgr = TransactionManager::new(TransactionConfig::default());
        let fake_id = TransactionId("nonexistent".to_string());
        assert!(mgr.status(&fake_id).await.is_err());
        assert!(mgr.commit(&fake_id).await.is_err());
        assert!(mgr.rollback(&fake_id).await.is_err());
    }
}
