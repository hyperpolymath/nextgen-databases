;; SPDX-License-Identifier: PMPL-1.0-or-later
;; ECOSYSTEM.scm - Ecosystem position for Lith
;; Media-Type: application/vnd.ecosystem+scm

(ecosystem
  (version "1.0")
  (name "Lith")
  (naming-note "Temporary name - 'Lith' is Google-owned trademark. Final name TBD before v1.0.0")
  (type "database-engine")
  (purpose "Narrative-first, reversible, audit-grade database for domains
            where provenance, auditability, and human understanding matter
            more than raw performance.")

  (position-in-ecosystem
    (category "Databases")
    (subcategory "Multi-Model / Document-Graph Hybrid")
    (unique-value
      "Provenance-native: Every mutation requires actor + rationale"
      "Reversible: Append-only journal with inverses for any operation"
      "Narrative: Schemas, constraints, migrations are human-readable artefacts"
      "Self-normalizing: Discovers FDs and proposes schema improvements with proofs"
      "Audit-grade: Complete history from genesis, time-travel queries"))

  (related-projects
    ;; Core ecosystem - Sibling projects
    (fbql-dt
      (relationship "sibling-language")
      (repo "github.com/hyperpolymath/fbql-dt")
      (status "implementation-in-progress")
      (completion 75)
      (description "FBQLdt: Dependently-Typed Lith Query Language. Lean 4 implementation
                    with compile-time type checking, refinement types, and proof-carrying
                    migrations. Two-tier design: FBQLdt (admin) and FBQL (user-friendly).")
      (tech-stack "Lean 4 + Idris2 ABI + Zig FFI + ReScript bindings")
      (integration-points
        (type-system "BoundedNat, BoundedInt, NonEmptyString, Confidence, PromptScores")
        (provenance "ActorId, Rationale, Timestamp, Tracked types")
        (serialization "CBOR proof blobs, JSON API, binary storage")
        (parser "Complete parser for INSERT/SELECT/UPDATE/DELETE with type inference")
        (permissions "Two-tier permission system with TypeWhitelist"))
      (alignment-status
        (fundep-types "Lith should adopt schema-bound FunDep S type from fbql-dt")
        (proofs "Waiting for fbql-dt M7 (Idris2 ABI) + M8 (Zig FFI)")
        (bindings "Waiting for fbql-dt M9 (ReScript bindings)")
        (ffi "Compatible - both use CBOR-encoded proof blobs via Zig FFI")))

    (formbase
      (relationship "sibling-application")
      (repo "github.com/hyperpolymath/formbase")
      (status "ui-prototype")
      (completion 30)
      (description "Open-source Airtable alternative built on Lith. Spreadsheet-database
                    hybrid with provenance by default, full reversibility, PROMPT scores,
                    and multi-view support (Grid/Kanban/Calendar/Gallery/Form).")
      (tech-stack "Gleam/BEAM backend + ReScript+React UI + Yjs CRDT + WebSocket")
      (dependency "Requires Lith language bindings (M12) for integration")
      (roadmap "v0.1.0 Core Grid view in progress"))

    (lithoglyph-studio
      (relationship "sibling-tool")
      (repo "github.com/hyperpolymath/lithoglyph-studio")
      (status "planned")
      (description "Zero-friction admin GUI for Lith. Visual schema designer,
                    FQL query builder, provenance explorer, journal viewer, and
                    normalization proof visualizer."))

    (lithoglyph-debugger
      (relationship "sibling-tool")
      (repo "github.com/hyperpolymath/lithoglyph-debugger")
      (status "scaffolding-complete")
      (completion 35)
      (description "Proof-carrying debugger. Step through FQL queries, inspect
                    constraint violations, visualize normalization proofs, and
                    explore journal replay scenarios.")
      (alignment-status
        (journal-types "Need Migration/NormalizationStep entry types from Lith")
        (provenance "Need Confidence + ProofBlob types from fbql-dt")
        (proofs "LosslessProof stubs need real Lean 4 implementations")))

    (lithoglyph-analytics
      (relationship "sibling-extension")
      (repo "github.com/hyperpolymath/lithoglyph-analytics")
      (status "planned")
      (description "Analytics layer for Lith. OLAP-style queries, time-series
                    analysis, provenance-aware aggregations."))

    (lithoglyph-beam
      (relationship "sibling-integration")
      (repo "github.com/hyperpolymath/lithoglyph-beam")
      (status "planned")
      (description "Erlang/BEAM ecosystem integration. Native Elixir/Gleam bindings,
                    OTP supervision tree, distributed Lith clusters."))

    (lithoglyph-geo
      (relationship "sibling-extension")
      (repo "github.com/hyperpolymath/lithoglyph-geo")
      (status "planned")
      (description "Geospatial extensions for Lith. PostGIS-style spatial types,
                    indexes, and queries with provenance tracking."))

    (zotero-lith
      (relationship "sibling-integration")
      (repo "github.com/hyperpolymath/zotero-lith")
      (status "planned")
      (description "Zotero plugin for Lith. Academic reference management with
                    provenance tracking, DOI linking, and citation graphs."))

    ;; External inspirations and comparisons
    (datomic
      (relationship "inspiration")
      (description "Immutable database with time-travel. Lith shares the
                    immutability philosophy but adds provenance and narrative."))

    (arangodb
      (relationship "comparison")
      (description "Multi-model database (document + graph). Lith is similar
                    but prioritizes auditability over performance."))

    (sqlite
      (relationship "comparison")
      (description "Embedded database. Lith aims for similar simplicity
                    but with built-in versioning and provenance."))

    (event-sourcing
      (relationship "pattern-inspiration")
      (description "Lith's journal is conceptually similar to event sourcing
                    but with first-class inverses and provenance."))

    (git
      (relationship "philosophy-inspiration")
      (description "Content-addressable, append-only, complete history.
                    Lith applies git's philosophy to structured data.")))

  (target-domains
    (investigative-journalism
      "Track sources, verify claims, maintain evidence chains.
       Every fact has provenance. Retractions are reversible corrections.")

    (governance-and-policy
      "Audit trails for decisions. Who approved what, when, why.
       Regulation compliance with explainable constraints.")

    (agentic-ecosystems
      "AI agents need to explain their reasoning. Lith provides
       the audit infrastructure for accountable AI systems.")

    (archives-and-preservation
      "Long-term data preservation with complete provenance.
       Future researchers can trace every change.")

    (scientific-research
      "Reproducibility requires knowing exactly what data existed when.
       Time-travel queries reconstruct historical states."))

  (what-this-is
    "A database engine that treats data history as sacred"
    "A query language (FBQL/FBQLdt) designed for provenance and narrative"
    "A storage format (blocks + journal) optimized for auditability"
    "A philosophy: databases should explain themselves"
    "An ecosystem of tools for narrative-first data management"
    "Layered architecture: Forth (storage) + Zig (FFI) + Factor (runtime) + Elixir (clustering)"
    "Integration with formal methods: Lean 4 via fbql-dt for proof-carrying migrations"
    "Open source under PMPL-1.0-or-later (Palimpsest License)")

  (what-this-is-not
    "Not a drop-in SQL replacement (FBQL is intentionally different)"
    "Not optimized for OLAP workloads (narrative overhead, use lithoglyph-analytics for that)"
    "Not a distributed database yet (single-node PoC complete, clustering in M14)"
    "Not a real-time streaming platform (use CDC integration for streaming)"
    "Not a full-text search engine (integrate with Meilisearch/Typesense)"
    "Not a time-series database (different access patterns, use InfluxDB/TimescaleDB)"
    "Not trying to be the fastest database (auditability > performance)"
    "Not called 'Lith' - that's Google's trademark (final name TBD before v1.0.0)"))
