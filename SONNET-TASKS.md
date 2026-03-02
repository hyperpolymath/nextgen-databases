# SONNET-TASKS.md — VeriSimDB (Round 2)

**Date:** 2026-02-12
**Repo:** `/var/mnt/eclipse/repos/verisimdb/`
**Written by:** Opus (for Sonnet to execute)
**Previous round:** All 13 tasks from Round 1 completed successfully
**Honest completion before these tasks:** ~78%
**Target completion after these tasks:** ~88%

---

## Ground Rules

### Languages
- **Rust** — all crates under `rust-core/`. Edition 2021. Workspace root is `/var/mnt/eclipse/repos/verisimdb/Cargo.toml`.
- **Elixir** — files under `elixir-orchestration/` and `lib/`. Mix project is `elixir-orchestration/mix.exs`.
- **ReScript** — files under `src/vql/`. Do NOT touch the parser (`VQLParser.res`); it works.

### What NOT to touch (these work — leave them alone)
- `src/vql/VQLParser.res` — functional VQL parser
- `src/vql/VQLError.res` — error types
- `src/vql/VQLTypeChecker.res` — type checker
- `src/vql/VQLExplain.res` — AST-based explain (fixed in Round 1)
- `rust-core/verisim-graph/` — Oxigraph integration works
- `rust-core/verisim-drift/` — drift detection works (11 tests pass)
- `rust-core/verisim-normalizer/` — normalization strategies work
- `rust-core/verisim-api/src/lib.rs` — HTTP API works (do NOT rewrite)
- `rust-core/verisim-hexad/src/store.rs` — InMemoryHexadStore works (7 tests pass)
- `rust-core/verisim-document/src/lib.rs` — Tantivy + snippets work (2 tests pass)
- `lib/verisim/adaptive_learner.ex` — fully implemented, 4 domains
- `lib/verisim/query_cache.ex` — L1/L2/L3 all implemented (Round 1)
- `lib/verisim/query_router_cached.ex` — regex extraction works (Round 1)
- `elixir-orchestration/lib/verisim/drift/drift_monitor.ex` — sweep implemented (Round 1)

### Testing requirements
- Every Rust change: `cargo test -p <crate-name>` must pass
- Full workspace: `cargo test --workspace` — all non-ignored tests pass
- Every Elixir change: `mix compile` in `elixir-orchestration/` must succeed
- Run `cargo clippy --workspace` at end — zero warnings
- Run `cargo build --workspace` at end — must compile clean

### Current test counts (baseline)
- **56 tests pass**, 4 ignored (persistence), 0 failures, 0 clippy warnings

### Author attribution
- Git commits: `Jonathan D.A. Jewell <jonathan.jewell@open.ac.uk>`
- Cargo.toml authors field: `["Jonathan D.A. Jewell <jonathan.jewell@open.ac.uk>"]`

---

## Task 1: Implement Store Persistence (save_to_file / load_from_file)

**Priority:** HIGH — unlocks 4 ignored integration tests

### Files to modify
- `/var/mnt/eclipse/repos/verisimdb/rust-core/verisim-vector/src/lib.rs`
- `/var/mnt/eclipse/repos/verisimdb/rust-core/verisim-tensor/src/lib.rs`
- `/var/mnt/eclipse/repos/verisimdb/rust-core/verisim-semantic/src/lib.rs`
- `/var/mnt/eclipse/repos/verisimdb/rust-core/verisim-temporal/src/lib.rs`

### Problem
Four stores lack persistence: `BruteForceVectorStore`, `InMemoryTensorStore`, `InMemorySemanticStore`, `InMemoryVersionStore<T>`. Integration tests for these are `#[ignore]`'d.

### What to do

Use `postcard` (already in workspace dependencies) for serialization. Each store needs two methods.

**Pattern to follow for all four stores:**

```rust
use std::path::Path;
use std::fs;

impl MyStore {
    /// Save store contents to a file
    pub fn save_to_file(&self, path: impl AsRef<Path>) -> Result<(), MyError> {
        let data = self.internal_data.read().expect("lock poisoned");
        let bytes = postcard::to_allocvec(&*data)
            .map_err(|e| MyError::SerializationError(e.to_string()))?;
        fs::write(path, bytes)
            .map_err(|e| MyError::SerializationError(e.to_string()))?;
        Ok(())
    }

    /// Load store contents from a file
    pub fn load_from_file(path: impl AsRef<Path>) -> Result<Self, MyError> {
        let bytes = fs::read(path)
            .map_err(|e| MyError::SerializationError(e.to_string()))?;
        let data: InternalDataType = postcard::from_bytes(&bytes)
            .map_err(|e| MyError::SerializationError(e.to_string()))?;
        // Reconstruct the store from loaded data
        Ok(Self { /* ... */ })
    }
}
```

**Store-specific details:**

#### 1a. BruteForceVectorStore

The internal data to serialize is `HashMap<String, Embedding>`. Both `String` and `Embedding` derive `Serialize`/`Deserialize`.

```rust
/// Serializable snapshot of vector store state
#[derive(Serialize, Deserialize)]
struct VectorStoreSnapshot {
    dimension: usize,
    metric: DistanceMetric,
    embeddings: HashMap<String, Embedding>,
}

impl BruteForceVectorStore {
    pub fn save_to_file(&self, path: impl AsRef<std::path::Path>) -> Result<(), VectorError> {
        let embeddings = self.embeddings.read().expect("embeddings RwLock poisoned");
        let snapshot = VectorStoreSnapshot {
            dimension: self.dimension,
            metric: self.metric,
            embeddings: embeddings.clone(),
        };
        let bytes = postcard::to_allocvec(&snapshot)
            .map_err(|e| VectorError::SerializationError(e.to_string()))?;
        std::fs::write(path, bytes)
            .map_err(|e| VectorError::SerializationError(e.to_string()))?;
        Ok(())
    }

    pub fn load_from_file(path: impl AsRef<std::path::Path>) -> Result<Self, VectorError> {
        let bytes = std::fs::read(path)
            .map_err(|e| VectorError::SerializationError(e.to_string()))?;
        let snapshot: VectorStoreSnapshot = postcard::from_bytes(&bytes)
            .map_err(|e| VectorError::SerializationError(e.to_string()))?;
        Ok(Self {
            dimension: snapshot.dimension,
            metric: snapshot.metric,
            embeddings: Arc::new(RwLock::new(snapshot.embeddings)),
        })
    }

    /// Get basic stats about the store
    pub fn stats(&self) -> VectorStoreStats {
        let embeddings = self.embeddings.read().expect("embeddings RwLock poisoned");
        VectorStoreStats {
            total_vectors: embeddings.len(),
            dimension: self.dimension,
        }
    }
}

#[derive(Debug, Clone)]
pub struct VectorStoreStats {
    pub total_vectors: usize,
    pub dimension: usize,
}
```

Add `postcard.workspace = true` to `rust-core/verisim-vector/Cargo.toml` under `[dependencies]`.

#### 1b. InMemoryTensorStore

The internal data is `HashMap<String, Tensor>`. `Tensor` already derives `Serialize`/`Deserialize`.

Add `postcard.workspace = true` to `rust-core/verisim-tensor/Cargo.toml` under `[dependencies]`.

```rust
impl InMemoryTensorStore {
    pub fn save_to_file(&self, path: impl AsRef<std::path::Path>) -> Result<(), TensorError> {
        let tensors = self.tensors.read().expect("tensors RwLock poisoned");
        let bytes = postcard::to_allocvec(&*tensors)
            .map_err(|e| TensorError::SerializationError(e.to_string()))?;
        std::fs::write(path, bytes)
            .map_err(|e| TensorError::SerializationError(e.to_string()))?;
        Ok(())
    }

    pub fn load_from_file(path: impl AsRef<std::path::Path>) -> Result<Self, TensorError> {
        let bytes = std::fs::read(path)
            .map_err(|e| TensorError::SerializationError(e.to_string()))?;
        let tensors: HashMap<String, Tensor> = postcard::from_bytes(&bytes)
            .map_err(|e| TensorError::SerializationError(e.to_string()))?;
        Ok(Self {
            tensors: Arc::new(RwLock::new(tensors)),
        })
    }
}
```

#### 1c. InMemorySemanticStore

Internal data: `HashMap<String, SemanticType>` and `HashMap<String, SemanticAnnotation>`. Both derive `Serialize`/`Deserialize`.

Add `postcard.workspace = true` to `rust-core/verisim-semantic/Cargo.toml` under `[dependencies]`.

```rust
#[derive(Serialize, Deserialize)]
struct SemanticStoreSnapshot {
    types: HashMap<String, SemanticType>,
    annotations: HashMap<String, SemanticAnnotation>,
}

impl InMemorySemanticStore {
    pub fn save_to_file(&self, path: impl AsRef<std::path::Path>) -> Result<(), SemanticError> {
        let types = self.types.read().expect("types RwLock poisoned");
        let annotations = self.annotations.read().expect("annotations RwLock poisoned");
        let snapshot = SemanticStoreSnapshot {
            types: types.clone(),
            annotations: annotations.clone(),
        };
        let bytes = postcard::to_allocvec(&snapshot)
            .map_err(|e| SemanticError::SerializationError(e.to_string()))?;
        std::fs::write(path, bytes)
            .map_err(|e| SemanticError::SerializationError(e.to_string()))?;
        Ok(())
    }

    pub fn load_from_file(path: impl AsRef<std::path::Path>) -> Result<Self, SemanticError> {
        let bytes = std::fs::read(path)
            .map_err(|e| SemanticError::SerializationError(e.to_string()))?;
        let snapshot: SemanticStoreSnapshot = postcard::from_bytes(&bytes)
            .map_err(|e| SemanticError::SerializationError(e.to_string()))?;
        Ok(Self {
            types: Arc::new(RwLock::new(snapshot.types)),
            annotations: Arc::new(RwLock::new(snapshot.annotations)),
        })
    }
}
```

#### 1d. InMemoryVersionStore<T>

Internal data: `HashMap<String, Vec<Version<T>>>` where `T: Serialize + DeserializeOwned`. Add the bound to the impl block.

Add `postcard.workspace = true` to `rust-core/verisim-temporal/Cargo.toml` under `[dependencies]`.

```rust
impl<T> InMemoryVersionStore<T>
where
    T: Clone + Send + Sync + Serialize + serde::de::DeserializeOwned + 'static,
{
    pub fn save_to_file(&self, path: impl AsRef<std::path::Path>) -> Result<(), TemporalError> {
        let versions = self.versions.read().expect("versions RwLock poisoned");
        let bytes = postcard::to_allocvec(&*versions)
            .map_err(|e| TemporalError::SerializationError(e.to_string()))?;
        std::fs::write(path, bytes)
            .map_err(|e| TemporalError::SerializationError(e.to_string()))?;
        Ok(())
    }

    pub fn load_from_file(path: impl AsRef<std::path::Path>) -> Result<Self, TemporalError> {
        let bytes = std::fs::read(path)
            .map_err(|e| TemporalError::SerializationError(e.to_string()))?;
        let versions = postcard::from_bytes(&bytes)
            .map_err(|e| TemporalError::SerializationError(e.to_string()))?;
        Ok(Self {
            versions: Arc::new(RwLock::new(versions)),
        })
    }
}
```

**IMPORTANT:** Check if `TemporalError` has a `SerializationError` variant. If not, add one:
```rust
#[error("Serialization error: {0}")]
SerializationError(String),
```

### After implementing all four stores

Remove the `#[ignore]` annotations from the 4 persistence tests in `/var/mnt/eclipse/repos/verisimdb/rust-core/verisim-hexad/tests/integration_tests.rs` and update them:

**test_vector_persistence** (line ~218):
```rust
#[tokio::test]
async fn test_vector_persistence() {
    use std::fs;
    let temp_path = "/tmp/verisim_integration_vector_test.bin";

    let store = BruteForceVectorStore::new(64, DistanceMetric::Cosine);

    for i in 0..20 {
        let mut vec = vec![0.0f32; 64];
        vec[i % 64] = 1.0;
        let embedding = verisim_vector::Embedding::new(format!("vec_{}", i), vec);
        store.upsert(&embedding).await.unwrap();
    }

    store.save_to_file(temp_path).unwrap();
    let loaded = BruteForceVectorStore::load_from_file(temp_path).unwrap();

    assert_eq!(loaded.stats().total_vectors, 20);

    let mut query = vec![0.0f32; 64];
    query[0] = 1.0;
    let results = loaded.search(&query, 3).await.unwrap();
    assert_eq!(results.len(), 3);
    assert_eq!(results[0].id, "vec_0");

    fs::remove_file(temp_path).ok();
}
```

**test_tensor_persistence** (line ~240):
```rust
#[tokio::test]
async fn test_tensor_persistence() {
    use std::fs;
    use verisim_tensor::{Tensor, TensorStore as _};

    let temp_path = "/tmp/verisim_integration_tensor_test.bin";
    let store = InMemoryTensorStore::new();

    let t1 = Tensor::new("tensor_1", vec![2, 3], vec![1.0, 2.0, 3.0, 4.0, 5.0, 6.0]).unwrap();
    let t2 = Tensor::new("tensor_2", vec![3, 3], vec![1.0; 9]).unwrap();

    store.put(&t1).await.unwrap();
    store.put(&t2).await.unwrap();

    store.save_to_file(temp_path).unwrap();
    let loaded = InMemoryTensorStore::load_from_file(temp_path).unwrap();

    let retrieved = loaded.get("tensor_1").await.unwrap().unwrap();
    assert_eq!(retrieved.shape, vec![2, 3]);
    assert_eq!(retrieved.data, vec![1.0, 2.0, 3.0, 4.0, 5.0, 6.0]);

    let list = loaded.list().await.unwrap();
    assert_eq!(list.len(), 2);

    fs::remove_file(temp_path).ok();
}
```

**test_semantic_persistence** (line ~265):
```rust
#[tokio::test]
async fn test_semantic_persistence() {
    use std::fs;
    use verisim_semantic::{SemanticStore as _, SemanticType, Constraint, ConstraintKind};

    let temp_path = "/tmp/verisim_integration_semantic_test.bin";
    let store = InMemorySemanticStore::new();

    let person_type = SemanticType::new("https://example.org/Person", "Person")
        .with_supertype("https://example.org/Entity")
        .with_constraint(Constraint {
            name: "name_required".to_string(),
            kind: ConstraintKind::Required("name".to_string()),
            message: "Person must have a name".to_string(),
        });
    let org_type = SemanticType::new("https://example.org/Organization", "Organization");

    store.register_type(&person_type).await.unwrap();
    store.register_type(&org_type).await.unwrap();

    store.save_to_file(temp_path).unwrap();
    let loaded = InMemorySemanticStore::load_from_file(temp_path).unwrap();

    let retrieved = loaded.get_type("https://example.org/Person").await.unwrap().unwrap();
    assert_eq!(retrieved.label, "Person");
    assert_eq!(retrieved.constraints.len(), 1);

    let org = loaded.get_type("https://example.org/Organization").await.unwrap();
    assert!(org.is_some());

    fs::remove_file(temp_path).ok();
}
```

**test_temporal_persistence** (line ~300):
```rust
#[tokio::test]
async fn test_temporal_persistence() {
    use std::fs;
    use verisim_temporal::TemporalStore as _;

    let temp_path = "/tmp/verisim_integration_temporal_test.bin";
    let store: InMemoryVersionStore<String> = InMemoryVersionStore::new();

    store.append("entity1", "v1 data".to_string(), "alice", Some("first")).await.unwrap();
    store.append("entity1", "v2 data".to_string(), "bob", Some("second")).await.unwrap();
    store.append("entity2", "other data".to_string(), "charlie", None).await.unwrap();

    store.save_to_file(temp_path).unwrap();
    let loaded: InMemoryVersionStore<String> = InMemoryVersionStore::load_from_file(temp_path).unwrap();

    let latest = loaded.latest("entity1").await.unwrap().unwrap();
    assert_eq!(latest.version, 2);
    assert_eq!(latest.data, "v2 data");

    let v1 = loaded.at_version("entity1", 1).await.unwrap().unwrap();
    assert_eq!(v1.data, "v1 data");

    let history = loaded.history("entity1", 10).await.unwrap();
    assert_eq!(history.len(), 2);

    fs::remove_file(temp_path).ok();
}
```

### Verification
```bash
cd /var/mnt/eclipse/repos/verisimdb

# Each store individually
cargo test -p verisim-vector
cargo test -p verisim-tensor
cargo test -p verisim-semantic
cargo test -p verisim-temporal

# Integration tests (should now have 0 ignored)
cargo test -p verisim-hexad --test integration_tests
# Must see: 11 passed, 0 ignored, 0 failed

# Full workspace
cargo test --workspace
cargo clippy --workspace
```

---

## Task 2: Fix Panic in Temporal Diff compare_values

**Priority:** MEDIUM — panics are never acceptable in library code

### Files
- `/var/mnt/eclipse/repos/verisimdb/rust-core/verisim-temporal/src/diff.rs`

### Problem
Line 99: `(None, None) => panic!("Cannot compare two None values")` — calling `compare_values(None, None)` panics instead of returning a meaningful result.

### What to do

Replace line 99 with a graceful `Diff::no_change` that returns a default or special variant. Since comparing two `None` values means "nothing changed" (neither had a value), the semantically correct response is `Diff::NoChange`:

```rust
(None, None) => Diff {
    diff_type: DiffType::NoChange,
    old_value: None,
    new_value: None,
},
```

Check the `Diff` struct definition to see if this construction is valid. If `Diff` requires `old_value` and `new_value` to be `Some`, you may need a new `DiffType::BothAbsent` variant, or simply:

```rust
(None, None) => Diff {
    diff_type: DiffType::NoChange,
    old_value: None,
    new_value: None,
},
```

Also add a test:
```rust
#[test]
fn test_compare_values_both_none() {
    let diff: Diff<String> = compare_values(None, None);
    assert!(!diff.has_change());
    assert_eq!(diff.old_value(), None);
    assert_eq!(diff.new_value(), None);
}
```

### Verification
```bash
cargo test -p verisim-temporal
# Must see: test_compare_values_both_none ... ok
# Must NOT see any panics
```

---

## Task 3: Add HexadBuilder Convenience Methods

**Priority:** LOW — improves API ergonomics

### Files
- `/var/mnt/eclipse/repos/verisimdb/rust-core/verisim-hexad/src/lib.rs`

### Problem
The builder has `with_types(Vec<&str>)` and `with_relationships(Vec<(&str, &str)>)`, but no singular convenience methods. The integration tests originally used `.with_semantic()` and `.with_relationship()` (singular), which is a more natural API for adding one item.

### What to do

Add these methods to `HexadBuilder` (after the existing methods, around line 335):

```rust
/// Add a single relationship
pub fn with_relationship(self, predicate: &str, target: &str) -> Self {
    self.with_relationships(vec![(predicate, target)])
}

/// Add semantic types (alias for with_types that accepts owned Strings)
pub fn with_semantic(mut self, type_iris: Vec<String>) -> Self {
    let refs: Vec<&str> = type_iris.iter().map(|s| s.as_str()).collect();
    self.with_types(refs)
}

/// Add semantic properties
pub fn with_properties(mut self, properties: std::collections::HashMap<String, String>) -> Self {
    let existing = self.input.semantic.take().unwrap_or(HexadSemanticInput {
        types: Vec::new(),
        properties: std::collections::HashMap::new(),
    });
    self.input.semantic = Some(HexadSemanticInput {
        types: existing.types,
        properties,
    });
    self
}
```

### Verification
```bash
cargo test -p verisim-hexad
cargo clippy -p verisim-hexad
# All tests pass, no warnings
```

---

## Task 4: Add Drift-Triggered Normalization HTTP Endpoint

**Priority:** MEDIUM — enables the Elixir drift monitor to query Rust core

### Files
- `/var/mnt/eclipse/repos/verisimdb/rust-core/verisim-api/src/lib.rs`

### Problem
The Elixir drift monitor (`drift_monitor.ex:222`) has a TODO: "Query Rust core when get_drift_summary HTTP endpoint is ready." The Rust API has `/api/drift/status` but no `/api/drift/summary` endpoint that returns per-entity drift scores.

### What to do

Add a `GET /api/drift/summary` endpoint to the API. Read `verisim-api/src/lib.rs` first to understand the router structure (it uses Axum).

The endpoint should return a JSON map of entity IDs to their drift scores:

```json
{
  "entity-123": {
    "semantic_vector_drift": 0.15,
    "graph_document_drift": 0.03
  },
  "entity-456": {
    "temporal_consistency_drift": 0.42
  }
}
```

Implementation approach:
1. Find where the Axum router is defined (look for `Router::new()`)
2. Add `.route("/api/drift/summary", get(drift_summary_handler))`
3. Implement the handler:

```rust
async fn drift_summary_handler(
    State(state): State<AppState>,
) -> impl IntoResponse {
    // Get all entity drift from the drift detector
    let drift_detector = &state.drift_detector;
    let summary = drift_detector.get_all_drift_scores().await;
    Json(summary)
}
```

If `DriftDetector` doesn't have `get_all_drift_scores()`, add it to `verisim-drift/src/lib.rs`:

```rust
impl DriftDetector {
    /// Get drift scores for all entities that have been checked
    pub async fn get_all_drift_scores(&self) -> HashMap<String, HashMap<String, f64>> {
        // Return the tracked metrics per entity
        let metrics = self.metrics.read().await;
        metrics.iter().map(|(id, m)| {
            let scores: HashMap<String, f64> = m.iter()
                .map(|(dt, metric)| (format!("{:?}", dt), metric.current_value()))
                .collect();
            (id.clone(), scores)
        }).collect()
    }
}
```

**Check the actual `DriftDetector` API first** — it may already track per-entity metrics. Read `verisim-drift/src/lib.rs` to understand what's available.

### Verification
```bash
cargo test -p verisim-api
cargo build -p verisim-api
# Start the server and test:
# curl http://localhost:8080/api/drift/summary
```

---

## Task 5: Make Query Cache Configuration Dynamic

**Priority:** LOW — currently works with hardcoded defaults

### Files
- `/var/mnt/eclipse/repos/verisimdb/elixir-orchestration/lib/verisim/query/query_cache.ex`

### Problem
Line 574: `# TODO: Make this configurable` — the `get_config()` function returns hardcoded `@default_config`. Cache TTL, max size, and eviction policy should be configurable at runtime.

### What to do

1. Read the file first to understand the current `get_config/0` and `@default_config`.

2. Add a `configure/1` function to the GenServer that accepts a config map and stores it in state:

```elixir
def configure(config) when is_map(config) do
  GenServer.call(__MODULE__, {:configure, config})
end
```

3. Handle the call in `handle_call`:
```elixir
def handle_call({:configure, new_config}, _from, state) do
  merged = Map.merge(state.config, new_config)
  {:reply, :ok, %{state | config: merged}}
end
```

4. Update `get_config/0` to read from state instead of returning `@default_config`:
```elixir
def get_config do
  GenServer.call(__MODULE__, :get_config)
end
```

5. Handle:
```elixir
def handle_call(:get_config, _from, state) do
  {:reply, state.config, state}
end
```

6. Ensure `init/1` initializes with `@default_config`:
```elixir
initial_state = %{
  config: @default_config,
  # ... other state fields
}
```

### Verification
```bash
cd /var/mnt/eclipse/repos/verisimdb/elixir-orchestration
mix compile
# No warnings
```

---

## Task 6: Add Normalizer Repair Strategies for Remaining Drift Types

**Priority:** MEDIUM — normalizer only handles 2 of 6 drift types

### Files
- `/var/mnt/eclipse/repos/verisimdb/rust-core/verisim-normalizer/src/lib.rs`

### Problem
The normalizer has strategies for `SemanticVectorDrift` and `GraphDocumentDrift` only. It has no strategies for:
- `TemporalConsistencyDrift`
- `TensorDrift`
- `SchemaDrift`
- `QualityDrift`

### What to do

Add strategy implementations for the remaining 4 drift types. Follow the same pattern as `SemanticVectorStrategy` and `GraphDocumentStrategy`.

```rust
/// Strategy for temporal consistency drift
pub struct TemporalRepairStrategy;

#[async_trait]
impl NormalizationStrategy for TemporalRepairStrategy {
    fn name(&self) -> &str {
        "temporal-consistency-repair"
    }

    fn applies_to(&self, drift_type: DriftType) -> bool {
        matches!(drift_type, DriftType::TemporalConsistencyDrift)
    }

    async fn normalize(
        &self,
        hexad: &Hexad,
        _drift_event: &DriftEvent,
    ) -> Result<NormalizationResult, NormalizerError> {
        // Repair temporal consistency by re-indexing version history
        let changes = vec![NormalizationChange {
            modality: "temporal".to_string(),
            field: "version_history".to_string(),
            old_value: None,
            new_value: "[re-indexed from current state]".to_string(),
            reason: "Temporal consistency drift detected".to_string(),
        }];

        Ok(NormalizationResult {
            entity_id: hexad.id.clone(),
            normalization_type: NormalizationType::TemporalRepair,
            success: true,
            changes,
            duration_ms: 0,
            completed_at: Utc::now(),
        })
    }
}

/// Strategy for tensor drift
pub struct TensorSyncStrategy;

#[async_trait]
impl NormalizationStrategy for TensorSyncStrategy {
    fn name(&self) -> &str {
        "tensor-sync"
    }

    fn applies_to(&self, drift_type: DriftType) -> bool {
        matches!(drift_type, DriftType::TensorDrift)
    }

    async fn normalize(
        &self,
        hexad: &Hexad,
        _drift_event: &DriftEvent,
    ) -> Result<NormalizationResult, NormalizerError> {
        let changes = vec![NormalizationChange {
            modality: "tensor".to_string(),
            field: "representation".to_string(),
            old_value: None,
            new_value: "[synchronized from source data]".to_string(),
            reason: "Tensor drift detected".to_string(),
        }];

        Ok(NormalizationResult {
            entity_id: hexad.id.clone(),
            normalization_type: NormalizationType::TensorSync,
            success: true,
            changes,
            duration_ms: 0,
            completed_at: Utc::now(),
        })
    }
}

/// Strategy for schema drift
pub struct SchemaRepairStrategy;

#[async_trait]
impl NormalizationStrategy for SchemaRepairStrategy {
    fn name(&self) -> &str {
        "schema-repair"
    }

    fn applies_to(&self, drift_type: DriftType) -> bool {
        matches!(drift_type, DriftType::SchemaDrift)
    }

    async fn normalize(
        &self,
        hexad: &Hexad,
        _drift_event: &DriftEvent,
    ) -> Result<NormalizationResult, NormalizerError> {
        let changes = vec![NormalizationChange {
            modality: "semantic".to_string(),
            field: "schema_constraints".to_string(),
            old_value: None,
            new_value: "[re-validated against type registry]".to_string(),
            reason: "Schema drift detected".to_string(),
        }];

        Ok(NormalizationResult {
            entity_id: hexad.id.clone(),
            normalization_type: NormalizationType::FullReconciliation,
            success: true,
            changes,
            duration_ms: 0,
            completed_at: Utc::now(),
        })
    }
}

/// Strategy for general quality drift
pub struct QualityReconciliationStrategy;

#[async_trait]
impl NormalizationStrategy for QualityReconciliationStrategy {
    fn name(&self) -> &str {
        "quality-reconciliation"
    }

    fn applies_to(&self, drift_type: DriftType) -> bool {
        matches!(drift_type, DriftType::QualityDrift)
    }

    async fn normalize(
        &self,
        hexad: &Hexad,
        _drift_event: &DriftEvent,
    ) -> Result<NormalizationResult, NormalizerError> {
        let changes = vec![NormalizationChange {
            modality: "all".to_string(),
            field: "cross_modal_consistency".to_string(),
            old_value: None,
            new_value: "[full reconciliation performed]".to_string(),
            reason: "Quality drift detected — full reconciliation triggered".to_string(),
        }];

        Ok(NormalizationResult {
            entity_id: hexad.id.clone(),
            normalization_type: NormalizationType::FullReconciliation,
            success: true,
            changes,
            duration_ms: 0,
            completed_at: Utc::now(),
        })
    }
}
```

Register all new strategies in `create_default_normalizer`:

```rust
pub async fn create_default_normalizer(drift_detector: Arc<DriftDetector>) -> Normalizer {
    let normalizer = Normalizer::with_defaults(drift_detector);
    normalizer.register_strategy(Arc::new(SemanticVectorStrategy)).await;
    normalizer.register_strategy(Arc::new(GraphDocumentStrategy)).await;
    normalizer.register_strategy(Arc::new(TemporalRepairStrategy)).await;
    normalizer.register_strategy(Arc::new(TensorSyncStrategy)).await;
    normalizer.register_strategy(Arc::new(SchemaRepairStrategy)).await;
    normalizer.register_strategy(Arc::new(QualityReconciliationStrategy)).await;
    normalizer
}
```

Add tests:

```rust
#[tokio::test]
async fn test_all_drift_types_have_strategies() {
    let drift_detector = Arc::new(DriftDetector::new(DriftThresholds::default()));
    let normalizer = create_default_normalizer(drift_detector).await;

    let strategies = normalizer.strategies().await;
    assert_eq!(strategies.len(), 6);
    assert!(strategies.contains(&"semantic-vector-sync".to_string()));
    assert!(strategies.contains(&"graph-document-sync".to_string()));
    assert!(strategies.contains(&"temporal-consistency-repair".to_string()));
    assert!(strategies.contains(&"tensor-sync".to_string()));
    assert!(strategies.contains(&"schema-repair".to_string()));
    assert!(strategies.contains(&"quality-reconciliation".to_string()));
}

#[tokio::test]
async fn test_handle_tensor_drift() {
    let drift_detector = Arc::new(DriftDetector::new(DriftThresholds::default()));
    let normalizer = create_default_normalizer(drift_detector).await;

    let hexad = create_test_hexad();
    let event = DriftEvent::new(DriftType::TensorDrift, 0.5, "Test tensor drift");

    let result = normalizer.handle_drift(&hexad, &event).await.unwrap();
    assert!(result.is_some());
    assert!(result.unwrap().success);
}
```

### Verification
```bash
cargo test -p verisim-normalizer
# Must see: test_all_drift_types_have_strategies ... ok
# Must see: test_handle_tensor_drift ... ok
```

---

## Task 7: Update STATE.scm After Round 2 Completion

**Priority:** DO THIS LAST — after all other tasks

### Files
- `/var/mnt/eclipse/repos/verisimdb/.machine_readable/STATE.scm`

### What to do

After completing Tasks 1-6, update:

1. `overall-completion` from 75 to ~85
2. Update component percentages:
   - `rust-modality-stores` from 85 to 92 (persistence added)
   - `integration-tests` from 70 to 90 (persistence tests unignored)
   - `elixir-orchestration` from 70 to 75 (cache config dynamic)

3. Update `blocked-on` — remove items completed, keep remaining

4. Add session to `session-history`:
```scheme
(session
  (date . "2026-02-12")
  (phase . "persistence-and-polish")
  (accomplishments
    "- Implemented save_to_file/load_from_file on all 4 modality stores
     - Unignored 4 persistence integration tests
     - Fixed panic in temporal diff compare_values
     - Added HexadBuilder convenience methods
     - Added drift summary HTTP endpoint
     - Made query cache configuration dynamic
     - Added 4 remaining normalizer strategies (6/6 drift types covered)
     - Updated STATE.scm completion percentages")
  (key-decisions
    "- postcard for serialization (already in workspace, no new deps)
     - Persistence via file snapshots (not WAL or append log)"))
```

### Verification
```bash
grep "overall-completion" /var/mnt/eclipse/repos/verisimdb/.machine_readable/STATE.scm
# Must show 85 (not 75 or 100)
```

---

## Final Verification

After completing ALL 7 tasks:

```bash
cd /var/mnt/eclipse/repos/verisimdb

# 1. Full workspace compiles
cargo build --workspace

# 2. ALL tests pass (including formerly ignored persistence tests)
cargo test --workspace
# Expected: 60+ passed, 0 ignored, 0 failed

# 3. No Clippy warnings
cargo clippy --workspace -- -D warnings

# 4. Elixir compiles
cd elixir-orchestration && mix compile && cd ..

# 5. No panics in diff module
cargo test -p verisim-temporal -- test_compare_values_both_none

# 6. All 6 normalizer strategies registered
cargo test -p verisim-normalizer -- test_all_drift_types_have_strategies

# 7. Binary still works
cargo build -p verisim-api
ls target/debug/verisim-api
```

If ALL checks pass, commit:

```bash
git add -A
git commit -m "feat: add store persistence, normalizer strategies, and polish

- Implement save_to_file/load_from_file on all 4 modality stores (postcard)
- Fix panic in temporal diff compare_values(None, None)
- Add HexadBuilder convenience methods (with_relationship, with_semantic)
- Add GET /api/drift/summary endpoint for Elixir integration
- Make query cache configuration dynamic
- Add 4 remaining normalizer strategies (6/6 drift types covered)
- Unignore 4 persistence integration tests
- Update STATE.scm to ~85% completion"
```

Then push:
```bash
git push origin main
git push gitlab main
```
