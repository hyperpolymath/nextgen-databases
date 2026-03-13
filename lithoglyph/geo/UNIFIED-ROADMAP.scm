; SPDX-License-Identifier: PMPL-1.0-or-later
; Lith Ecosystem - Unified Roadmap to MVP 1.0.0
; Media-Type: application/vnd.roadmap+scm
;
; This file is distributed to all Lith ecosystem repos:
; - lith (core database)
; - fbql-dt (dependently-typed query language)
; - lith-studio (GUI)
; - lith-debugger (recovery tool)
; - lith-geo (geospatial projection layer)
; - lith-analytics (OLAP analytics projection layer)

(unified-roadmap
  (metadata
    (version "1.1.0")
    (created "2026-01-12")
    (updated "2026-01-16")
    (author "hyperpolymath")
    (target "MVP 1.0.0"))

  ;; ============================================================================
  ;; ECOSYSTEM OVERVIEW
  ;; ============================================================================
  (ecosystem-summary
    (components
      (lith
        (version "0.0.5")
        (completion 80)
        (role "Core database engine")
        (tech "Forth + Factor + Zig"))
      (fbql-dt
        (version "0.2.0")
        (completion 65)
        (role "Dependently-typed query language")
        (tech "Lean 4 + Zig"))
      (lith-studio
        (version "0.1.0")
        (completion 45)
        (role "Zero-friction GUI")
        (tech "ReScript + Tauri 2.0 + Rust"))
      (lith-debugger
        (version "0.1.0")
        (completion 55)
        (role "Proof-carrying recovery tool")
        (tech "Lean 4 + Idris 2 + Rust"))
      (lith-geo
        (version "0.1.0")
        (completion 15)
        (role "Geospatial projection layer")
        (tech "Rust (rstar, axum, geo)"))
      (lith-analytics
        (version "0.1.0")
        (completion 15)
        (role "OLAP analytics projection layer")
        (tech "Julia (DataFrames, Parquet2, Oxygen)")))

    (architecture
      "┌─────────────────────────────────────────────────────────────┐"
      "│  Lith Studio (GUI)                                        │"
      "│    ↓ generates FQLdt code                                   │"
      "├─────────────────────────────────────────────────────────────┤"
      "│  FQLdt (Lean 4)                                             │"
      "│    ↓ compiles to proof blobs                                │"
      "├─────────────────────────────────────────────────────────────┤"
      "│  Form.Bridge (Zig ABI)                                      │"
      "│    ↓ calls                                                  │"
      "├─────────────────────────────────────────────────────────────┤"
      "│  Lith Core (Forth + Factor)                               │"
      "│    Form.Runtime → Form.Normalizer → Form.Model → Form.Blocks│"
      "├─────────────────────────────────────────────────────────────┤"
      "│  Lith Debugger (alongside)                                │"
      "│    ↓ proves recovery safe                                   │"
      "│  Lith + FQLdt                                             │"
      "├─────────────────────────────────────────────────────────────┤"
      "│  Projection Layers (read from Lith HTTP API)              │"
      "│    lith-geo (R-tree spatial)  lith-analytics (OLAP)     │"
      "└─────────────────────────────────────────────────────────────┘"))

  ;; ============================================================================
  ;; CRITICAL PATH TO MVP 1.0.0
  ;; ============================================================================
  (critical-path
    (phase (id "P1") (name "Core Integration")
      (duration "weeks 1-6")
      (focus "Lith + FQLdt integration")

      (lith-tasks
        (task "Complete M11: HTTP API Server" priority: critical status: complete)
        (task "M12: Language bindings (ReScript, PHP)" priority: critical status: next)
        (task "M13: CMS integration (WordPress)" priority: high status: pending)
        (task "M14: Form.ControlPlane (clustering)" priority: medium status: pending))

      (fbql-dt-tasks
        (task "M5: Zig FFI bridge to Form.Bridge" priority: critical status: not-started)
        (task "M6: FQL parser (integrate with Lith's EBNF)" priority: high status: not-started)
        (task "Proof blob serialization (CBOR RFC 8949)" priority: high status: pending))

      (checkpoint "FQLdt can compile a query → proof blob → Lith accepts and executes"))

    (phase (id "P2") (name "User-Facing Tools")
      (duration "weeks 7-10")
      (focus "Studio and Debugger completion")

      (studio-tasks
        (task "Verify ReScript/Tauri build pipeline" priority: critical status: pending)
        (task "Wire ReScript UI to FQLdt code generation" priority: high status: pending)
        (task "Connect to Lith HTTP API" priority: high status: blocked)
        (task "Test schema creation → query → results flow" priority: medium status: pending))

      (debugger-tasks
        (task "Wire Idris REPL to PostgreSQL adapter" priority: high status: pending)
        (task "Lith adapter: parse real journal files" priority: high status: partial)
        (task "Complete Ratatui TUI interface" priority: medium status: in-progress)
        (task "Integration: proof verification before recovery" priority: medium status: pending))

      (projection-layer-tasks
        (task "lith-geo: Integration test with real Lith" priority: high status: pending)
        (task "lith-geo: Docker deployment" priority: medium status: pending)
        (task "lith-analytics: Integration test with real Lith" priority: high status: pending)
        (task "lith-analytics: PROMPT score dashboard endpoints" priority: medium status: pending))

      (checkpoint "Users can create schemas in Studio, debug with Debugger, query spatial/analytics"))

    (phase (id "P3") (name "Production Hardening")
      (duration "weeks 11-12")
      (focus "Stability and polish")

      (all-repos
        (task "Crash recovery tests" priority: high)
        (task "Error handling improvements" priority: high)
        (task "Cross-platform testing" priority: medium)
        (task "Documentation completion" priority: medium)
        (task "Performance optimization" priority: low))

      (checkpoint "MVP 1.0.0 release ready")))

  ;; ============================================================================
  ;; DEPENDENCY GRAPH
  ;; ============================================================================
  (dependencies
    (lith-m11
      (name "Lith HTTP API Server")
      (blocks "Studio M2" "Debugger Lith adapter")
      (priority critical))

    (fbql-dt-m5
      (name "FQLdt Zig FFI Bridge")
      (blocks "Studio M3" "Real type checking")
      (depends-on "Lith Form.Bridge")
      (priority critical))

    (fbql-dt-m6
      (name "FQLdt FQL Parser")
      (blocks "Full FQLdt compilation")
      (depends-on "fbql-dt-m5")
      (priority high))

    (studio-m1
      (name "Studio Build Pipeline")
      (blocks "All Studio features")
      (priority critical))

    (debugger-repl-db
      (name "Debugger REPL Database Connection")
      (blocks "Real debugging")
      (priority high))

    (lith-geo-integration
      (name "lith-geo Lith Integration")
      (depends-on "lith-m11")
      (blocks "Spatial queries in Studio")
      (priority medium))

    (lith-analytics-integration
      (name "lith-analytics Lith Integration")
      (depends-on "lith-m11")
      (blocks "Analytics dashboards in Studio")
      (priority medium)))

  ;; ============================================================================
  ;; UNRESOLVED DECISIONS
  ;; ============================================================================
  (decisions-needed
    (decision (id "DECISION-002")
      (title "FQLdt parser approach")
      (repo "fbql-dt")
      (options
        "Hand-rolled parser (simple, no deps)"
        "Lean 4 Parsec (built-in)"
        "Integrate with Lith's Factor-based FBQL parser")
      (recommendation "Integrate - reuse Lith's EBNF grammar via FFI")
      (impact "Affects M6 implementation"))

    (decision (id "DECISION-003")
      (title "Lith integration strategy for FQLdt")
      (repo "fbql-dt")
      (options
        "Mock Forth core for MVP"
        "Real Form.Bridge integration")
      (recommendation "Real integration - M11 HTTP API makes this feasible")
      (impact "Determines MVP scope")))

  ;; ============================================================================
  ;; POST-MVP ROADMAP
  ;; ============================================================================
  (post-mvp
    (release (version "1.1.0") (name "Normalization & Migration")
      (features
        "Form.Normalizer full integration (FD discovery → decomposition)"
        "Three-phase migration workflow (Announce/Shadow/Commit)"
        "Studio: visual normalization wizard"
        "Debugger: migration rollback proofs"
        "lith-geo: Polygon and region queries"
        "lith-analytics: Time-series dashboards in Studio"))

    (release (version "1.2.0") (name "Multi-Database Support")
      (features
        "Debugger: SQLite adapter completion"
        "Lith: clustering/replication (Form.ControlPlane begins)"
        "Studio: connection manager for multiple DBs"))

    (release (version "2.0.0") (name "Agentic Ecosystem")
      (features
        "Form.ControlPlane (Elixir/OTP) for distributed coordination"
        "Agent handover protocols"
        "Long-term archive format standardization"
        "Multi-user collaboration in Studio")))

  ;; ============================================================================
  ;; SUCCESS METRICS
  ;; ============================================================================
  (success-metrics
    (mvp-criteria
      "User can create a schema in Studio with visual builder"
      "Schema generates valid FQLdt with type checking"
      "User can insert data with provenance tracking"
      "User can query data and see results"
      "Debugger can analyze schema and propose fixes"
      "All operations have proof-carrying verification")

    (quality-gates
      "All ReScript code compiles without warnings"
      "All Rust code passes Clippy lints"
      "All Lean 4 code builds with lake"
      "All Julia code passes tests"
      "Cross-platform builds succeed (Mac/Windows/Linux)"
      "Integration tests pass end-to-end"
      "Projection layers can sync from Lith HTTP API")))
