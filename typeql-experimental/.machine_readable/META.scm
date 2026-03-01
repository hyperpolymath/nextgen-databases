;; SPDX-License-Identifier: PMPL-1.0-or-later
(meta
  (version "1.0.0")
  (last-updated "2026-03-01")

  (architecture-decisions
    (decision "vql-not-sql"
      (status accepted)
      (date "2026-03-01")
      (context "Need a base query language for type extensions")
      (decision "Use VQL (VeriSim Query Language) as foundation, not SQL")
      (rationale "VQL's cross-modal semantics (HEXAD, 8 modalities, PROOF clauses)
                  are the natural foundation. SQL's relational model is too flat
                  for the properties we want to prove."))

    (decision "idris2-qtt-native"
      (status accepted)
      (date "2026-03-01")
      (context "Need linear types for resource-counted connections")
      (decision "Use Idris2's native QTT (quantitative type theory) rather than encoding linearity")
      (rationale "Idris2 variables carry quantities (0, 1, omega). CONSUME AFTER 1 USE
                  maps to (1 conn : Connection) — compiler enforces linearity for free."))

    (decision "delta-grammar"
      (status accepted)
      (date "2026-03-01")
      (context "Need grammar for 6 new clause types")
      (decision "Extend VQL v3.0 EBNF with optional clauses appended after standard query")
      (rationale "No keyword conflicts. All new keywords disjoint from VQL's 60+ reserved words."))

    (decision "dual-language-split"
      (status accepted)
      (date "2026-03-01")
      (context "Need both formal proofs and practical parsing")
      (decision "Idris2 for type kernel, ReScript for parser")
      (rationale "Idris2 proves properties. ReScript parses queries. Independent operation
                  in experimental phase — no runtime interop needed."))

    (decision "zero-believe-me"
      (status accepted)
      (date "2026-03-01")
      (context "Formal verification integrity")
      (decision "Absolute ban on believe_me, assert_total, assert_smaller")
      (rationale "These undermine formal verification. If a proof cannot be
                  completed, the type definition must be restructured."))

    (decision "zig-0-15-build-api"
      (status accepted)
      (date "2026-03-01")
      (context "Zig 0.15.2 removed addStaticLibrary from Build API")
      (decision "Use addModule + addTest(.root_module) pattern instead of addStaticLibrary")
      (rationale "Zig 0.15 restructured the build system. Module-based approach
                  is the idiomatic pattern. build.zig.zon required for package metadata."))

    (decision "subsumes-argument-order"
      (status accepted)
      (date "2026-03-01")
      (context "Effect subsumption direction was initially backwards")
      (decision "Subsumes declared actual = Subset actual declared (actual is subset of declared)")
      (rationale "A query's actual effects must be a subset of its declared effects.
                  The original direction (Subset declared actual) was backwards,
                  meaning 'every declared effect appears in actual' which is wrong."))

    (decision "no-erased-pattern-match"
      (status accepted)
      (date "2026-03-01")
      (context "Idris2 quantity-0 implicits cannot be pattern-matched at runtime")
      (decision "Removed hasUses function; use type system to distinguish Available from Depleted")
      (rationale "Erased (quantity 0) implicits exist only at type level. Any function
                  that needs to inspect the resource count must take it as a runtime argument.")))

  (development-practices
    (practice "all-modules-total"
      (description "Every Idris2 module uses %default total"))
    (practice "structural-termination"
      (description "All recursive functions prove termination structurally"))
    (practice "parser-combinator-pattern"
      (description "ReScript parser follows VeriSimDB's combinator style"))
    (practice "ipkg-typecheck"
      (description "Use 'idris2 --typecheck file.ipkg' for packages, not --check"))
    (practice "explicit-nesting"
      (description "Non-associative helper functions (andCheck) require explicit nested calls,
                    not backtick infix chaining"))))
