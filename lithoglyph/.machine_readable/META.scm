;; SPDX-License-Identifier: PMPL-1.0-or-later
;; META.scm - Meta-level information for Lith
;; Media-Type: application/meta+scheme

(meta
  (architecture-decisions
    (adr-001
      (id "ADR-001")
      (title "Narrative-First Design Philosophy")
      (status "accepted")
      (date "2026-01-03")
      (context "Databases optimize for machine efficiency over human understanding.
                Error messages are cryptic, schemas are opaque, migrations are scary.")
      (decision "All artefacts (schemas, constraints, migrations, journals) must be
                 human-readable narrative artefacts that explain intent, not just state.")
      (consequences
        "Provenance required for all mutations"
        "Constraints produce explainable rejections"
        "Migrations are reversible with narrative explanations"
        "Higher storage overhead for narrative metadata"))

    (adr-002
      (id "ADR-002")
      (title "Append-Only Journal with Inverses")
      (status "accepted")
      (date "2026-01-03")
      (context "Traditional databases use WAL for crash recovery but discard history.
                Audit requirements demand complete operation history.")
      (decision "All operations logged to append-only journal with sequence numbers.
                 Each operation stores its inverse for reversibility.")
      (consequences
        "Complete audit trail from genesis"
        "Any state reconstructable via replay"
        "Time-travel queries possible"
        "Journal grows unbounded (tiered storage mitigates)"))

    (adr-003
      (id "ADR-003")
      (title "Zig-Only ABI (No C Dependency)")
      (status "accepted")
      (date "2026-01-11")
      (context "Originally planned C ABI for FFI. C introduces memory safety risks
                and complicates build process.")
      (decision "Use Zig-only ABI for Form.Bridge. Zig provides C ABI compatibility
                 without C's safety issues.")
      (consequences
        "Safer FFI boundary"
        "Simpler build (no separate C compiler)"
        "Factor/Forth integration via Zig"
        "Requires Zig toolchain"))

    (adr-004
      (id "ADR-004")
      (title "FQL Over SQL")
      (status "accepted")
      (date "2026-01-03")
      (context "SQL is ubiquitous but designed for relational model only.
                Lith is multi-model (document, graph, relational).")
      (decision "Design FQL (Lith Query Language) with native support for
                 documents, edges, provenance, and narrative constraints.")
      (consequences
        "No SQL compatibility layer (explicit non-goal)"
        "Learning curve for SQL users"
        "Native graph traversal (TRAVERSE)"
        "Built-in provenance syntax (WITH PROVENANCE)"))

    (adr-005
      (id "ADR-005")
      (title "Forth/Factor for Core Implementation")
      (status "accepted")
      (date "2026-01-11")
      (context "Need minimal, auditable implementation for storage layer.
                Most languages have large runtimes.")
      (decision "Use Forth for core-forth (block/journal/model layers).
                 Use Factor for runtime (parser/planner/executor).")
      (consequences
        "Minimal dependencies"
        "Highly auditable code"
        "Concatenative style matches stack-based block operations"
        "Smaller developer community"))

    (adr-006
      (id "ADR-006")
      (title "Dependent Types for Schema Evolution")
      (status "accepted")
      (date "2026-01-11")
      (context "Schema migrations are error-prone. Type systems can catch errors
                at compile time but most don't encode database constraints.")
      (decision "FQLdt (FQL with Dependent Types) uses Lean 4 to encode constraints
                 as types. Schema evolution carries proofs of correctness.")
      (consequences
        "Compile-time query verification"
        "Proof-carrying migrations"
        "Requires Lean 4 for full verification"
        "Optional - base FQL works without proofs"))

    (adr-007
      (id "ADR-007")
      (title "PMPL-1.0 License")
      (status "accepted")
      (date "2026-01-12")
      (context "MPL-2.0 is permissive but doesn't align with ethical open source
                principles of the Palimpsest philosophy.")
      (decision "Adopt Palimpsest-MPL 1.0 (PMPL-1.0) which adds ethical use
                 considerations to MPL-2.0 base.")
      (consequences
        "Stronger ethical stance"
        "May limit adoption by some organizations"
        "Aligns with project values (auditability, meaning, ethics)")))

  (development-practices
    (code-style
      (forth "ANS Forth with Lith vocabulary extensions")
      (factor "Factor standard style, USING: declarations")
      (zig "Zig style guide, explicit error handling")
      (docs "AsciiDoc with :toc: and :icons: font"))

    (security
      (principle "Defense in depth")
      (provenance "All mutations require actor + rationale")
      (checksums "CRC32C for block integrity")
      (encryption "Optional per-block encryption (planned)")
      (audit "Complete journal enables forensic analysis"))

    (testing
      (unit "Per-layer tests in core-forth/test/")
      (integration "Seam checks: Block↔Model, Model↔Runtime, Block↔Runtime")
      (golden "Test vectors for deterministic operations")
      (property "FQLdt proofs for schema properties"))

    (versioning
      (scheme "SemVer 2.0.0")
      (stability "Pre-1.0: No stability guarantees")
      (policy "See VERSIONING.adoc"))

    (documentation
      (format "AsciiDoc (.adoc)")
      (specs "spec/*.adoc - Formal specifications")
      (guides "docs/*.adoc - User guides")
      (api "docs/API-REFERENCE.adoc"))

    (branching
      (main "Stable, releasable")
      (feature "feature/* for development")
      (release "Tags: v0.0.1, v0.0.2, v0.0.3")))

  (design-rationale
    (why-narrative-first
      "Traditional databases treat humans as second-class citizens.
       Error messages like 'UNIQUE constraint failed' explain nothing.
       Lith believes every database artefact should tell a story:
       who changed what, why, and what it means.")

    (why-reversibility
      "DELETE in SQL is permanent. DROP TABLE is terrifying.
       Lith journals everything with inverses. Any operation
       can be undone. Time-travel is a feature, not a hack.")

    (why-provenance
      "In journalism, governance, and archives, 'who said this and why'
       matters as much as the data itself. Provenance is not metadata -
       it's the soul of the record.")

    (why-multi-model
      "Real data is messy. Some is tabular, some is documents,
       some is graphs. Lith doesn't force you to pick one model.
       Documents, edges, and schemas coexist naturally.")

    (why-constraints-as-ethics
      "A UNIQUE constraint isn't just a rule - it's a promise.
       A CHECK constraint encodes business ethics. Lith makes
       constraints visible, explainable, and narratively meaningful.")

    (why-self-normalizing
      "Schema design is hard. Most developers get it wrong.
       Lith can discover functional dependencies automatically
       and propose normalization with proofs of correctness.
       The database teaches you about your own data.")))
