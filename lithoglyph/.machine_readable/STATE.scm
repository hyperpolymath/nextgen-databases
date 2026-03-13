;; SPDX-License-Identifier: PMPL-1.0-or-later
;; Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <jonathan.jewell@open.ac.uk>
;;
;; STATE.scm - Project state tracking for Lithoglyph (formerly Lith)
;; Media-Type: application/vnd.state+scm

(state
  (metadata
    (version "0.0.7")
    (schema-version "1.0.0")
    (created "2026-02-01")
    (updated "2026-03-13")
    (project "Lithoglyph")
    (former-name "Lith")
    (naming-note "IP claim on 'Form'/'Lith'. Code still uses Lith internally — rename to Lith/Litho PENDING.")
    (repo "https://github.com/hyperpolymath/lithoglyph"))

  (project-context
    (name "Lithoglyph: Narrative-First, Reversible, Audit-Grade Database")
    (tagline "The database where the database is part of the story")
    (tech-stack
      (storage-layer "Forth" "Lith.Blocks + Lith.Model (17 passing tests)")
      (bridge-layer "Zig" "Lith.Bridge - C ABI, 19 functions, WAL commit, all tests pass")
      (abi-layer "Idris2" "Dependent-type ABI proofs, zero believe_me, compiles clean")
      (runtime-layer "Factor" "Lith.Runtime - GQL parser/planner/executor")
      (normalizer-layer "Factor + Lean 4" "Lith.Normalizer - FD discovery with 52 proofs")
      (beam-layer "Zig + Rust" "BEAM NIFs for Elixir/Erlang integration, both build clean")
      (control-plane "Elixir/OTP" "Lith.ControlPlane - clustering, supervision (planned)")
      (query-language "GQLdt" "github.com/hyperpolymath/gql-dt - dependently-typed")
      (config "Nickel")
      (containers "Podman + selur-compose")))

  (current-position
    (phase "ip-rename-complete")
    (overall-completion 80)
    (note "Core phases 1-4 complete. ABI formally verified. BEAM NIFs compile. L1 (Zig HTTP migration) COMPLETE. L2 (Lith rename) COMPLETE. L3 (Evidence collection schema) COMPLETE. IP rename: fdb_*→lith_*, FQL/FBQL/FDQL→GQL, FormBD/FormDB→Lith/Lithoglyph — all complete. Glyphbase NIF wired to core-zig via Zig module import (19 bridge functions, 9.3MB .so). All builds pass.")
    (components
      (lith-blocks
        (status complete)
        (completion 100)
        (version "v0.0.2")
        (build-status "17/17 tests pass")
        (files
          "core-forth/src/lithoglyph-blocks.fs"
          "core-forth/test/test-blocks.fs"
          "spec/blocks.adoc"))
      (lith-bridge
        (status complete)
        (completion 100)
        (version "v0.0.8")
        (build-status "BUILD + TEST PASS (Zig 0.15.2)")
        (description "C ABI bridge with persistent BlockStorage, WAL commit, 6-phase sync. IP rename complete: fdb_*→lith_*, FQL→GQL, FormBD→Lith.")
        (files
          "core-zig/src/bridge.zig"
          "core-zig/src/blocks.zig"
          "core-zig/test-ffi-integration.c")
        (features
          "19 real functions (open, close, apply, commit, abort, read, update, delete, ...)"
          "WAL commit protocol"
          "Block allocator with compaction"
          "Schema and constraint introspection"
          "Proof verifier registration"
          "All unsafe casts annotated with // SAFETY:"
          "IP rename: all fdb_* symbols → lith_*, FQL/FBQL/FDQL → GQL (Glyph Query Language)"))
      (idris2-abi
        (status complete)
        (completion 100)
        (version "v0.0.7")
        (build-status "All 3 files type-check clean (idris2 --check)")
        (description "Dependent-type ABI definitions with formal proofs")
        (files
          "src/Lith/LithBridge.idr"
          "src/Lith/LithForeign.idr"
          "src/Lith/LithLayout.idr")
        (properties
          "Zero believe_me (BANNED pattern eliminated)"
          "Zero typed holes"
          "Memory layout proofs (alignment, block sizes, packing)"
          "ABI compatibility proofs (cross-platform, version stability)"
          "Storage efficiency proofs (>98% payload ratio)"
          "18 FFI declarations matching core-zig bridge"
          "Inline validation (path, GQL query, JSON) pending Proven integration"))
      (ffi-delegation
        (status complete)
        (completion 100)
        (version "v0.0.7")
        (build-status "BUILD + TEST PASS")
        (description "ffi/zig/ delegates to core-zig (unified bridge)")
        (files
          "ffi/zig/build.zig"
          "ffi/zig/src/bridge.zig"))
      (generated-header
        (status complete)
        (completion 100)
        (version "v0.0.7")
        (description "C header generated from Idris2 ABI definitions")
        (files "generated/abi/bridge.h"))
      (factor-runtime
        (status complete)
        (completion 100)
        (version "v0.0.4")
        (description "GQL parser, planner, executor in Factor with FFI to Zig bridge")
        (files
          "core-factor/gql/storage-backend.factor"
          "core-factor/gql/gql.factor"))
      (lean-proofs
        (status complete)
        (completion 100)
        (version "v0.0.4")
        (build-status "52 tests pass")
        (files "core-lean/"))
      (beam-nif-zig
        (status complete)
        (completion 100)
        (version "v0.0.8")
        (build-status "BUILD PASS (0 errors)")
        (description "Zig NIF for BEAM with real FFI calls to core-zig bridge")
        (files
          "beam/native/src/lith_nif.zig"
          "beam/native/src/beam.zig"))
      (glyphbase-nif
        (status in-progress)
        (completion 60)
        (version "v0.0.8")
        (build-status "BUILD PASS — NIF links to core-zig (9.3MB .so)")
        (description "Glyphbase Zig NIF wired to core-zig via module import. All 19 bridge functions available. Type mismatch resolved: NIF uses real LgBlob/LgStatus from core-zig.")
        (files
          "glyphbase/native/src/glyphbase_nif.zig")
        (notes "UI layer still uses demo data. NIF build and linkage complete, real data flow pending."))
      (beam-nif-rust
        (status complete)
        (completion 100)
        (version "v0.0.7")
        (build-status "BUILD PASS (0 warnings)")
        (description "Rust NIF for BEAM via rustler with thread-safe handles")
        (files
          "beam/native_rust/src/lib.rs"
          "beam/native_rust/Cargo.toml"))
      (api-layer
        (status complete)
        (completion 100)
        (version "v0.0.8")
        (build-status "PASS — Zig 0.15.2 HTTP migration complete (83 call sites updated)")
        (description "HTTP + gRPC API with real bridge calls, Reader/Writer pattern")
        (files
          "api/src/main.zig"
          "api/src/rest.zig"
          "api/src/grpc.zig"
          "api/src/auth.zig"
          "api/build.zig"))
      (evidence-collections
        (status complete)
        (completion 100)
        (version "v0.0.8")
        (description "L3: Evidence collection schema for bofig — 5 collections defined in glyphbase/examples/bofig-evidence.json + 5 GQL test vectors")
        (collections "bofig_evidence" "bofig_claims" "bofig_relationships" "bofig_entities" "bofig_financial_transactions"))
      (production-infra
        (status complete)
        (completion 100)
        (version "v0.0.7")
        (description "Container deployment, orchestration, CI/CD")
        (files
          "Containerfile"
          "selur-compose.yml"
          ".github/workflows/ci.yml"))
      (test-vectors
        (status complete)
        (completion 100)
        (version "v0.0.7")
        (description "Encoding test vectors and BEAM integration tests")
        (files
          "test-vectors/encoding/block-header.json"
          "test-vectors/encoding/block-payload.json"
          "test-vectors/encoding/journal-entry.json"
          "test-vectors/encoding/cbor-roundtrip.json"
          "beam/test/lith_nif_test.exs"
          "beam/test/lith_integration_test.exs"))
      (rescript-tests
        (status complete)
        (completion 100)
        (version "v0.0.7")
        (description "Property tests (12 predicates) + fuzz tests (4 targets)")
        (files
          "tests/property/run.sh"
          "tests/fuzz/run.sh"
          "tests/fuzz/src/Lith_Fuzz_Main.res"))
      (language-bindings
        (status in-progress)
        (completion 40)
        (version "v0.0.6")
        (rescript-bindings
          (status in-progress)
          (completion 60)
          (files "clients/rescript/"))
        (php-bindings
          (status in-progress)
          (completion 20)
          (files "clients/php/")))
      (studio
        (status incomplete)
        (completion 20)
        (description "Tauri admin GUI — 11 TODO commands returning mock data")
        (files "studio/src-tauri/src/main.rs"))
      (control-plane
        (status not-started)
        (completion 0)
        (planned-version "v0.1.0"))))

  (route-to-mvp
    (target-version "1.0.0")
    (definition "Production-ready narrative database with clustering and full ecosystem")

    (milestones
      (milestone-1
        (name "Core Specifications")
        (status complete)
        (version "v0.0.2"))
      (milestone-2-5
        (name "Forth PoC Implementation")
        (status complete)
        (version "v0.0.2"))
      (milestone-6
        (name "Machine-Readable Artefacts")
        (status complete)
        (version "v0.0.2"))
      (milestone-7
        (name "Complete Documentation Suite")
        (status complete)
        (version "v0.0.3"))
      (milestone-8
        (name "Lith.Runtime (GQL Engine)")
        (status complete)
        (version "v0.0.4"))
      (milestone-9
        (name "Lith.Normalizer")
        (status complete)
        (version "v0.0.4"))
      (milestone-10
        (name "Production Hardening")
        (status complete)
        (version "v0.0.4"))
      (milestone-11
        (name "Multi-Protocol API Server")
        (status complete)
        (version "v0.0.5")
        (note "Bridge calls wired but HTTP API needs Zig 0.15.2 migration"))
      (milestone-11.5
        (name "ABI Formalization and Bridge Unification")
        (status complete)
        (completed-date "2026-02-13")
        (version "v0.0.7")
        (items
          (item "Idris2 ABI: zero believe_me, all proofs verified" status: complete)
          (item "ffi/zig unified with core-zig (delegation pattern)" status: complete)
          (item "C header generated from ABI definitions" status: complete)
          (item "Factor FFI aligned with generated header" status: complete)
          (item "BEAM NIFs: Zig + Rust, both compile clean" status: complete)
          (item "All unsafe Zig casts annotated with // SAFETY:" status: complete)
          (item "SQL injection fixed in test generators" status: complete)
          (item "Production infrastructure: Containerfile, selur-compose, CI" status: complete)
          (item "Test vectors and BEAM integration tests created" status: complete)))
      (milestone-12
        (name "Language Bindings")
        (status in-progress)
        (version "v0.0.6"))
      (milestone-13
        (name "CMS Integration")
        (status not-started)
        (version "v0.0.8"))
      (milestone-14
        (name "Lith.ControlPlane (Clustering)")
        (status not-started)
        (version "v0.1.0"))
      (milestone-14.5
        (name "Lith → Lith/Litho Rename")
        (status not-started)
        (version "v0.8.0")
        (description "IP claim on 'Form'/'Lith'. Rename all code, files, dirs, symbols, docs.")
        (scope "Entire repo: .idr .zig .rs .res .factor .fs .h .json .md .yml"))
      (milestone-15
        (name "1.0.0 Release Candidate")
        (status not-started)
        (version "v1.0.0-rc"))))

  (blockers-and-issues
    (critical
      (issue
        (id "NAMING-001")
        (title "Lith → Lith/Litho rename (IP claim)")
        (description "Google owns 'Lith' trademark. Rename from Form*/FormBD/FormDB to Lith/Lithoglyph LARGELY COMPLETE. fdb_*→lith_* symbol rename done. FQL/FBQL/FDQL→GQL (Glyph Query Language) done. FormBD/FormDB→Lith/Lithoglyph done. Remaining: full Lith→Litho rename at M14.5.")
        (milestone "M14.5")
        (target-version "v0.8.0")
        (partial-progress "fdb_*→lith_* complete; FQL/FBQL/FDQL→GQL complete; FormBD/FormDB→Lith/Lithoglyph complete; formdb-http/→lith-http/ complete; remaining: Lith→Litho final rename deferred to M14.5")))
    (high
      (issue
        (id "API-001")
        (title "API layer Zig 0.15.2 HTTP migration")
        (description "api/src/rest.zig has 83 call sites using old std.http.Server API. Needs Reader/Writer pattern.")
        (status "complete")
        (completed-date "2026-03-13")
        (notes "All 83 call sites migrated to Reader/Writer pattern. L1 COMPLETE."))
      (issue
        (id "INTEGRATION-001")
        (title "GQLdt integration")
        (description "Lithoglyph needs to integrate with gql-dt for dependently-typed queries")
        (dependency "github.com/hyperpolymath/gql-dt M7 (Idris2 ABI) + M8 (Zig FFI)")))
    (medium
      (issue
        (id "PROVEN-001")
        (title "Proven library integration")
        (description "Inline validation in LithBridge.idr should delegate to external Proven repo")
        (notes "Real Proven repo at /var/mnt/eclipse/repos/proven/ has 104+ modules"))
      (issue
        (id "BINDINGS-001")
        (title "Language bindings incomplete")
        (description "ReScript bindings 60% done, PHP bindings 20% done")
        (milestone "M12")))
    (low
      (issue
        (id "STUDIO-001")
        (title "Studio Tauri commands are all TODOs")
        (description "11 backend commands return mock data"))))

  (session-history
    (snapshot
      (date "2026-03-13")
      (session-id "ip-rename-and-glyphbase-nif-linkage")
      (accomplishments
        "IP rename complete: fdb_*→lith_* across all Zig/C/Idris2/Factor symbols"
        "Query language rename: FQL/FBQL/FDQL→GQL (Glyph Query Language)"
        "Project name rename: FormBD/FormDB→Lith/Lithoglyph in all code and docs"
        "Glyphbase NIF wired to core-zig via Zig module import — all 19 bridge functions linked"
        "NIF builds to 9.3MB .so with real core-zig integration"
        "Type mismatch resolved: NIF now uses real LgBlob/LgStatus from core-zig instead of local stubs"
        "All builds pass: core-zig, ffi/zig, glyphbase NIF, Idris2 ABI"
        "Zero believe_me maintained throughout"
        "Updated overall completion from 75% to 80%"))
    (snapshot
      (date "2026-03-13")
      (session-id "seams-sealing-pipeline-integration")
      (accomplishments
        "L1 (Zig HTTP migration): marked COMPLETE"
        "L2 (Lith rename): formdb-http/ → lith-http/ directory rename + all FORMDB_*/FormBD/FormDB env vars and code refs renamed to LITH_*/Lith across entire repo (excl. lith-http/)"
        "L3 (Evidence collection schema): marked COMPLETE — 5 collections + 5 GQL test vectors"
        "Updated overall completion from 70% to 75%"
        "Integration plan docs created: docs/INTEGRATION-PLAN-LITHOGLYPH.md, docs/EPSTEIN-INGEST-TESTS.md"
        "Cross-repo seams sealed with Bofig and Docudactyl"))
    (snapshot
      (date "2026-02-13")
      (session-id "abi-hardening-and-compile-verification")
      (accomplishments
        "Phase A: Completed 7-phase ABI plan (delete templates, eliminate believe_me, align ABI, generate header, update Factor FFI, expand tests, create test runners)"
        "Phase B: Fixed all compile blockers — Idris2 typed holes filled, proof signatures use concrete literals for Nat reduction, forward reference issues resolved"
        "Unified dual Zig bridges (ffi/zig delegates to core-zig)"
        "Implemented real BEAM NIFs (Zig + Rust) replacing stubs"
        "Wired real bridge calls into API layer (rest.zig, grpc.zig)"
        "Added SAFETY comments to all 22 Zig unsafe casts"
        "Fixed SQL injection in test generators"
        "Created production infrastructure (Containerfile, selur-compose.yml, CI workflow)"
        "Created test vectors and BEAM integration tests"
        "Fixed Rust NIF lifetime errors and eliminated all 6 cargo warnings"
        "Cleaned cruft: removed tracked .zig-cache, Rust target/, legacy docs, broken symlinks"
        "Updated .gitignore for comprehensive coverage"
        "Verified builds: core-zig PASS, ffi/zig PASS, core-forth 17/17, Lean 52/52, Idris2 clean, beam/native PASS, beam/native_rust PASS (0 warnings)")
      (pending
        "Lith → Lith/Litho rename (IP issue, whole repo)"
        "API layer Zig 0.15.2 HTTP migration (83 call sites in rest.zig)"
        "Proven library integration (inline validation → external repo)"
        "Studio Tauri commands (11 TODOs)"
        "Re-run panic-attack scan after fixes"))
    (snapshot
      (date "2026-02-01")
      (session-id "documentation-organization")
      (accomplishments
        "Created STATE.scm for Lith repo"
        "Assessed current state: M1-M11 complete, M12 in progress"))))

;; Helper functions for state queries
(define (get-completion-percentage state)
  (state 'current-position 'overall-completion))

(define (get-blockers state priority)
  (state 'blockers-and-issues priority))

(define (get-milestone state n)
  (state 'route-to-mvp 'milestones (string->symbol (format "milestone-~a" n))))
