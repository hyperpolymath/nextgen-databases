;; SPDX-License-Identifier: PMPL-1.0-or-later
;; VeriSimDB Meta-Level Information
;; Media type: application/meta+scheme
;; Last updated: 2026-02-27

(define-module (verisimdb meta)
  #:version "1.1.0"
  #:updated "2026-02-13T22:00:00Z")

;; ============================================================================
;; ARCHITECTURE DECISIONS (ADR Format)
;; ============================================================================

(define architecture-decisions
  '((adr-001
      (title . "Use ISO/IEC 14977 EBNF for VQL Grammar")
      (status . "accepted")
      (date . "2026-01-22")
      (context . "VQL grammar needs formal specification for parser generators and documentation. Multiple EBNF variants exist (W3C, ISO, ANTLR-style).")
      (decision . "Use ISO/IEC 14977 EBNF standard for vql-grammar.ebnf")
      (consequences
        (positive . "Standard format, tool-parseable (drawgrammar), unambiguous semantics, international standard")
        (negative . "Stricter than informal EBNF, required 12 iterations to fix all violations, no regex shortcuts")
        (neutral . "Required character classes → special sequences, explicit alternatives")))

    (adr-002
      (title . "Hybrid Push/Pull Normalization Cascade")
      (status . "accepted")
      (date . "2026-01-22")
      (context . "Five levels of normalization (L0-L4) need coordination strategy. Pure push (eventual consistency, high overhead) vs pure pull (stale data, low overhead).")
      (decision . "Hybrid: Push critical (retractions, integrity), pull optimization (title mismatches). VeriSimDB controls L0-L3, advisory on L4 (external systems).")
      (consequences
        (positive . "Scales better (most drift is cosmetic), clear boundaries, safety-first for critical issues")
        (negative . "More complex than pure strategy, requires classification logic")
        (neutral . "Adaptive learner can adjust push/pull thresholds over time")))

    (adr-003
      (title . "Dependent Types for PROOF Path, Simple Types for Slipstream")
      (status . "accepted")
      (date . "2026-01-22")
      (context . "VQL has two execution paths: dependent-type (with ZKP proofs) and slipstream (fast, unverified). Type system complexity needed?")
      (decision . "Use dependent types with refinements for PROOF path, simple types for slipstream. Type erasure possible for optimization.")
      (consequences
        (positive . "Formal verification where needed, performance elsewhere, clear separation of guarantees")
        (negative . "Dual type system complexity, parser must handle both paths")
        (neutral . "Type checker only runs for PROOF queries")))

    (adr-004
      (title . "Elixir Feedback Loops (v1) Before miniKanren (v3)")
      (status . "accepted")
      (date . "2026-01-22")
      (context . "Adaptive learning needed for cache TTL, normalization policies, query optimization. Mozart/Oz suggested but heavyweight. miniKanren is lightweight but unproven in this domain.")
      (decision . "Implement Elixir feedback loops for v1 (adaptive_learner.ex), plan miniKanren constraint solving for v3. Prove learning works before adding logic programming.")
      (consequences
        (positive . "Simpler v1 implementation, Elixir GenServers well-understood, can iterate quickly")
        (negative . "Elixir limited to heuristics, can't synthesize rules from examples")
        (neutral . "miniKanren adds ~500 LOC but unlocks rule synthesis, strategy optimization")))

    (adr-005
      (title . "Four-Tier Verbosity System for Error Handling")
      (status . "accepted")
      (date . "2026-01-22")
      (context . "Different use cases need different output levels: CI/CD (silent), interactive (normal), debugging (verbose), troubleshooting (debug).")
      (decision . "SILENT, NORMAL (default), VERBOSE, DEBUG. Friendly notices (info, warning, hint, deprecation) separate from errors.")
      (consequences
        (positive . "Matches actual user workflows, progressive disclosure, friendly for newcomers")
        (negative . "Four levels to maintain, filtering logic needed")
        (neutral . "Follows precedent from Cargo, GCC, Clang")))

    (adr-006
      (title . "Separate verisimdb-debugger Repo (v2)")
      (status . "proposed")
      (date . "2026-01-22")
      (context . "Debugger planned for v2. Options: monorepo directory or separate repo. Debugger is tooling (TUI), not core database.")
      (decision . "Separate verisimdb-debugger repo. Clearer separation (core vs tooling), independent versioning, smaller focused repos.")
      (consequences
        (positive . "Clear boundaries, debugger can support multiple VeriSimDB versions, different release cadence")
        (negative . "Cross-repo dependency management, version sync challenges")
        (neutral . "Can move back to monorepo if becomes problematic")))

    (adr-007
      (title . "Semantic Versioning with 6-Month Deprecation")
      (status . "accepted")
      (date . "2026-01-22")
      (context . "Backwards compatibility critical for federated systems. Breaking changes need migration time.")
      (decision . "Semantic versioning (MAJOR.MINOR.PATCH) with minimum 6-month deprecation period. VERSION clause in VQL for explicit version pinning.")
      (consequences
        (positive . "Predictable upgrades, users have time to migrate, federated stores can negotiate versions")
        (negative . "Must support multiple versions simultaneously, deprecation tracking overhead")
        (neutral . "6 months balances stability (not too short) and agility (not too long)")))

    (adr-008
      (title . "Rust Edition 2024 for Modality Stores")
      (status . "accepted")
      (date . "2026-01-22")
      (context . "Rust edition choice: 2021 (stable, widely supported) vs 2024 (latest, new features).")
      (decision . "Use Rust edition 2024 for all modality stores. Project is new, can leverage latest features.")
      (consequences
        (positive . "Latest language features, better diagnostics, improved ergonomics")
        (negative . "Requires Rust 1.85+ (late 2024), smaller ecosystem compatibility")
        (neutral . "Edition 2021 code can be dependencies without issues")))

    (adr-009
      (title . "IPv6-Only Default with IPv4 Override")
      (status . "accepted")
      (date . "2026-02-13")
      (context . "Network binding default: IPv4 (0.0.0.0), IPv6 (::), or dual-stack. IPv6 adoption is standard in modern infrastructure.")
      (decision . "Default to [::] (IPv6 any). VERISIM_ENABLE_IPV4=true enables dual-stack. Without override: IPv6-only.")
      (consequences
        (positive . "Forward-looking, works on all modern infrastructure, avoids IPv4 exhaustion")
        (negative . "Legacy IPv4-only networks need explicit override")
        (neutral . "Container orchestrators (Podman, Kubernetes) support IPv6 natively")))

    (adr-010
      (title . "Federation Closed by Default (PSK Authentication)")
      (status . "accepted")
      (date . "2026-02-13")
      (context . "Federation peer registration was open to anyone. This is a security risk in production.")
      (decision . "Federation registration requires X-Federation-PSK header. VERISIM_FEDERATION_KEYS env var provides allowed store_id:key pairs. When unset, federation registration is disabled entirely.")
      (consequences
        (positive . "Secure by default, no accidental open federation")
        (negative . "Requires PSK distribution for federation setup")
        (neutral . "PSK is simple; future: upgrade to mTLS or signed tokens")))

    (adr-011
      (title . "Homoiconicity: Queries as Hexads")
      (status . "accepted")
      (date . "2026-02-13")
      (context . "VQL queries are structured data. Storing them as hexads enables meta-circular operations: query the query store, optimize stored queries, track query lineage.")
      (decision . "VQL queries are stored as hexads with all 6 modalities populated. REFLECT keyword queries the query store itself. /queries/{id}/optimize enables self-modification.")
      (consequences
        (positive . "Meta-circular: system can reason about its own queries. Similarity search over past queries. Self-optimization.")
        (negative . "Storage overhead for query hexads. Risk of infinite recursion with REFLECT queries.")
        (neutral . "REFLECT queries are themselves stored as hexads, enabling arbitrary meta-levels")))

    (adr-012
      (title . "R1CS Constraint System for Custom ZKP Circuits")
      (status . "accepted")
      (date . "2026-02-13")
      (context . "Custom circuits need a representation for verification. Options: R1CS (Rank-1 Constraint System), Plonk, AIR (Algebraic Intermediate Representation).")
      (decision . "Use R1CS (A * B = C constraint format) for custom circuits. Gates compile to R1CS constraints. SHA-256 for Merkle commitments within circuits.")
      (consequences
        (positive . "Well-understood, compatible with existing ZKP libraries (Groth16, Spartan)")
        (negative . "Less expressive than Plonk for some circuit patterns")
        (neutral . "Can add Plonk support later as alternative backend")))

    (adr-013
      (title . "Octad Architecture: 8 Modalities (Hexad → Octad Evolution)")
      (status . "accepted")
      (date . "2026-02-27")
      (context . "The original hexad (6 modalities) covered data representation but lacked origin tracking and geospatial awareness. Temporal tracks versions (what changed); provenance tracks origins (where it came from). Spatial captures physical location and proximity.")
      (decision . "Evolve from hexad (6) to octad (8). Add provenance/lineage as 7th modality (CRITICAL) and spatial/geospatial as 8th modality. Tensor modality retained — active research is exploring novel applications with significant future potential beyond traditional numeric storage. All existing modalities unchanged.")
      (consequences
        (positive . "Provenance enables GDPR compliance, audit trails, cross-system lineage, drift causality explanation. Spatial enables IoT, logistics, fleet management consistency. Tensor research opens future possibilities.")
        (negative . "Structural change across codebase. All modality iteration must account for 8 stores. Naming evolution (hexad → octad) throughout documentation.")
        (neutral . "Provenance is append-only (simpler than graph or vector). Spatial uses mature Rust crates (geo, rstar). Tensor research is ongoing and confidential.")))

    (adr-014
      (title . "Heterogeneous Database Federation")
      (status . "proposed")
      (date . "2026-02-27")
      (context . "Current federation is peer-to-peer between VerisimDB instances. Enterprise value requires watching non-VerisimDB databases (ArangoDB, PostgreSQL, Elasticsearch) for cross-system entity consistency. IDApTIK database bridge is the first working example.")
      (decision . "Extend federation with adapter interface for external databases. Each adapter maps an external database's API to VerisimDB's hexad model. Drift detection operates across adapters.")
      (consequences
        (positive . "Enterprise adoption without requiring data migration. VerisimDB becomes consistency layer over existing stack. Unique positioning vs data quality tools.")
        (negative . "Each adapter is maintenance burden. External database schema changes can break adapters.")
        (neutral . "Adapter interface isolates external complexity. Start with ArangoDB and PostgreSQL.")))

    (adr-015
      (title . "No Introspection Endpoints")
      (status . "accepted")
      (date . "2026-02-27")
      (context . "Should VerisimDB expose schema discovery endpoints (/_introspect, SHOW COLLECTIONS, DESCRIBE HEXAD)? Standard practice in many databases.")
      (decision . "No introspection endpoints. Not disabled, not gated — not written. The Elixir orchestration layer knows the schema from source code. If the code path does not exist, it cannot be misconfigured into production.")
      (consequences
        (positive . "Zero attack surface from schema discovery. No information leakage about internal structure.")
        (negative . "External tooling cannot auto-discover schema. Developers must read docs.")
        (neutral . "The REPL and REST API provide all needed functionality without exposing structure.")))

    (adr-016
      (title . "Three-Layer Differentiator Strategy")
      (status . "accepted")
      (date . "2026-02-27")
      (context . "VerisimDB has multiple novel capabilities. Which to lead with? Options: 6 modalities (marketing-sounding), drift detection (broad appeal), VQL-DT (deep tech).")
      (decision . "Layer 1: Drift detection (door-opener, easy to explain). Layer 2: Heterogeneous federation (enterprise value). Layer 3: VQL-DT formal verification (technical moat, impossible to clone quickly). Provenance compounds with all three layers.")
      (consequences
        (positive . "Clear positioning for different audiences. Drift for data teams, federation for enterprise, VQL-DT for regulated industries.")
        (negative . "VQL-DT development deferred until VQL is solid. Risk of losing momentum on strongest technical feature.")
        (neutral . "Competitors in data quality space (Great Expectations, Monte Carlo) operate at table/column level — VerisimDB operates at entity level across systems. Different category.")))

    (adr-017
      (title . "Cross-Modal Write Atomicity via Elixir 2PC Coordination")
      (status . "proposed")
      (date . "2026-02-27")
      (context . "Writes to an octad entity span 8 independent Rust modality stores. If a write succeeds in the document store but fails in the graph store, the entity is born inconsistent — VerisimDB generates the very drift it claims to detect. This is potentially the most critical architectural concern.")
      (decision . "Elixir EntityServer acts as 2PC coordinator. Phase 1: prepare writes to all modality stores (each returns WAL entry). Phase 2: commit all or rollback all. WAL replay on crash recovery ensures atomicity survives process restarts.")
      (consequences
        (positive . "Eliminates self-inflicted drift. Entity writes are atomic across all modalities. WAL provides crash recovery. Elixir is natural coordinator (already manages entity lifecycle).")
        (negative . "2PC adds latency to every write. WAL requires disk I/O. Complexity in failure handling (partial prepare failures, network timeouts).")
        (neutral . "Existing verisim-wal crate provides the WAL foundation. EntityServer GenServer already exists. This is coordination logic, not new storage.")))))

;; ============================================================================
;; DEVELOPMENT PRACTICES
;; ============================================================================

(define development-practices
  '((code-style
      (languages
        ((rescript . "Official ReScript formatter, no custom rules")
         (elixir . "mix format with default settings")
         (rust . "rustfmt with edition 2024")))
      (naming-conventions
        "- Types: PascalCase (e.g., QueryResult, HexadRef)
         - Functions: snake_case (e.g., detect_drift, parse_query)
         - Constants: SCREAMING_SNAKE_CASE (e.g., MAX_RETRIES)
         - Modules: PascalCase (e.g., DriftMonitor, VQLParser)")
      (documentation
        "- All public APIs must have doc comments
         - Rust: /// doc comments with examples
         - Elixir: @doc with @spec type signatures
         - ReScript: /** JSDoc-style */ comments"))

    (security
      (principles
        "- Zero-Trust: All federation requests must be signed
         - Least privilege: Services run as non-root
         - Immutable audit trail: All mutations logged to temporal store
         - ZKP where possible: Proofs instead of raw data exposure")
      (practices
        "- Dependencies: Audit with cargo-audit, mix audit
         - Secrets: Never commit (use .gitignore, git-crypt for configs)
         - SPDX headers: All files must have SPDX-License-Identifier
         - CVE monitoring: Subscribe to rust-sec, Elixir security advisories"))

    (testing
      (unit-tests
        "- Rust: #[cfg(test)] modules, use proptest for property-based
         - Elixir: ExUnit with doctests for examples
         - ReScript: Jest for ReScript output")
      (integration-tests
        "- End-to-end VQL query tests
         - Federation coordination tests (multi-store)
         - Drift detection scenarios
         - ZKP proof generation/verification")
      (property-tests
        "- Query equivalence (semantically equal queries → same results)
         - Drift repair idempotence (repair(repair(x)) = repair(x))
         - Type safety (well-typed queries don't crash)")
      (coverage
        "- Target: 80% line coverage for core logic
         - Critical paths (ZKP, drift repair): 95%+
         - Generated code (bindings): Excluded"))

    (versioning
      (scheme . "Semantic Versioning 2.0.0 (MAJOR.MINOR.PATCH)")
      (changelog . "Keep CHANGELOG.adoc updated per Keep a Changelog format")
      (release-process
        "1. Update version in Cargo.toml, package.json (registry), mix.exs
         2. Update CHANGELOG.adoc
         3. Tag release: git tag -a vX.Y.Z -m 'Release X.Y.Z'
         4. Build artifacts: cargo build --release, ReScript compile
         5. Publish: crates.io (Rust), npm (ReScript registry), hex.pm (Elixir)
         6. Announce: GitHub releases, mailing list"))

    (documentation
      (structure
        "- README.adoc: Quick start, architecture overview
         - WHITEPAPER.md: High-level vision, use cases
         - docs/*.adoc: Detailed technical specs
         - API docs: Generated from code (rustdoc, ExDoc, ReScript docgen)")
      (maintenance
        "- Update docs alongside code changes
         - Review docs quarterly for stale content
         - Link verification: Check external links monthly")
      (formats
        "- AsciiDoc preferred for long-form docs (better than Markdown for technical)
         - Markdown for GitHub-specific (CONTRIBUTING, CODE_OF_CONDUCT)
         - EBNF for grammar (ISO/IEC 14977)
         - Scheme for state files (STATE.scm, META.scm, ECOSYSTEM.scm)"))

    (branching
      (strategy . "GitHub Flow (lightweight)")
      (branches
        "- main: Always deployable, protected
         - feature/*: New features
         - fix/*: Bug fixes
         - docs/*: Documentation only")
      (pull-requests
        "- Required for all changes to main
         - At least 1 approval (if team > 1)
         - CI must pass (tests, lints, build)
         - Squash merge preferred for clean history"))))

;; ============================================================================
;; DESIGN RATIONALE (Why VeriSimDB?)
;; ============================================================================

(define design-rationale
  '((why-tiny-core
      (problem . "Monolithic databases force consistency models, federation systems lack local storage")
      (solution . "VeriSimDB: <5k LOC core that operates as database AND coordinator. Start standalone, federate later.")
      (benefit . "Users choose deployment mode (standalone/federated/hybrid) without rewrite"))

    (why-eight-modalities-octad
      (problem . "Complex data workloads need graph (citations), vector (embeddings), tensor (novel research applications), semantic (types), document (text), temporal (versions), provenance (origins/lineage), and spatial (geolocation). No single database provides all.")
      (solution . "VeriSimDB: Eight modalities (octad) in one namespace. Query across modalities with cross-modal drift detection ensuring consistency.")
      (benefit . "Eliminates ETL between specialized databases. One query, multiple modalities. Provenance tracks data origins for compliance. Tensor modality opens future research possibilities."))

    (why-drift-tolerant
      (problem . "Federated systems diverge. Forcing strict consistency blocks federation. Ignoring drift causes errors.")
      (solution . "VeriSimDB: Detect drift (5 levels), choose repair strategy (strict/repair/tolerate/latest). Drift is first-class concept.")
      (benefit . "Federated stores can diverge temporarily. System converges when appropriate, not immediately."))

    (why-vql
      (problem . "SQL (relational), Cypher (graph), vector search (custom APIs), tensor ops (NumPy) = 4 languages for 4 modalities. No unified query.")
      (solution . "VQL: One language for all modalities. SELECT GRAPH, VECTOR FROM ... WHERE (graph pattern) AND (vector similarity)")
      (benefit . "Single query language. Dependent types for verified path, simple types for slipstream."))

    (why-zkp-proofs
      (problem . "Federated data lacks verifiability. 'Trust but don't verify' insufficient for compliance (GDPR, HIPAA, FAIR).")
      (solution . "VeriSimDB: Optional PROOF clause. Queries return results + ZKP proof of contract satisfaction (existence, citation, access, integrity).")
      (benefit . "Verifiable queries without exposing private data. Audit trail for compliance."))

    (why-rescript-elixir-rust
      (problem . "Single-language systems lack best tool for each job.")
      (solution
        "- ReScript: Type-safe registry, compiles to WASM (portable, sandboxed)
         - Elixir/OTP: Fault-tolerant coordination, GenServers for hexads
         - Rust: Performance-critical stores, zero-cost abstractions")
      (benefit . "Each language solves problem it's best at. ReScript for logic, Elixir for supervision, Rust for speed."))

    (why-adaptive-learning
      (problem . "Static policies (cache TTL, normalization thresholds) don't adapt to workload.")
      (solution . "VeriSimDB: Feedback loops observe metrics, adjust policies. v1: Elixir heuristics. v3: miniKanren rule synthesis.")
      (benefit . "System self-tunes. Cache TTL increases if hit rate high. Drift types pushed if frequency high."))

    (why-not-mozart-oz
      (problem . "Mozart/Oz suggested for constraint solving, but heavyweight (~10MB runtime).")
      (solution . "VeriSimDB: Elixir feedback loops (v1), miniKanren (v3). Prove learning works before adding complex runtime.")
      (benefit . "Tiny core maintained. miniKanren ~500 LOC vs Mozart/Oz full runtime."))

    (why-normalization-hybrid
      (problem . "Pure push (eventual consistency, high overhead) vs pure pull (stale data, low overhead).")
      (solution . "Hybrid: Push critical (retractions, integrity), pull optimization (title mismatches). VeriSimDB controls L0-L3, advisory L4.")
      (benefit . "Scales (most drift cosmetic), safe (critical issues pushed), clear boundaries."))

    (why-iso-ebnf
      (problem . "VQL grammar needs formal spec. Many EBNF variants (W3C, ISO, ANTLR).")
      (solution . "ISO/IEC 14977 EBNF. International standard, tool-parseable.")
      (benefit . "Unambiguous. Parser generators work. Grammar is formal spec, not just documentation."))))

;; ============================================================================
;; CROSS-CUTTING CONCERNS
;; ============================================================================

(define cross-cutting-concerns
  '((performance
      (goals
        "- Query latency: <100ms for slipstream, <1s for dependent-type (with proof)
         - Throughput: 1000 queries/sec on 4-core machine
         - Federation: <5s for 3-store federated query with quorum
         - Startup time: <2s for standalone, <10s for federated coordinator")
      (measurement
        "- Criterion.rs for Rust benchmarks
         - :timer module for Elixir timing
         - Flamegraph for profiling
         - Memory: heaptrack, valgrind")
      (optimization
        "- Cache query plans (VQLExplain.res)
         - Memoize drift detection results
         - Parallel federation queries (Task.async_stream)
         - SIMD for vector operations (if supported)"))

    (scalability
      (horizontal
        "- Federation: Add stores dynamically
         - Elixir supervision tree: Scale GenServers
         - Load balancing: Registry routes to least-loaded store")
      (vertical
        "- Rust stores: Multi-threaded (rayon for parallel ops)
         - Elixir: OTP scales to millions of processes
         - Memory: Stream large results (avoid loading all in RAM)"))

    (observability
      (logging
        "- Elixir: Logger with metadata (query_id, hexad_id)
         - Rust: tracing crate with spans
         - Structured logs (JSON) for parsing")
      (metrics
        "- Query latency histograms
         - Drift detection frequency
         - Cache hit rate
         - Store availability")
      (tracing
        "- OpenTelemetry for distributed tracing
         - Span per query, sub-spans per modality store
         - VeriSimDB Debugger (v2) for interactive trace viewer"))

    (security-model
      (threat-model
        "- Malicious federated store (Byzantine fault)
         - Compromised registry (unauthorized store registration)
         - Proof forgery (invalid ZKP)
         - Injection attacks (SQL injection equivalent for VQL)")
      (mitigations
        "- Byzantine tolerance: Quorum-based consensus (2f+1 agreement)
         - Registry signing: sactify-php signatures for store registration
         - ZKP verification: proven library formal verification
         - VQL parsing: Formal grammar, no eval() or dynamic code execution"))

    (ethical-considerations
      (privacy
        "- ZKP proofs: Prove properties without revealing data
         - Temporal log: Track all access (audit trail)
         - Right to forget: Tombstone records, not deletion (GDPR compliance)")
      (governance
        "- Federation: No single authority (decentralized)
         - Store operators: Autonomous (own policies)
         - Drift policies: Configurable (strict/tolerant)")
      (transparency
        "- Open source: All code public (PMPL-1.0-or-later)
         - Immutable logs: All mutations auditable
         - ZKP verification: Anyone can verify proofs"))))

;; ============================================================================
;; FUTURE VISION (v2+)
;; ============================================================================

(define future-vision
  '((v2-goals
      "- VeriSimDB Debugger (TUI for query tracing, drift visualization)
       - Full VQL implementation (parser, type checker, optimizer)
       - Production-ready standalone deployment
       - Performance benchmarks vs PostgreSQL, MongoDB")

    (v3-goals
      "- miniKanren integration (constraint-based optimization)
       - Rule synthesis from error examples
       - Advanced drift repair (automatic conflict resolution)
       - Federation at scale (100+ stores)")

    (beyond-v3
      "- VQL language server (IDE integration, autocomplete)
       - Liquid types (automatic predicate inference)
       - Effect types (track side effects in queries)
       - Probabilistic queries (uncertainty in federated data)")))

;; Export metadata
(define-public architecture-decisions architecture-decisions)
(define-public development-practices development-practices)
(define-public design-rationale design-rationale)
(define-public cross-cutting-concerns cross-cutting-concerns)
(define-public future-vision future-vision)
