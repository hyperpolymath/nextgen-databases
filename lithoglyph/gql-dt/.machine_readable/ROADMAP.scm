; SPDX-License-Identifier: PMPL-1.0-or-later
; Lithoglyph Ecosystem - Unified Roadmap to MVP 1.0.0
; Media-Type: application/vnd.roadmap+scm
;
; This file is distributed to all Lithoglyph ecosystem repos:
; - lithoglyph (core database)
; - fdql-dt (dependently-typed query language)
; - lithoglyph-studio (GUI)
; - lithoglyph-debugger (recovery tool)

(unified-roadmap
  (metadata
    (version "1.0.0")
    (created "2026-01-12")
    (updated "2026-01-12")
    (author "hyperpolymath")
    (target "MVP 1.0.0"))

  ;; ============================================================================
  ;; ECOSYSTEM OVERVIEW
  ;; ============================================================================
  (ecosystem-summary
    (components
      (lithoglyph
        (version "0.0.4")
        (completion 70)
        (role "Core database engine")
        (tech "Forth + Factor + Zig"))
      (fdql-dt
        (version "0.2.0")
        (completion 85)
        (role "Dependently-typed query language")
        (tech "Lean 4 + Zig"))
      (lithoglyph-studio
        (version "0.1.0")
        (completion 45)
        (role "Zero-friction GUI")
        (tech "ReScript + Tauri 2.0 + Rust"))
      (lithoglyph-debugger
        (version "0.1.0")
        (completion 55)
        (role "Proof-carrying recovery tool")
        (tech "Lean 4 + Idris 2 + Rust")))

    (architecture
      "┌─────────────────────────────────────────────────────────────┐"
      "│  Lithoglyph Studio (GUI)                                        │"
      "│    ↓ generates FQLdt code                                   │"
      "├─────────────────────────────────────────────────────────────┤"
      "│  FQLdt (Lean 4)                                             │"
      "│    ↓ compiles to proof blobs                                │"
      "├─────────────────────────────────────────────────────────────┤"
      "│  Form.Bridge (Zig ABI)                                      │"
      "│    ↓ calls                                                  │"
      "├─────────────────────────────────────────────────────────────┤"
      "│  Lithoglyph Core (Forth + Factor)                               │"
      "│    Form.Runtime → Form.Normalizer → Form.Model → Form.Blocks│"
      "├─────────────────────────────────────────────────────────────┤"
      "│  Lithoglyph Debugger (alongside)                                │"
      "│    ↓ proves recovery safe                                   │"
      "│  Lithoglyph + FQLdt                                             │"
      "└─────────────────────────────────────────────────────────────┘"))

  ;; ============================================================================
  ;; CRITICAL PATH TO MVP 1.0.0
  ;; ============================================================================
  (critical-path
    (phase (id "P1") (name "Core Integration")
      (duration "weeks 1-6")
      (focus "Lithoglyph + FQLdt integration")

      (lithoglyph-tasks
        (task "Complete M11: HTTP API Server" priority: critical status: in-progress)
        (task "Expose Form.Bridge FFI for proof verification" priority: high status: pending)
        (task "Add CBOR proof blob acceptance in query path" priority: high status: pending))

      (fdql-dt-tasks
        (task "M5: Zig FFI bridge to Form.Bridge" priority: critical status: not-started)
        (task "M6: GQL parser (integrate with Lithoglyph's EBNF)" priority: high status: not-started)
        (task "Proof blob serialization (CBOR RFC 8949)" priority: high status: pending))

      (checkpoint "FQLdt can compile a query → proof blob → Lithoglyph accepts and executes"))

    (phase (id "P2") (name "User-Facing Tools")
      (duration "weeks 7-10")
      (focus "Studio and Debugger completion")

      (studio-tasks
        (task "Verify ReScript/Tauri build pipeline" priority: critical status: pending)
        (task "Wire ReScript UI to FQLdt code generation" priority: high status: pending)
        (task "Connect to Lithoglyph HTTP API" priority: high status: blocked)
        (task "Test schema creation → query → results flow" priority: medium status: pending))

      (debugger-tasks
        (task "Wire Idris REPL to PostgreSQL adapter" priority: high status: pending)
        (task "Lithoglyph adapter: parse real journal files" priority: high status: partial)
        (task "Complete Ratatui TUI interface" priority: medium status: in-progress)
        (task "Integration: proof verification before recovery" priority: medium status: pending))

      (checkpoint "Users can create schemas in Studio, debug with Debugger"))

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
    (lithoglyph-m11
      (name "Lithoglyph HTTP API Server")
      (blocks "Studio M2" "Debugger Lithoglyph adapter")
      (priority critical))

    (fdql-dt-m5
      (name "FQLdt Zig FFI Bridge")
      (blocks "Studio M3" "Real type checking")
      (depends-on "Lithoglyph Form.Bridge")
      (priority critical))

    (fdql-dt-m6
      (name "FQLdt GQL Parser")
      (blocks "Full FQLdt compilation")
      (depends-on "fdql-dt-m5")
      (priority high))

    (studio-m1
      (name "Studio Build Pipeline")
      (blocks "All Studio features")
      (priority critical))

    (debugger-repl-db
      (name "Debugger REPL Database Connection")
      (blocks "Real debugging")
      (priority high)))

  ;; ============================================================================
  ;; UNRESOLVED DECISIONS
  ;; ============================================================================
  (decisions-needed
    (decision (id "DECISION-002")
      (title "FQLdt parser approach")
      (repo "fdql-dt")
      (options
        "Hand-rolled parser (simple, no deps)"
        "Lean 4 Parsec (built-in)"
        "Integrate with Lithoglyph's Factor-based FDQL parser")
      (recommendation "Integrate - reuse Lithoglyph's EBNF grammar via FFI")
      (impact "Affects M6 implementation"))

    (decision (id "DECISION-003")
      (title "Lithoglyph integration strategy for FQLdt")
      (repo "fdql-dt")
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
        "Debugger: migration rollback proofs"))

    (release (version "1.2.0") (name "Multi-Database Support")
      (features
        "Debugger: SQLite adapter completion"
        "Lithoglyph: clustering/replication (Form.ControlPlane begins)"
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
      "Cross-platform builds succeed (Mac/Windows/Linux)"
      "Integration tests pass end-to-end")))
