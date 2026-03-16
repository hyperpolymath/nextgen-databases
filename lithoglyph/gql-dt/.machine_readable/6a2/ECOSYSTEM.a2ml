;; SPDX-License-Identifier: PMPL-1.0-or-later
;; SPDX-FileCopyrightText: 2025 hyperpolymath
;;
;; ECOSYSTEM.scm - Project ecosystem positioning for gql-dt
;; Media-Type: application/vnd.ecosystem+scm

(ecosystem
  (version "1.0.0")
  (name "gql-dt")
  (type "language-extension")
  (purpose "Add dependent types to Lithoglyph Query Language for compile-time verification")

  (position-in-ecosystem
    (layer "query-language")
    (role "type-safe frontend to Lithoglyph")
    (integration-point "Form.Bridge (Zig FFI)"))

  (related-projects
    (project
      (name "lithoglyph")
      (repo "https://github.com/hyperpolymath/lithoglyph")
      (relationship sibling-standard)
      (description "The narrative-first database that FQLdt queries")
      (integration "FQLdt compiles to operations on Form.Model via Form.Bridge"))

    (project
      (name "lithoglyph-studio")
      (repo "https://github.com/hyperpolymath/lithoglyph-studio")
      (relationship potential-consumer)
      (description "Zero-friction GUI that could use FQLdt for type-safe queries"))

    (project
      (name "lithoglyph-debugger")
      (repo "https://github.com/hyperpolymath/lithoglyph-debugger")
      (relationship sibling-standard)
      (description "Proof-carrying database debugger (Lean 4 + Idris 2)")
      (integration "Shares Lean 4 proof infrastructure"))

    (project
      (name "bofig")
      (repo "https://github.com/hyperpolymath/bofig")
      (relationship potential-consumer)
      (description "Evidence graph for investigative journalism")
      (integration "Primary use case for PROMPT score types"))

    (project
      (name "zotero-lithoglyph")
      (repo "https://github.com/hyperpolymath/zotero-lithoglyph")
      (relationship potential-consumer)
      (description "Reference manager with PROMPT scores")
      (integration "Production pilot for refinement types"))

    (project
      (name "formbase")
      (repo "https://github.com/hyperpolymath/formbase")
      (relationship potential-consumer)
      (description "Open-source Airtable alternative with provenance")
      (integration "Could use FQLdt for verified data entry"))

    (project
      (name "lean4")
      (repo "https://github.com/leanprover/lean4")
      (relationship inspiration)
      (description "Dependent type theory implementation")
      (integration "Primary implementation language for type system"))

    (project
      (name "mathlib4")
      (repo "https://github.com/leanprover-community/mathlib4")
      (relationship dependency)
      (description "Lean 4 mathematical library")
      (integration "Provides tactics and proof automation")))

  (what-this-is
    (item "Dependent type extension for GQL")
    (item "Compile-time constraint verification")
    (item "Provenance tracking at type level")
    (item "PROMPT score type safety")
    (item "Reversibility proofs for operations")
    (item "Lean 4 implementation with Zig FFI"))

  (what-this-is-not
    (item "Not a replacement for standard GQL (backward compatible)")
    (item "Not a general-purpose dependently-typed language")
    (item "Not a database engine (uses Lithoglyph)")
    (item "Not required for Lithoglyph usage (optional verification layer)")))
