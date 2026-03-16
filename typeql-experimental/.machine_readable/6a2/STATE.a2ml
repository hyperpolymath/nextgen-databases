;; SPDX-License-Identifier: PMPL-1.0-or-later
(state
  (metadata
    (version "1.0.0")
    (last-updated "2026-03-01")
    (status active))

  (project-context
    (name "typeql-experimental")
    (purpose "Experimental type-theoretic extensions to VQL (VQL-dt++)")
    (completion-percentage 85))

  (current-position
    (phase "initial-implementation-complete")
    (summary "All 37 files implemented across 6 phases. Idris2 kernel (9 modules)
              type-checks clean with --total and zero banned patterns. Zig FFI
              bridge (5 tests) passes. ReScript parser and examples written.
              Six extensions: linear types, session types, effect systems,
              modal types, proof-carrying code, quantitative type theory."))

  (components
    (component "idris2-kernel"
      (status "complete")
      (description "9 Idris2 modules: Core, Linear, Session, Effects, Modal,
                    ProofCarrying, Quantitative, Checker, Proofs. All type-check
                    with %default total. Zero believe_me/assert_total/assert_smaller.")
      (completion 100))
    (component "rescript-parser"
      (status "written")
      (description "Extended AST (TQLAst.res) and parser (TQLParser.res) for 6 new
                    VQL++ clauses. Follows VeriSimDB combinator patterns. Not yet
                    build-tested (requires rescript-legacy toolchain).")
      (completion 70))
    (component "grammar-spec"
      (status "complete")
      (description "Delta EBNF extending VQL v3.0 with 6 new clause types.
                    Documented in docs/vql-dtpp-grammar.ebnf.")
      (completion 100))
    (component "zig-ffi"
      (status "complete")
      (description "C-compatible FFI bridge skeleton. build.zig targets Zig 0.15.2.
                    5 tests pass: empty annotations, consume_after=0, usage<consume,
                    full valid annotations, version string.")
      (completion 100))
    (component "examples"
      (status "complete")
      (description "7 annotated .vqlpp example files covering all 6 extensions
                    individually plus a combined maximal query.")
      (completion 100))
    (component "idris2-tests"
      (status "complete")
      (description "3 compile-time test modules: TestLinear.idr, TestSession.idr,
                    TestQuantitative.idr. Validated by Idris2 type-checker.")
      (completion 100))
    (component "documentation"
      (status "complete")
      (description "README.adoc, DESIGN doc, type-system-spec.adoc, examples.adoc,
                    grammar EBNF, AI manifest, machine-readable SCM files.")
      (completion 100)))

  (route-to-mvp
    (milestone "type-kernel-complete"
      (description "All 9 Idris2 modules type-check with --total, zero believe_me")
      (completion 100))
    (milestone "zig-ffi-tested"
      (description "Zig FFI bridge compiles and all 5 tests pass on Zig 0.15.2")
      (completion 100))
    (milestone "parser-written"
      (description "ReScript parser written with combinator pattern from VeriSimDB")
      (completion 70))
    (milestone "parser-build-tested"
      (description "ReScript parser compiles and accepts all 7 example .vqlpp files")
      (completion 0))
    (milestone "integration"
      (description "Idris2 proofs validated against ReScript-parsed ASTs")
      (completion 0)))

  (verified-results
    (result "idris2-typecheck"
      (command "idris2 --typecheck typeql-experimental.ipkg")
      (outcome "9/9 modules compile clean")
      (date "2026-03-01"))
    (result "zig-tests"
      (command "cd ffi/zig && zig build test")
      (outcome "5/5 tests pass")
      (date "2026-03-01"))
    (result "banned-patterns"
      (command "grep -rn 'believe_me|assert_total|assert_smaller' src/abi/")
      (outcome "zero matches (comment-only reference in Proofs.idr)")
      (date "2026-03-01")))

  (implementation-notes
    (note "idris2-version" "Idris2 0.8.0 — ipkg uses --typecheck not --check")
    (note "zig-version" "Zig 0.15.2 — addModule/addTest API, no addStaticLibrary")
    (note "effects-subsumption" "Subsumes declared actual = Subset actual declared (flipped)")
    (note "erased-implicit" "Cannot pattern-match on quantity-0 implicits (removed hasUses)")
    (note "andCheck-nesting" "Non-associative function requires explicit nested calls"))

  (blockers-and-issues
    (blocker "rescript-build"
      (description "ReScript parser not yet build-tested — needs rescript-legacy or
                    equivalent toolchain. Written code follows VeriSimDB patterns.")))

  (critical-next-actions
    (action "Build-test ReScript parser with rescript-legacy toolchain")
    (action "Test all 7 example .vqlpp files parse correctly")
    (action "Wire Idris2 proof results to ReScript-parsed ASTs (integration phase)")))
