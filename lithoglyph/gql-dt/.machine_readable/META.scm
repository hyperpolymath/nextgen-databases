;; SPDX-License-Identifier: PMPL-1.0-or-later
;; SPDX-FileCopyrightText: 2025 hyperpolymath
;;
;; META.scm - Meta-level information for fdql-dt
;; Media-Type: application/meta+scheme

(meta
  (version "1.0.0")
  (project "fdql-dt")

  (architecture-decisions
    (adr-001
      (status accepted)
      (date "2025-01-11")
      (title "Use Lean 4 as implementation language")
      (context
        "Need a dependently-typed language for compile-time verification. "
        "Options considered: Lean 4, Idris 2, Agda, F*, Dafny.")
      (decision
        "Use Lean 4 for implementation.")
      (consequences
        (positive
          "Best LSP/IDE support (VSCode extension)"
          "Large proof library (Mathlib4)"
          "Good performance (compiled, not interpreted)"
          "Active development and community")
        (negative
          "Steeper learning curve than F*/Dafny"
          "Less mature than Agda for research")))

    (adr-002
      (status accepted)
      (date "2025-01-11")
      (title "Zig for FFI bridge to Lithoglyph")
      (context
        "Lithoglyph core is written in Forth. Need FFI to Lean 4. "
        "Options: C headers, Zig, Rust.")
      (decision
        "Use Zig for Form.Bridge with callconv(.C) for interop.")
      (consequences
        (positive
          "No C headers or libc dependency"
          "Stable ABI via C calling convention"
          "Memory safety without runtime overhead"
          "Bidirectional FFI (Lean -> Zig -> Forth and back)")
        (negative
          "Additional language in stack"
          "Zig is still pre-1.0")))

    (adr-003
      (status accepted)
      (date "2025-01-11")
      (title "Backward compatibility with standard GQL")
      (context
        "Existing GQL code should continue to work. "
        "Question: require explicit opt-in or default to dependent types?")
      (decision
        "Standard GQL is valid in dependent-type mode. Types are inferred. "
        "Explicit WITH DEPENDENT_TYPES for new type features.")
      (consequences
        (positive
          "Zero migration cost for existing queries"
          "Gradual adoption possible"
          "Clear separation of concerns")
        (negative
          "Two modes to maintain"
          "Potential confusion about which mode is active")))

    (adr-004
      (status proposed)
      (date "2025-01-12")
      (title "Refinement types before full dependent types")
      (context
        "Full dependent types are complex. Refinement types (BoundedNat, NonEmptyString) "
        "provide significant value with less complexity.")
      (decision
        "MVP focuses on refinement types (Phase 1). Full dependent types in Phase 2-3.")
      (consequences
        (positive
          "Faster time to value"
          "Simpler proof obligations"
          "Validates core architecture before complexity")
        (negative
          "Some use cases deferred"
          "May need refactoring for full dependent types")))

    (adr-005
      (status proposed)
      (date "2025-01-12")
      (title "Proof blob serialization format")
      (context
        "Lean 4 proofs need to be passed through Zig FFI to Forth core. "
        "Options: JSON, MessagePack, custom binary, CBOR.")
      (decision
        "To be decided. Leaning toward CBOR for compactness and schema support.")
      (consequences
        (positive "TBD")
        (negative "TBD"))))

  (development-practices
    (code-style
      (lean4 "Follow mathlib4 style guide")
      (zig "Follow Zig style guide, no allocator in FFI boundary")
      (comments "Document proof strategies, not obvious code"))

    (security
      (principle "Type safety is security")
      (guideline "All external input must be validated via refinement types")
      (guideline "Proof blobs must be verifiable, not trusted blindly"))

    (testing
      (unit "Lean 4 #check and example for type checking")
      (property "QuickCheck-style testing via Plausible")
      (integration "End-to-end GQL string to Forth operation"))

    (versioning
      (scheme "SemVer")
      (breaking "Major version for type system changes")
      (note "Spec version may differ from implementation version"))

    (documentation
      (specs "Markdown in spec/")
      (api "Lean 4 docstrings")
      (examples "In spec files and tests"))

    (branching
      (main "main - stable, reviewed")
      (feature "feat/* - work in progress")
      (release "release/* - preparation for tags")))

  (design-rationale
    (why-dependent-types
      "Runtime constraint checks catch errors too late. "
      "Type-level proofs make invalid states unrepresentable. "
      "PROMPT scores in [0,100] should be enforced by the type system, not runtime checks.")

    (why-provenance-in-types
      "Lithoglyph's core value is provenance tracking. "
      "If provenance is optional, it will be skipped. "
      "Type-level enforcement makes provenance non-negotiable.")

    (why-reversibility-proofs
      "Journalism requires corrections and retractions. "
      "Proving operations have inverses ensures auditability. "
      "Irreversible operations (GDPR deletion) must be explicitly justified.")

    (why-not-typescript
      "TypeScript's type system is too weak for dependent types. "
      "Refinement types require theorem proving, not just type inference. "
      "Per RSR: TypeScript is banned, use ReScript for JS-targeting code.")))
