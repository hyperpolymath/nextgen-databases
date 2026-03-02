// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <jonathan.jewell@open.ac.uk>

//! Prepared statements and query plan caching.
//!
//! This module implements Phase 5.2 of the VeriSimDB roadmap: Prepared Statements / Query Caching.
//! It provides a [`PlanCache`] that stores parsed and planned query statements, avoiding redundant
//! parsing and planning for repeated queries. The cache supports:
//!
//! - **Prepared statements**: Parse once, execute many times with different parameters.
//! - **Query fingerprinting**: Normalize query text so that semantically identical queries share
//!   a single cached plan (whitespace-insensitive, keyword-case-insensitive).
//! - **Physical plan caching**: Optionally cache the optimized physical plan alongside the
//!   logical plan.
//! - **LRU eviction**: When the cache exceeds `max_entries`, the least-recently-used statement
//!   is evicted.
//! - **TTL expiration**: Entries older than `ttl_seconds` are considered expired and removed on
//!   access or during explicit eviction sweeps.
//! - **Hit/miss statistics**: Track cache effectiveness with atomic counters.

use std::collections::HashMap;
use std::fmt;
use std::sync::atomic::{AtomicU64, Ordering};

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use tokio::sync::RwLock;

use crate::plan::{LogicalPlan, PhysicalPlan};

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/// A unique identifier for a prepared statement.
///
/// Derived from a SHA-256 fingerprint of the normalized query text, ensuring that
/// semantically identical queries map to the same ID.
#[derive(Debug, Clone, Hash, Eq, PartialEq, Serialize, Deserialize)]
pub struct PreparedId(String);

impl PreparedId {
    /// Create a new `PreparedId` from a raw string.
    pub fn new(id: impl Into<String>) -> Self {
        Self(id.into())
    }

    /// Return the underlying string representation.
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl fmt::Display for PreparedId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "prep_{}", &self.0[..12.min(self.0.len())])
    }
}

/// A parameter value that can be bound to a prepared statement placeholder.
///
/// When a prepared statement contains named parameters (e.g. `$name`, `$threshold`),
/// concrete values are supplied at execution time via a map of `String -> ParamValue`.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ParamValue {
    /// A UTF-8 string value.
    String(String),
    /// A signed 64-bit integer.
    Int(i64),
    /// A 64-bit floating-point number.
    Float(f64),
    /// A boolean value.
    Bool(bool),
    /// A vector of 32-bit floats (e.g. an embedding).
    Vector(Vec<f32>),
    /// An explicit SQL-style NULL.
    Null,
}

impl fmt::Display for ParamValue {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ParamValue::String(s) => write!(f, "\"{}\"", s),
            ParamValue::Int(i) => write!(f, "{}", i),
            ParamValue::Float(v) => write!(f, "{}", v),
            ParamValue::Bool(b) => write!(f, "{}", b),
            ParamValue::Vector(v) => write!(f, "vec[{}]", v.len()),
            ParamValue::Null => write!(f, "NULL"),
        }
    }
}

/// A prepared (parsed + planned) statement stored in the cache.
///
/// Contains both the logical plan (always present) and an optional cached physical plan.
/// Tracks usage statistics for LRU eviction and performance monitoring.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PreparedStatement {
    /// Unique identifier derived from the query fingerprint.
    pub id: PreparedId,
    /// The original query text as submitted by the user.
    pub original_query: String,
    /// Named parameters extracted from the query (e.g. `["$name", "$threshold"]`).
    pub parameter_names: Vec<String>,
    /// The parsed logical plan (modality-independent).
    pub logical_plan: LogicalPlan,
    /// Optionally cached optimized physical plan.
    pub cached_physical_plan: Option<PhysicalPlan>,
    /// Timestamp when this statement was first prepared.
    pub created_at: DateTime<Utc>,
    /// Timestamp of the most recent access (prepare or execute).
    pub last_used: DateTime<Utc>,
    /// Number of times this statement has been executed.
    pub use_count: u64,
    /// Rolling average execution time in milliseconds.
    pub avg_execution_ms: f64,
}

/// Configuration for the plan cache.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CacheConfig {
    /// Maximum number of prepared statements to keep in the cache.
    pub max_entries: usize,
    /// Time-to-live in seconds; entries older than this are eligible for eviction.
    pub ttl_seconds: u64,
    /// Whether to cache optimized physical plans alongside logical plans.
    pub enable_plan_cache: bool,
    /// Whether to cache query result sets (reserved for future use).
    pub enable_result_cache: bool,
    /// Maximum bytes allowed for the result cache (reserved for future use).
    pub max_result_cache_bytes: usize,
}

impl Default for CacheConfig {
    fn default() -> Self {
        Self {
            max_entries: 1024,
            ttl_seconds: 3600,
            enable_plan_cache: true,
            enable_result_cache: false,
            max_result_cache_bytes: 64 * 1024 * 1024, // 64 MiB
        }
    }
}

/// Aggregate statistics about cache performance.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CacheStats {
    /// Number of statements currently in the cache.
    pub total_entries: usize,
    /// Total number of cache hits (lookups that found an existing entry).
    pub hit_count: u64,
    /// Total number of cache misses (lookups that did not find an entry).
    pub miss_count: u64,
    /// Total number of entries evicted (TTL or LRU).
    pub eviction_count: u64,
    /// Hit ratio: `hit_count / (hit_count + miss_count)`, or 0.0 if no lookups.
    pub hit_ratio: f64,
    /// Monotonically increasing generation counter; bumped on every mutation.
    pub generation: u64,
}

/// Errors that can occur during cache operations.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum CacheError {
    /// The requested prepared statement was not found in the cache.
    NotFound(String),
    /// The supplied parameters do not match the statement's declared parameter names.
    ParameterMismatch {
        /// Parameter names the statement expects.
        expected: Vec<String>,
        /// Parameter names that were actually provided.
        provided: Vec<String>,
    },
    /// The prepared statement has expired (exceeded TTL).
    Expired(String),
    /// The cache is full and no entry could be evicted to make room.
    CacheFull,
}

impl fmt::Display for CacheError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            CacheError::NotFound(id) => write!(f, "prepared statement not found: {}", id),
            CacheError::ParameterMismatch { expected, provided } => {
                write!(
                    f,
                    "parameter mismatch: expected {:?}, provided {:?}",
                    expected, provided
                )
            }
            CacheError::Expired(id) => write!(f, "prepared statement expired: {}", id),
            CacheError::CacheFull => write!(f, "cache is full"),
        }
    }
}

impl std::error::Error for CacheError {}

// ---------------------------------------------------------------------------
// PlanCache
// ---------------------------------------------------------------------------

/// The plan cache: maps query fingerprints to prepared statements with physical plans.
///
/// Thread-safe via `tokio::sync::RwLock` — multiple readers can access cached plans
/// concurrently, while mutations (prepare, invalidate, evict) take a write lock.
///
/// # Example
///
/// ```rust,no_run
/// use verisim_planner::prepared::{PlanCache, CacheConfig};
/// use verisim_planner::plan::{LogicalPlan, QuerySource};
///
/// # async fn example() {
/// let cache = PlanCache::new(CacheConfig::default());
///
/// let plan = LogicalPlan {
///     source: QuerySource::Hexad,
///     nodes: vec![],
///     post_processing: vec![],
/// };
///
/// let id = cache.prepare("SEARCH graph WHERE type = $t", plan).await;
/// let stmt = cache.get(&id).await;
/// # }
/// ```
pub struct PlanCache {
    /// Cache configuration (immutable after construction).
    config: CacheConfig,
    /// Map from `PreparedId` to the full `PreparedStatement`.
    statements: RwLock<HashMap<PreparedId, PreparedStatement>>,
    /// Map from query fingerprint string to `PreparedId` for fast lookup.
    fingerprints: RwLock<HashMap<String, PreparedId>>,
    /// Monotonically increasing generation counter; bumped on every mutation.
    generation: AtomicU64,
    /// Total cache hits.
    hit_count: AtomicU64,
    /// Total cache misses.
    miss_count: AtomicU64,
    /// Total evictions performed.
    eviction_count: AtomicU64,
}

impl PlanCache {
    /// Create a new plan cache with the given configuration.
    pub fn new(config: CacheConfig) -> Self {
        Self {
            config,
            statements: RwLock::new(HashMap::new()),
            fingerprints: RwLock::new(HashMap::new()),
            generation: AtomicU64::new(0),
            hit_count: AtomicU64::new(0),
            miss_count: AtomicU64::new(0),
            eviction_count: AtomicU64::new(0),
        }
    }

    /// Prepare a query: parse once, store the logical plan, return a stable ID.
    ///
    /// If a statement with the same fingerprint already exists, its `last_used` and
    /// `use_count` are updated and the existing ID is returned.
    pub async fn prepare(&self, query: &str, logical_plan: LogicalPlan) -> PreparedId {
        let fp = Self::fingerprint(query);
        let id = PreparedId::new(&fp);

        // Check if we already have this fingerprint cached.
        {
            let stmts = self.statements.read().await;
            if stmts.contains_key(&id) {
                drop(stmts);
                // Update last_used on existing entry.
                let mut stmts = self.statements.write().await;
                if let Some(stmt) = stmts.get_mut(&id) {
                    stmt.last_used = Utc::now();
                }
                self.generation.fetch_add(1, Ordering::Relaxed);
                return id;
            }
        }

        let now = Utc::now();
        let param_names = Self::extract_parameters(query);

        let stmt = PreparedStatement {
            id: id.clone(),
            original_query: query.to_string(),
            parameter_names: param_names,
            logical_plan,
            cached_physical_plan: None,
            created_at: now,
            last_used: now,
            use_count: 0,
            avg_execution_ms: 0.0,
        };

        {
            let mut stmts = self.statements.write().await;
            let mut fps = self.fingerprints.write().await;

            // Evict LRU if at capacity.
            if stmts.len() >= self.config.max_entries {
                self.evict_lru_inner(&mut stmts, &mut fps);
            }

            stmts.insert(id.clone(), stmt);
            fps.insert(fp, id.clone());
        }

        self.generation.fetch_add(1, Ordering::Relaxed);
        id
    }

    /// Retrieve a prepared statement by its ID.
    ///
    /// Returns `None` if the ID is not in the cache or the entry has expired.
    pub async fn get(&self, id: &PreparedId) -> Option<PreparedStatement> {
        let stmts = self.statements.read().await;
        match stmts.get(id) {
            Some(stmt) => {
                if self.is_expired(stmt) {
                    drop(stmts);
                    self.miss_count.fetch_add(1, Ordering::Relaxed);
                    // Lazy expiration: remove on next write.
                    None
                } else {
                    self.hit_count.fetch_add(1, Ordering::Relaxed);
                    Some(stmt.clone())
                }
            }
            None => {
                self.miss_count.fetch_add(1, Ordering::Relaxed);
                None
            }
        }
    }

    /// Execute a prepared statement: validate parameters, increment counters, return statement.
    ///
    /// This does not actually run the query against the storage engine — it returns the
    /// statement with updated usage statistics so the caller can feed it to the executor.
    pub async fn execute_prepared(
        &self,
        id: &PreparedId,
        params: &HashMap<String, ParamValue>,
    ) -> Result<PreparedStatement, CacheError> {
        let mut stmts = self.statements.write().await;
        let stmt = stmts
            .get_mut(id)
            .ok_or_else(|| CacheError::NotFound(id.as_str().to_string()))?;

        // Check TTL expiration.
        if self.is_expired(stmt) {
            let id_str = id.as_str().to_string();
            stmts.remove(id);
            return Err(CacheError::Expired(id_str));
        }

        // Validate that the provided parameter names match expected ones.
        if !stmt.parameter_names.is_empty() {
            let mut expected_sorted = stmt.parameter_names.clone();
            expected_sorted.sort();

            let mut provided_sorted: Vec<String> = params.keys().cloned().collect();
            provided_sorted.sort();

            if expected_sorted != provided_sorted {
                return Err(CacheError::ParameterMismatch {
                    expected: stmt.parameter_names.clone(),
                    provided: params.keys().cloned().collect(),
                });
            }
        }

        // Update usage statistics.
        stmt.use_count += 1;
        stmt.last_used = Utc::now();

        self.hit_count.fetch_add(1, Ordering::Relaxed);
        self.generation.fetch_add(1, Ordering::Relaxed);

        Ok(stmt.clone())
    }

    /// Invalidate (remove) a specific prepared statement from the cache.
    ///
    /// Returns `true` if the statement existed and was removed.
    pub async fn invalidate(&self, id: &PreparedId) -> bool {
        let mut stmts = self.statements.write().await;
        let mut fps = self.fingerprints.write().await;

        if let Some(stmt) = stmts.remove(id) {
            let fp = Self::fingerprint(&stmt.original_query);
            fps.remove(&fp);
            self.eviction_count.fetch_add(1, Ordering::Relaxed);
            self.generation.fetch_add(1, Ordering::Relaxed);
            true
        } else {
            false
        }
    }

    /// Invalidate all prepared statements (e.g. on schema change).
    pub async fn invalidate_all(&self) {
        let mut stmts = self.statements.write().await;
        let mut fps = self.fingerprints.write().await;

        let count = stmts.len() as u64;
        stmts.clear();
        fps.clear();

        self.eviction_count.fetch_add(count, Ordering::Relaxed);
        self.generation.fetch_add(1, Ordering::Relaxed);
    }

    /// Compute a deterministic fingerprint for a query string.
    ///
    /// Normalization rules:
    /// 1. Collapse all whitespace (spaces, tabs, newlines) into single spaces.
    /// 2. Trim leading and trailing whitespace.
    /// 3. Lowercase VQL/SQL keywords (SELECT, WHERE, FROM, SEARCH, LIMIT, ORDER, BY, GROUP,
    ///    AND, OR, NOT, JOIN, ON, AS, HAVING, INSERT, UPDATE, DELETE, SET, INTO, VALUES,
    ///    WITH, UNION, INTERSECT, EXCEPT, EXISTS, BETWEEN, LIKE, IN, IS, NULL, TRUE, FALSE,
    ///    ASC, DESC, DISTINCT, ALL, ANY, SOME, CASE, WHEN, THEN, ELSE, END, PROOF, VERIFY,
    ///    DRIFT, HEXAD, MODALITY).
    /// 4. SHA-256 hash the normalized text and return as hex.
    pub fn fingerprint(query: &str) -> String {
        let normalized = Self::normalize_query(query);

        let mut hasher = Sha256::new();
        hasher.update(normalized.as_bytes());
        let result = hasher.finalize();

        // Convert to hex string.
        result
            .iter()
            .map(|byte| format!("{:02x}", byte))
            .collect::<String>()
    }

    /// Look up an existing prepared statement by raw query text.
    ///
    /// Returns the `PreparedId` if a statement with the same fingerprint exists, or `None`.
    pub async fn lookup_by_query(&self, query: &str) -> Option<PreparedId> {
        let fp = Self::fingerprint(query);
        let fps = self.fingerprints.read().await;

        match fps.get(&fp) {
            Some(id) => {
                self.hit_count.fetch_add(1, Ordering::Relaxed);
                Some(id.clone())
            }
            None => {
                self.miss_count.fetch_add(1, Ordering::Relaxed);
                None
            }
        }
    }

    /// Cache an optimized physical plan for an existing prepared statement.
    ///
    /// This is called after the optimizer produces a physical plan, so subsequent executions
    /// can skip the optimization step entirely.
    pub async fn cache_plan(&self, id: &PreparedId, plan: PhysicalPlan) {
        let mut stmts = self.statements.write().await;
        if let Some(stmt) = stmts.get_mut(id) {
            stmt.cached_physical_plan = Some(plan);
            self.generation.fetch_add(1, Ordering::Relaxed);
        }
    }

    /// Return aggregate cache statistics.
    pub fn stats(&self) -> CacheStats {
        let hits = self.hit_count.load(Ordering::Relaxed);
        let misses = self.miss_count.load(Ordering::Relaxed);
        let total_lookups = hits + misses;
        let hit_ratio = if total_lookups > 0 {
            hits as f64 / total_lookups as f64
        } else {
            0.0
        };

        // We cannot await inside a non-async function, so we report the generation
        // and eviction counters which are always available atomically. The total_entries
        // field requires a blocking read — callers who need it should use `stats_async`.
        CacheStats {
            total_entries: 0, // Populated by stats_async; sync callers get 0.
            hit_count: hits,
            miss_count: misses,
            eviction_count: self.eviction_count.load(Ordering::Relaxed),
            hit_ratio,
            generation: self.generation.load(Ordering::Relaxed),
        }
    }

    /// Return aggregate cache statistics (async version with accurate entry count).
    pub async fn stats_async(&self) -> CacheStats {
        let stmts = self.statements.read().await;
        let mut s = self.stats();
        s.total_entries = stmts.len();
        s
    }

    /// Evict all entries whose `created_at` is older than the configured TTL.
    ///
    /// Returns the number of entries evicted.
    pub async fn evict_expired(&self) -> usize {
        let now = Utc::now();
        let ttl = chrono::Duration::seconds(self.config.ttl_seconds as i64);

        let mut stmts = self.statements.write().await;
        let mut fps = self.fingerprints.write().await;

        let expired_ids: Vec<PreparedId> = stmts
            .iter()
            .filter(|(_, stmt)| {
                now.signed_duration_since(stmt.created_at) > ttl
            })
            .map(|(id, _)| id.clone())
            .collect();

        let count = expired_ids.len();
        for id in &expired_ids {
            if let Some(stmt) = stmts.remove(id) {
                let fp = Self::fingerprint(&stmt.original_query);
                fps.remove(&fp);
            }
        }

        self.eviction_count
            .fetch_add(count as u64, Ordering::Relaxed);
        if count > 0 {
            self.generation.fetch_add(1, Ordering::Relaxed);
        }

        count
    }

    /// Evict the least-recently-used entry when the cache exceeds `max_entries`.
    ///
    /// Returns the number of entries evicted (0 or 1).
    pub async fn evict_lru(&self) -> usize {
        let mut stmts = self.statements.write().await;
        let mut fps = self.fingerprints.write().await;

        if stmts.len() <= self.config.max_entries {
            return 0;
        }

        self.evict_lru_inner(&mut stmts, &mut fps)
    }

    // -----------------------------------------------------------------------
    // Internal helpers
    // -----------------------------------------------------------------------

    /// Inner LRU eviction that operates on already-locked maps.
    ///
    /// Removes the single entry with the oldest `last_used` timestamp.
    /// Returns the number of entries evicted (0 or 1).
    fn evict_lru_inner(
        &self,
        stmts: &mut HashMap<PreparedId, PreparedStatement>,
        fps: &mut HashMap<String, PreparedId>,
    ) -> usize {
        if stmts.is_empty() {
            return 0;
        }

        // Find the entry with the oldest `last_used`.
        let oldest_id = stmts
            .iter()
            .min_by_key(|(_, stmt)| stmt.last_used)
            .map(|(id, _)| id.clone());

        if let Some(id) = oldest_id {
            if let Some(stmt) = stmts.remove(&id) {
                let fp = Self::fingerprint(&stmt.original_query);
                fps.remove(&fp);
            }
            self.eviction_count.fetch_add(1, Ordering::Relaxed);
            self.generation.fetch_add(1, Ordering::Relaxed);
            1
        } else {
            0
        }
    }

    /// Check whether a prepared statement has exceeded its TTL.
    fn is_expired(&self, stmt: &PreparedStatement) -> bool {
        let now = Utc::now();
        let ttl = chrono::Duration::seconds(self.config.ttl_seconds as i64);
        now.signed_duration_since(stmt.created_at) > ttl
    }

    /// Normalize a query string for fingerprinting.
    ///
    /// Collapses whitespace, trims, and lowercases known keywords while preserving
    /// the case of identifiers and string literals.
    fn normalize_query(query: &str) -> String {
        // Step 1: Collapse all whitespace into single spaces and trim.
        let collapsed: String = query
            .split_whitespace()
            .collect::<Vec<&str>>()
            .join(" ");

        // Step 2: Lowercase known keywords.
        // We split on whitespace, check each token against the keyword list,
        // and lowercase it if it matches. Non-keyword tokens keep original case.
        let keywords = [
            // SQL/VQL standard keywords
            "SELECT", "WHERE", "FROM", "SEARCH", "LIMIT", "ORDER", "BY", "GROUP",
            "AND", "OR", "NOT", "JOIN", "ON", "AS", "HAVING", "INSERT", "UPDATE",
            "DELETE", "SET", "INTO", "VALUES", "WITH", "UNION", "INTERSECT", "EXCEPT",
            "EXISTS", "BETWEEN", "LIKE", "IN", "IS", "NULL", "TRUE", "FALSE",
            "ASC", "DESC", "DISTINCT", "ALL", "ANY", "SOME", "CASE", "WHEN", "THEN",
            "ELSE", "END",
            // VeriSimDB-specific keywords
            "PROOF", "VERIFY", "DRIFT", "HEXAD", "MODALITY", "TYPE",
            // Modality names (treated as keywords for normalization)
            "GRAPH", "VECTOR", "TENSOR", "SEMANTIC", "DOCUMENT", "TEMPORAL",
        ];

        collapsed
            .split(' ')
            .map(|token| {
                if keywords.contains(&token.to_uppercase().as_str()) {
                    token.to_lowercase()
                } else {
                    token.to_string()
                }
            })
            .collect::<Vec<String>>()
            .join(" ")
    }

    /// Extract parameter placeholder names from a query string.
    ///
    /// Parameters are identified by a `$` prefix followed by one or more word characters
    /// (e.g. `$name`, `$threshold_1`). Duplicates are removed, order preserved.
    fn extract_parameters(query: &str) -> Vec<String> {
        let mut params = Vec::new();
        let mut seen = std::collections::HashSet::new();

        let mut chars = query.chars().peekable();
        while let Some(ch) = chars.next() {
            if ch == '$' {
                let mut name = String::from("$");
                while let Some(&next) = chars.peek() {
                    if next.is_alphanumeric() || next == '_' {
                        name.push(next);
                        chars.next();
                    } else {
                        break;
                    }
                }
                if name.len() > 1 && seen.insert(name.clone()) {
                    params.push(name);
                }
            }
        }

        params
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use crate::plan::{ConditionKind, LogicalPlan, PlanNode, PostProcessing, QuerySource};
    use crate::Modality;

    /// Helper: build a simple logical plan with one graph node.
    fn sample_logical_plan() -> LogicalPlan {
        LogicalPlan {
            source: QuerySource::Hexad,
            nodes: vec![PlanNode {
                modality: Modality::Graph,
                conditions: vec![ConditionKind::Traversal {
                    predicate: "relates_to".to_string(),
                    depth: Some(2),
                }],
                projections: vec!["id".to_string()],
                early_limit: None,
            }],
            post_processing: vec![PostProcessing::Limit { count: 10 }],
        }
    }

    /// Helper: build a physical plan for caching tests.
    fn sample_physical_plan() -> PhysicalPlan {
        use crate::cost::CostEstimate;
        use crate::plan::{ExecutionStrategy, PlanStep};

        PhysicalPlan {
            steps: vec![PlanStep {
                step: 1,
                operation: "Graph traversal (1 conditions)".to_string(),
                modality: Modality::Graph,
                cost: CostEstimate {
                    time_ms: 25.0,
                    estimated_rows: 100,
                    selectivity: 0.1,
                    io_cost: 15.0,
                    cpu_cost: 10.0,
                },
                optimization_hint: Some("depth-limited BFS".to_string()),
                pushed_predicates: vec!["relates_to".to_string()],
            }],
            strategy: ExecutionStrategy::Sequential,
            total_cost: CostEstimate {
                time_ms: 25.0,
                estimated_rows: 100,
                selectivity: 0.1,
                io_cost: 15.0,
                cpu_cost: 10.0,
            },
            notes: vec!["Sequential execution — single modality".to_string()],
        }
    }

    // -- Test 1: Prepare and retrieve a statement --

    #[tokio::test]
    async fn test_prepare_and_retrieve() {
        let cache = PlanCache::new(CacheConfig::default());
        let plan = sample_logical_plan();

        let id = cache.prepare("SEARCH graph WHERE type = $t", plan.clone()).await;
        let stmt = cache.get(&id).await;

        assert!(stmt.is_some(), "prepared statement should be retrievable");
        let stmt = stmt.unwrap();
        assert_eq!(stmt.id, id);
        assert_eq!(stmt.original_query, "SEARCH graph WHERE type = $t");
        assert_eq!(stmt.parameter_names, vec!["$t"]);
        assert_eq!(stmt.use_count, 0);
        assert!(stmt.cached_physical_plan.is_none());
    }

    // -- Test 2: Query fingerprint normalization --

    #[test]
    fn test_fingerprint_normalization() {
        // Whitespace normalization: extra spaces, tabs, newlines should produce same fingerprint.
        let fp1 = PlanCache::fingerprint("SEARCH  graph  WHERE  type = $t");
        let fp2 = PlanCache::fingerprint("SEARCH graph WHERE type = $t");
        let fp3 = PlanCache::fingerprint("SEARCH\tgraph\nWHERE\ttype = $t");
        assert_eq!(fp1, fp2, "extra whitespace should not change fingerprint");
        assert_eq!(fp2, fp3, "tabs/newlines should not change fingerprint");

        // Keyword case normalization.
        let fp4 = PlanCache::fingerprint("search GRAPH where TYPE = $t");
        assert_eq!(fp1, fp4, "keyword case should not change fingerprint");

        // Different queries should produce different fingerprints.
        let fp_other = PlanCache::fingerprint("SEARCH vector WHERE k = 10");
        assert_ne!(fp1, fp_other, "different queries must have different fingerprints");
    }

    // -- Test 3: Lookup by query (cache hit) --

    #[tokio::test]
    async fn test_lookup_by_query_hit() {
        let cache = PlanCache::new(CacheConfig::default());
        let plan = sample_logical_plan();

        let id = cache.prepare("SEARCH graph WHERE type = $t", plan).await;
        let found = cache.lookup_by_query("SEARCH graph WHERE type = $t").await;

        assert_eq!(found, Some(id));
    }

    // -- Test 4: Cache miss returns None --

    #[tokio::test]
    async fn test_cache_miss_returns_none() {
        let cache = PlanCache::new(CacheConfig::default());

        let id = PreparedId::new("nonexistent");
        assert!(cache.get(&id).await.is_none(), "missing ID should return None");

        let found = cache.lookup_by_query("SELECT * FROM nowhere").await;
        assert!(found.is_none(), "unknown query should return None");
    }

    // -- Test 5: Invalidate specific statement --

    #[tokio::test]
    async fn test_invalidate_specific() {
        let cache = PlanCache::new(CacheConfig::default());
        let plan = sample_logical_plan();

        let id = cache.prepare("SEARCH graph WHERE type = $t", plan).await;
        assert!(cache.get(&id).await.is_some());

        let removed = cache.invalidate(&id).await;
        assert!(removed, "invalidate should return true for existing entry");
        assert!(cache.get(&id).await.is_none(), "entry should be gone after invalidation");

        let removed_again = cache.invalidate(&id).await;
        assert!(!removed_again, "invalidate on missing entry should return false");
    }

    // -- Test 6: Invalidate all --

    #[tokio::test]
    async fn test_invalidate_all() {
        let cache = PlanCache::new(CacheConfig::default());
        let plan = sample_logical_plan();

        let id1 = cache.prepare("SEARCH graph WHERE type = $t", plan.clone()).await;
        let id2 = cache.prepare("SEARCH vector WHERE k = 5", plan).await;

        assert!(cache.get(&id1).await.is_some());
        assert!(cache.get(&id2).await.is_some());

        cache.invalidate_all().await;

        assert!(cache.get(&id1).await.is_none());
        assert!(cache.get(&id2).await.is_none());

        let stats = cache.stats_async().await;
        assert_eq!(stats.total_entries, 0);
    }

    // -- Test 7: Execute increments use_count and updates last_used --

    #[tokio::test]
    async fn test_execute_increments_counters() {
        let cache = PlanCache::new(CacheConfig::default());
        let plan = sample_logical_plan();

        let id = cache.prepare("SEARCH graph WHERE type = $t", plan).await;

        let mut params = HashMap::new();
        params.insert("$t".to_string(), ParamValue::String("Person".to_string()));

        let stmt = cache.execute_prepared(&id, &params).await.unwrap();
        assert_eq!(stmt.use_count, 1, "first execute should set use_count to 1");

        let stmt2 = cache.execute_prepared(&id, &params).await.unwrap();
        assert_eq!(stmt2.use_count, 2, "second execute should set use_count to 2");
        assert!(
            stmt2.last_used >= stmt.last_used,
            "last_used should advance on execute"
        );
    }

    // -- Test 8: Evict expired entries --

    #[tokio::test]
    async fn test_evict_expired() {
        // Use a TTL of 0 seconds so everything expires immediately.
        let config = CacheConfig {
            ttl_seconds: 0,
            ..CacheConfig::default()
        };
        let cache = PlanCache::new(config);
        let plan = sample_logical_plan();

        cache.prepare("SEARCH graph WHERE type = $t", plan.clone()).await;
        cache.prepare("SEARCH vector WHERE k = 5", plan).await;

        // Sleep briefly to ensure the TTL check sees them as expired.
        tokio::time::sleep(tokio::time::Duration::from_millis(10)).await;

        let evicted = cache.evict_expired().await;
        assert_eq!(evicted, 2, "both entries should be evicted");

        let stats = cache.stats_async().await;
        assert_eq!(stats.total_entries, 0);
    }

    // -- Test 9: Evict LRU when over limit --

    #[tokio::test]
    async fn test_evict_lru_when_over_limit() {
        let config = CacheConfig {
            max_entries: 2,
            ..CacheConfig::default()
        };
        let cache = PlanCache::new(config);
        let plan = sample_logical_plan();

        // Prepare two entries (at capacity).
        let id1 = cache.prepare("SEARCH graph WHERE type = $t", plan.clone()).await;
        // Brief pause so id1 has older last_used than id2.
        tokio::time::sleep(tokio::time::Duration::from_millis(5)).await;
        let _id2 = cache.prepare("SEARCH vector WHERE k = 5", plan.clone()).await;

        // Preparing a third should evict the LRU (id1).
        let _id3 = cache.prepare("SEARCH document WHERE text = $q", plan).await;

        let stats = cache.stats_async().await;
        assert_eq!(stats.total_entries, 2, "cache should stay at max_entries");

        assert!(
            cache.get(&id1).await.is_none(),
            "oldest entry (id1) should have been evicted"
        );
    }

    // -- Test 10: Parameter mismatch error --

    #[tokio::test]
    async fn test_parameter_mismatch_error() {
        let cache = PlanCache::new(CacheConfig::default());
        let plan = sample_logical_plan();

        let id = cache.prepare("SEARCH graph WHERE type = $t AND name = $n", plan).await;

        // Provide wrong parameter names.
        let mut params = HashMap::new();
        params.insert("$wrong".to_string(), ParamValue::String("test".to_string()));

        let result = cache.execute_prepared(&id, &params).await;
        assert!(result.is_err(), "mismatched params should return error");

        match result.unwrap_err() {
            CacheError::ParameterMismatch { expected, provided } => {
                assert!(expected.contains(&"$t".to_string()));
                assert!(expected.contains(&"$n".to_string()));
                assert!(provided.contains(&"$wrong".to_string()));
            }
            other => panic!("expected ParameterMismatch, got: {:?}", other),
        }
    }

    // -- Test 11: Cache stats tracking --

    #[tokio::test]
    async fn test_cache_stats_tracking() {
        let cache = PlanCache::new(CacheConfig::default());
        let plan = sample_logical_plan();

        // Initial stats: all zeros.
        let stats = cache.stats_async().await;
        assert_eq!(stats.total_entries, 0);
        assert_eq!(stats.hit_count, 0);
        assert_eq!(stats.miss_count, 0);
        assert_eq!(stats.hit_ratio, 0.0);

        // Prepare a statement.
        let id = cache.prepare("SEARCH graph WHERE type = $t", plan).await;

        // Cache hit.
        let _ = cache.get(&id).await;
        let stats = cache.stats_async().await;
        assert_eq!(stats.hit_count, 1);
        assert_eq!(stats.total_entries, 1);

        // Cache miss.
        let _ = cache.get(&PreparedId::new("nonexistent")).await;
        let stats = cache.stats_async().await;
        assert_eq!(stats.miss_count, 1);

        // Hit ratio should be 0.5 (1 hit, 1 miss).
        assert!((stats.hit_ratio - 0.5).abs() < f64::EPSILON);

        // Generation should have incremented from prepare + any mutations.
        assert!(stats.generation > 0, "generation should be non-zero after mutations");
    }

    // -- Test 12: Plan caching on prepared statement --

    #[tokio::test]
    async fn test_plan_caching() {
        let cache = PlanCache::new(CacheConfig::default());
        let logical = sample_logical_plan();
        let physical = sample_physical_plan();

        let id = cache.prepare("SEARCH graph WHERE type = $t", logical).await;

        // Initially no cached physical plan.
        let stmt = cache.get(&id).await.unwrap();
        assert!(stmt.cached_physical_plan.is_none());

        // Cache the physical plan.
        cache.cache_plan(&id, physical).await;

        // Now it should be present.
        let stmt = cache.get(&id).await.unwrap();
        assert!(
            stmt.cached_physical_plan.is_some(),
            "physical plan should be cached"
        );
        let plan = stmt.cached_physical_plan.unwrap();
        assert_eq!(plan.steps.len(), 1);
        assert_eq!(plan.steps[0].modality, Modality::Graph);
    }

    // -- Test 13: JSON serialization round-trip --

    #[tokio::test]
    async fn test_json_serialization_roundtrip() {
        let cache = PlanCache::new(CacheConfig::default());
        let logical = sample_logical_plan();
        let physical = sample_physical_plan();

        let id = cache.prepare("SEARCH graph WHERE type = $t", logical).await;
        cache.cache_plan(&id, physical).await;

        let stmt = cache.get(&id).await.unwrap();

        // Serialize to JSON.
        let json = serde_json::to_string_pretty(&stmt).unwrap();
        assert!(!json.is_empty());

        // Deserialize back.
        let parsed: PreparedStatement = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed.id, stmt.id);
        assert_eq!(parsed.original_query, stmt.original_query);
        assert_eq!(parsed.parameter_names, stmt.parameter_names);
        assert_eq!(parsed.use_count, stmt.use_count);
        assert!(parsed.cached_physical_plan.is_some());

        // CacheConfig round-trip.
        let config = CacheConfig::default();
        let config_json = serde_json::to_string(&config).unwrap();
        let parsed_config: CacheConfig = serde_json::from_str(&config_json).unwrap();
        assert_eq!(parsed_config.max_entries, config.max_entries);
        assert_eq!(parsed_config.ttl_seconds, config.ttl_seconds);

        // CacheStats round-trip.
        let stats = cache.stats_async().await;
        let stats_json = serde_json::to_string(&stats).unwrap();
        let parsed_stats: CacheStats = serde_json::from_str(&stats_json).unwrap();
        assert_eq!(parsed_stats.total_entries, stats.total_entries);

        // CacheError round-trip.
        let err = CacheError::ParameterMismatch {
            expected: vec!["$a".to_string()],
            provided: vec!["$b".to_string()],
        };
        let err_json = serde_json::to_string(&err).unwrap();
        let parsed_err: CacheError = serde_json::from_str(&err_json).unwrap();
        match parsed_err {
            CacheError::ParameterMismatch { expected, provided } => {
                assert_eq!(expected, vec!["$a"]);
                assert_eq!(provided, vec!["$b"]);
            }
            _ => panic!("wrong error variant after deserialization"),
        }

        // ParamValue round-trip.
        let params = vec![
            ParamValue::String("hello".to_string()),
            ParamValue::Int(42),
            ParamValue::Float(3.14),
            ParamValue::Bool(true),
            ParamValue::Vector(vec![0.1, 0.2, 0.3]),
            ParamValue::Null,
        ];
        for pv in &params {
            let pv_json = serde_json::to_string(pv).unwrap();
            let parsed_pv: ParamValue = serde_json::from_str(&pv_json).unwrap();
            // Verify the variant matches (structural equality check).
            let re_json = serde_json::to_string(&parsed_pv).unwrap();
            assert_eq!(pv_json, re_json);
        }
    }

    // -- Test 14: Duplicate prepare returns same ID --

    #[tokio::test]
    async fn test_duplicate_prepare_returns_same_id() {
        let cache = PlanCache::new(CacheConfig::default());
        let plan = sample_logical_plan();

        let id1 = cache.prepare("SEARCH graph WHERE type = $t", plan.clone()).await;
        let id2 = cache.prepare("SEARCH graph WHERE type = $t", plan).await;

        assert_eq!(id1, id2, "same query should produce same PreparedId");

        let stats = cache.stats_async().await;
        assert_eq!(stats.total_entries, 1, "only one entry should exist");
    }

    // -- Test 15: Parameter extraction --

    #[test]
    fn test_parameter_extraction() {
        let params = PlanCache::extract_parameters("SEARCH graph WHERE type = $t AND name = $name");
        assert_eq!(params, vec!["$t", "$name"]);

        // Duplicate parameters should be deduplicated.
        let params = PlanCache::extract_parameters("WHERE $x > 1 AND $x < 10");
        assert_eq!(params, vec!["$x"]);

        // No parameters.
        let params = PlanCache::extract_parameters("SEARCH graph");
        assert!(params.is_empty());

        // Dollar sign at end of string.
        let params = PlanCache::extract_parameters("value = $");
        assert!(params.is_empty());
    }

    // -- Test 16: PreparedId display --

    #[test]
    fn test_prepared_id_display() {
        let id = PreparedId::new("abcdef1234567890");
        let display = format!("{}", id);
        assert_eq!(display, "prep_abcdef123456");

        // Short ID (less than 12 chars).
        let id_short = PreparedId::new("abc");
        let display_short = format!("{}", id_short);
        assert_eq!(display_short, "prep_abc");
    }
}
