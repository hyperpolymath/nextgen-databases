# verisim-planner Implementation Status

**Last updated:** 2026-02-13
**Author:** Claude Opus 4.6 session
**Recovery doc:** If this machine crashes, this file tells you exactly where things stand.

## Overview

Adding a cost-based query planner (`verisim-planner`) to VeriSimDB's Rust core, plus
triple API (REST + GraphQL + gRPC) and VQL integration.

---

## Phase 1: verisim-planner crate — COMPLETE

**Status:** Done. Builds clean, 39/39 tests pass, zero clippy warnings.

### Files Created

| File | Lines | Status |
|------|-------|--------|
| `rust-core/verisim-planner/Cargo.toml` | 16 | Done |
| `rust-core/verisim-planner/src/lib.rs` | ~120 | Done — Modality enum, re-exports |
| `rust-core/verisim-planner/src/error.rs` | ~20 | Done — PlannerError |
| `rust-core/verisim-planner/src/plan.rs` | ~130 | Done — LogicalPlan, PhysicalPlan, PlanNode |
| `rust-core/verisim-planner/src/cost.rs` | ~220 | Done — CostModel, CostEstimate, BaseCost |
| `rust-core/verisim-planner/src/stats.rs` | ~110 | Done — StatisticsCollector |
| `rust-core/verisim-planner/src/config.rs` | ~100 | Done — PlannerConfig, OptimizationMode |
| `rust-core/verisim-planner/src/optimizer.rs` | ~200 | Done — Planner with optimize() + explain() |
| `rust-core/verisim-planner/src/explain.rs` | ~210 | Done — ExplainOutput text/JSON rendering |

### Files Modified

| File | Change | Status |
|------|--------|--------|
| `Cargo.toml` (workspace root) | Added `verisim-planner` to members | Done |
| `rust-core/verisim-api/Cargo.toml` | Added `verisim-planner` dependency | Done |
| `rust-core/verisim-api/src/lib.rs` | Added Planner to AppState, 5 REST endpoints | Done |

### REST Endpoints Added

| Endpoint | Method | Status |
|----------|--------|--------|
| `/query/plan` | POST | Done |
| `/query/explain` | POST | Done |
| `/planner/config` | GET | Done |
| `/planner/config` | PUT | Done |
| `/planner/stats` | GET | Done |

### Verification

```bash
cargo build -p verisim-planner   # Clean build, 0 warnings
cargo test -p verisim-planner    # 39/39 pass
cargo build -p verisim-api       # Clean build
cargo test -p verisim-api        # 7/7 pass
cargo clippy -p verisim-planner  # 0 warnings
```

---

## Phase 2: Triple API — IN PROGRESS

### 2a. REST — COMPLETE (done in Phase 1)

### 2b. GraphQL — NOT STARTED

**Plan:** Add `async-graphql` + `async-graphql-axum` to verisim-api.

**Dependencies needed:**
```toml
async-graphql = "7"       # Latest stable (8.x is rc only)
async-graphql-axum = "7"
```

**Files to create/modify:**
- `rust-core/verisim-api/src/graphql.rs` — Schema types, Query root, Mutation root
- `rust-core/verisim-api/src/lib.rs` — Add `/graphql` route, add schema to AppState

**GraphQL Schema (planned):**
```graphql
type Query {
  health: Health!
  hexad(id: ID!): Hexad
  searchText(query: String!, limit: Int): [SearchResult!]!
  driftStatus: [DriftStatus!]!
  plannerConfig: PlannerConfig!
  plannerStats: PlannerStats!
  explainPlan(plan: LogicalPlanInput!): ExplainOutput!
}

type Mutation {
  createHexad(input: HexadInput!): Hexad!
  updateHexad(id: ID!, input: HexadInput!): Hexad!
  deleteHexad(id: ID!): Boolean!
  optimizePlan(plan: LogicalPlanInput!): PhysicalPlan!
  updatePlannerConfig(config: PlannerConfigInput!): PlannerConfig!
}
```

**Feasibility:** YES — async-graphql has native axum integration, same AppState pattern. ~200-300 lines.

### 2c. gRPC — NOT STARTED

**Plan:** Add `tonic` + `prost` to workspace, create `.proto` definitions.

**Dependencies needed:**
```toml
# workspace Cargo.toml
tonic = "0.14"
prost = "0.14"
tonic-build = "0.14"  # build dependency
```

**Files to create/modify:**
- `rust-core/verisim-api/proto/verisim.proto` — Service + message definitions
- `rust-core/verisim-api/build.rs` — tonic-build code generation
- `rust-core/verisim-api/src/grpc.rs` — Service implementation
- `rust-core/verisim-api/src/lib.rs` — Start gRPC server alongside HTTP

**Proto Schema (planned):**
```protobuf
service VeriSimPlanner {
  rpc OptimizePlan(LogicalPlan) returns (PhysicalPlan);
  rpc ExplainPlan(LogicalPlan) returns (ExplainOutput);
  rpc GetConfig(Empty) returns (PlannerConfig);
  rpc SetConfig(PlannerConfig) returns (PlannerConfig);
  rpc GetStats(Empty) returns (StatsSnapshot);
}

service VeriSimHexad {
  rpc Create(HexadRequest) returns (HexadResponse);
  rpc Get(HexadId) returns (HexadResponse);
  rpc Update(UpdateHexadRequest) returns (HexadResponse);
  rpc Delete(HexadId) returns (Empty);
  rpc SearchText(TextSearchRequest) returns (SearchResults);
  rpc SearchVector(VectorSearchRequest) returns (SearchResults);
}
```

**Feasibility:** YES — tonic has mature axum co-hosting support. ~300-400 lines + proto. Runs on separate port (50051) or multiplexed.

---

## Phase 3: VQL AST → LogicalPlan Bridge — NOT STARTED

**Plan:** Add `rust-core/verisim-planner/src/vql_bridge.rs` that deserializes the ReScript VQL AST JSON format into the planner's `LogicalPlan`.

**Key mappings:**
- `AST.modality` → `Modality` (direct, except `All` → expand to 6)
- `AST.source` → `QuerySource` (Hexad/Federation/Store)
- `AST.simpleCondition` variants → `ConditionKind` variants
- `AST.query.limit` → `PlanNode.early_limit`
- `AST.query.proof` → proof obligation nodes (Phase 4)

**New endpoint:** `POST /query/vql` — accepts VQL AST JSON, returns PhysicalPlan.

**Feasibility:** YES — both sides use JSON serde. ~150-200 lines.

---

## Phase 4: Proof Obligation Costing — NOT STARTED

**Plan:** Add to verisim-planner:
- `src/proof.rs` — ProofObligation, ProofPlanNode, CompositionStrategy types
- Modify `cost.rs` — add proof cost estimation
- Modify `explain.rs` — include proof section in EXPLAIN output
- Modify `plan.rs` — add proof obligations to PhysicalPlan

**Cost values (from VQLProofObligation.res):**
| Proof Type | Estimated Cost |
|-----------|---------------|
| Existence | 50ms |
| Citation | 100ms |
| Access | 150ms |
| Integrity | 200ms |
| Provenance | 300ms |
| Custom | 500ms |

**Feasibility:** YES — pure type additions + cost arithmetic. ~200 lines.

---

## Phase 5: Statistics Feedback + Adaptive Tuning — NOT STARTED

**Plan:**
- Add `POST /planner/stats/record` endpoint (modality, latency_ms, rows_returned)
- Implement adaptive mode tuning in `config.rs`:
  - Track last 50 queries per modality
  - Compare estimated vs actual
  - Shift mode if average error exceeds ±0.3

**Feasibility:** YES — StatisticsCollector already has `record_execution()`. Need endpoint + tuning logic. ~100-150 lines.

---

## Phase 6: Cross-Modal + PostProcessing Costing — NOT STARTED

**Plan:**
- Add `ConditionKind::CrossModalCompare`, `DriftCheck`, `ConsistencyCheck`
- Add PostProcessing cost estimation to optimizer (GroupBy=20ms, Sort=15ms, Aggregate=10ms)
- Handle `All` modality expansion

**Feasibility:** YES — extending existing enums + adding cost branches. ~100 lines.

---

## Dependency Graph

```
Phase 1 (DONE) ─┬─► Phase 2b (GraphQL)
                 ├─► Phase 2c (gRPC)
                 ├─► Phase 3 (VQL Bridge) ──► Phase 4 (Proof Costing)
                 ├─► Phase 5 (Statistics)
                 └─► Phase 6 (Cross-Modal)
```

All phases are independent except Phase 4 depends on Phase 3 (bridge must exist before proof obligations can flow through it).

---

## Feasibility Summary

| Phase | Feasible? | Effort | Risk |
|-------|-----------|--------|------|
| 1. Planner crate | YES — DONE | Done | None |
| 2b. GraphQL | YES | ~300 lines | Low — async-graphql is mature |
| 2c. gRPC | YES | ~400 lines + proto | Low — tonic is mature |
| 3. VQL Bridge | YES | ~200 lines | Low — JSON↔JSON mapping |
| 4. Proof Costing | YES | ~200 lines | Low — pure arithmetic |
| 5. Stats Feedback | YES | ~150 lines | Low — extending existing code |
| 6. Cross-Modal | YES | ~100 lines | Low — extending existing enums |

**Total remaining:** ~1350 lines across 6 phases. All feasible, all low risk.

---

## If Machine Crashes — Recovery Steps

```bash
cd /var/mnt/eclipse/repos/verisimdb

# 1. Verify Phase 1 is intact
cargo build -p verisim-planner && cargo test -p verisim-planner
cargo build -p verisim-api && cargo test -p verisim-api

# 2. Check git status
git status
git diff --stat

# 3. If uncommitted, commit immediately:
git add rust-core/verisim-planner/ Cargo.toml rust-core/verisim-api/
git commit -m "feat: add verisim-planner crate with cost-based query planning"

# 4. Resume from whichever phase is next (check this file)
```

## Files That Must Not Be Lost

These are the new files from this session:
```
rust-core/verisim-planner/Cargo.toml
rust-core/verisim-planner/src/lib.rs
rust-core/verisim-planner/src/error.rs
rust-core/verisim-planner/src/plan.rs
rust-core/verisim-planner/src/cost.rs
rust-core/verisim-planner/src/stats.rs
rust-core/verisim-planner/src/config.rs
rust-core/verisim-planner/src/optimizer.rs
rust-core/verisim-planner/src/explain.rs
```

Modified files:
```
Cargo.toml (workspace root — added verisim-planner member)
rust-core/verisim-api/Cargo.toml (added verisim-planner dep)
rust-core/verisim-api/src/lib.rs (added planner to AppState + 5 endpoints)
```
