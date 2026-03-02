# Design Document: PanLL Database Interop + Telemetry

**Date:** 2026-02-28
**Repo:** nextgen-databases/verisimdb + panll
**Session:** PanLL database module protocol, opt-in telemetry, product development insights

## Problem Statement

VeriSimDB's PanLL integration is currently hardcoded — `verisimdbState` lives directly
in PanLL's Model, with VeriSimDB-specific messages and Tauri commands. This means:

1. **No plugin architecture** for other databases (QuandleDB, LithoGlyph)
2. **No telemetry** — we have `:telemetry` events defined but no aggregation, export, or UI
3. **No product development feedback loop** — we don't know how the system is used
4. **Each playground is standalone** — VQL Playground, future KQL/GQL playgrounds are islands

## Design Goals

1. **Database Module Protocol** — standard interface for any database to plug into PanLL
2. **Opt-In Telemetry** — transparent, privacy-first product development metrics
3. **User-Facing Insights** — telemetry is also useful to database operators
4. **Playground Gallery** — PanLL manages query language playgrounds uniformly

## Architecture

### Database Module Protocol

Each database module implements a standard protocol for PanLL integration:

```
┌───────────────────────────────────────────────────────┐
│  PanLL Database Module Protocol                        │
│                                                        │
│  capabilities():  → list<capability>                   │
│  health():        → result<status, error>              │
│  query(string):   → result<queryResult, error>         │
│  telemetry():     → telemetrySnapshot                  │
│  playground():    → playgroundConfig                   │
│                                                        │
│  Pane-L Mapping:  grammar, type system, constraints    │
│  Pane-N Mapping:  query engine, inference, reasoning   │
│  Pane-W Mapping:  results, drift, telemetry dashboard  │
└───────────────────────────────────────────────────────┘
```

**Capabilities** (what a database can do):
- `QueryExecution` — run queries in its native language
- `DriftDetection` — detect cross-modal consistency issues
- `ProofGeneration` — generate verifiable proof certificates
- `Normalisation` — self-repair drifted modalities
- `Federation` — federate queries across backends
- `Telemetry` — expose operational metrics
- `Playground` — provide an interactive query editor

### Telemetry Architecture

```
                     ┌──────────────┐
                     │  VeriSimDB   │
                     │  Telemetry   │
                     │  (Elixir)    │
                     └──────┬───────┘
                            │ :telemetry events
                     ┌──────▼───────┐
                     │  Collector   │
                     │  (ETS-based) │
                     └──────┬───────┘
                            │ periodic flush
                     ┌──────▼───────┐
                     │  Reporter    │
                     │  (JSON export│
                     │  + HTTP API) │
                     └──────┬───────┘
                            │
              ┌─────────────┼─────────────┐
              │             │             │
       ┌──────▼───┐  ┌─────▼────┐  ┌─────▼────┐
       │ PanLL UI │  │ JSON     │  │ Product  │
       │ Dashboard│  │ Export   │  │ Insights │
       └──────────┘  └──────────┘  └──────────┘
```

**Privacy Guarantees:**
- **Opt-in only** — telemetry disabled by default, explicit `VERISIM_TELEMETRY=true`
- **No PII** — never captures query content, entity data, or user identifiers
- **Aggregate only** — counts, distributions, rates — never individual records
- **Local first** — all data stays on the machine unless user explicitly exports
- **User-visible** — telemetry dashboard shows exactly what is collected

### Telemetry Events

| Event | What it measures | Why it helps |
|-------|-----------------|-------------|
| `verisim.query.modality_usage` | Which modalities are queried most | Prioritise optimisation work |
| `verisim.query.pattern` | Query shape (SELECT, SEARCH, INSERT, etc.) | Understand usage patterns |
| `verisim.query.duration_distribution` | Query latency percentiles | Performance regression detection |
| `verisim.drift.frequency` | How often drift is detected | Gauge system stability |
| `verisim.drift.modality_breakdown` | Which modalities drift most | Focus normalisation work |
| `verisim.normalise.success_rate` | How often normalisation succeeds | Quality metric |
| `verisim.federation.peer_health` | Federated peer availability | Operational monitoring |
| `verisim.proof.type_usage` | Which proof types are used | VQL-DT adoption metric |
| `verisim.entity.modality_coverage` | Average modalities per entity | Data completeness metric |
| `verisim.system.uptime` | Server uptime | Reliability metric |

### Product Insights Derived from Telemetry

The reporter aggregates raw telemetry into actionable insights:

1. **Modality Heatmap** — which of the 8 modalities see real use vs. are ignored
2. **Query Pattern Distribution** — what percentage is read vs. write vs. drift vs. proof
3. **Performance Trends** — is p95 latency improving or degrading over time?
4. **Drift Frequency** — are entities staying consistent or constantly re-normalising?
5. **Federation Health** — are peer backends reliable or flaky?
6. **VQL-DT Adoption** — are users using dependent type proofs?

### PanLL Integration Points

**Existing (already built):**
- `Model.res` — `verisimdbState` with drift scores, proof obligations
- `Msg.res` — `verisimdbMsg` with health, query, drift, normalise, entity detail
- `TauriCmd.res` — 7 VeriSimDB Tauri commands
- `PaneW.res` — Database tools panel, drift heatmap, VQL query area

**New (this session):**
- `Model.res` — add `telemetryState` to verisimdbState
- `Msg.res` — add `FetchTelemetry`, `TelemetryLoaded` messages
- `TauriCmd.res` — add `getTelemetry` Tauri command
- `PaneW.res` — add telemetry dashboard panel
- `DatabaseModule.res` (NEW) — protocol types for generic database modules
- `DatabaseRegistry.res` (NEW) — manages registered database modules

## Implementation Plan

### Phase 1: VeriSimDB Telemetry (Elixir-side)

1. Extend `lib/verisim/telemetry.ex` with event emission across modules
2. Create `lib/verisim/telemetry/collector.ex` — ETS-based metric aggregation
3. Create `lib/verisim/telemetry/reporter.ex` — JSON export + HTTP endpoint
4. Create `lib/verisim/telemetry/product_insights.ex` — derived insights
5. Add telemetry endpoint to verisim-api (GET /api/v1/telemetry)

### Phase 2: PanLL Database Module Protocol

1. Create `src/modules/DatabaseModule.res` — type definitions
2. Create `src/modules/DatabaseRegistry.res` — module registry
3. Extend `Model.res` with telemetry state
4. Extend `Msg.res` with telemetry messages
5. Add telemetry Tauri command to `TauriCmd.res`

### Phase 3: PanLL Telemetry Dashboard

1. Extend `PaneW.res` with telemetry visualization panel
2. Modality usage heatmap (reuses drift heatmap pattern)
3. Query pattern distribution bar chart
4. Performance trend indicators

### Phase 4: Playground Gallery (Future)

1. Abstract VQL Playground as a PanLL module
2. Define playground protocol (editor, linter, formatter, executor)
3. Register VQL, future KQL, future GQL playgrounds
4. PanLL manages playground lifecycle

## Files Changed/Created

### VeriSimDB (elixir-orchestration)
- `lib/verisim/telemetry.ex` — extend with new events
- `lib/verisim/telemetry/collector.ex` — NEW: ETS-based aggregation
- `lib/verisim/telemetry/reporter.ex` — NEW: JSON export + insights
- `test/verisim/telemetry_test.exs` — NEW: telemetry tests

### PanLL
- `src/modules/DatabaseModule.res` — NEW: protocol types
- `src/modules/DatabaseRegistry.res` — NEW: module registry
- `src/Model.res` — extend verisimdbState with telemetry
- `src/Msg.res` — add telemetry messages
- `src/commands/TauriCmd.res` — add telemetry command
- `src/components/PaneW.res` — add telemetry panel
