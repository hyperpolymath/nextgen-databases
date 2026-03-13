;; SPDX-License-Identifier: PMPL-1.0-or-later
;; SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath)
;;
;; PLAYBOOK.scm - Operational runbook for Lithoglyph
;; Media-Type: application/x-scheme

(define-module (lithoglyph playbook)
  #:version "1.0.0"
  #:updated "2026-03-13T00:00:00Z")

;; ============================================================================
;; BUILD PROCEDURES
;; ============================================================================

(define build-procedures
  '((full-build
      (description . "Build all components in dependency order")
      (steps
        "1. core-forth: gforth test/lithoglyph-tests.fs
         2. core-zig: cd core-zig && zig build test
         3. ffi/zig: cd ffi/zig && zig build test
         4. Idris2 ABI: idris2 --source-dir src --check src/Lith/FormBridge.idr
                        idris2 --source-dir src --check src/Lith/FormLayout.idr
                        idris2 --source-dir src --check src/Lith/FormForeign.idr
         5. normalizer: cd normalizer && lake build
         6. BEAM Rust NIF: cd beam/native_rust && cargo build
         7. BEAM Zig NIF: cd beam/native && zig build
         8. lith-http: cd lith-http && mix deps.get && mix compile && mix test")
      (shortcut . "just build-all")
      (success-criteria
        "- core-forth: 17/17 tests pass
         - core-zig: BUILD + TEST PASS
         - ffi/zig: BUILD + TEST PASS
         - Idris2: all 3 files type-check clean
         - normalizer: 52 proofs pass
         - BEAM NIFs: both build
         - lith-http: mix test passes"))

    (quick-check
      (description . "Fast verification of core components only")
      (steps
        "1. cd core-zig && zig build test
         2. cd ffi/zig && zig build test
         3. cd core-forth && gforth test/lithoglyph-tests.fs")
      (shortcut . "just test")
      (success-criteria
        "- All three pass without errors"))))

;; ============================================================================
;; DEPLOYMENT PLAYBOOKS
;; ============================================================================

(define deployment-playbooks
  '((container-deployment
      (phases
        ((phase "Build Container Image")
         (steps
           "1. Verify Containerfile uses cgr.dev/chainguard/wolfi-base:latest
            2. Build: podman build -t lithoglyph:latest -f Containerfile .
            3. Sign: cerro-torre sign lithoglyph:latest (ML-DSA-87)
            4. Verify: cerro-torre verify lithoglyph:latest")
         (success-criteria
           "- Image builds without errors
            - Image signed with ML-DSA-87
            - Signature verification passes"))

        ((phase "Deploy with selur-compose")
         (steps
           "1. Review selur-compose.yml configuration
            2. Deploy: selur up -f selur-compose.yml
            3. Health check: curl http://localhost:4000/health
            4. Verify svalinn TLS gateway: curl https://localhost:8443/health")
         (success-criteria
           "- All services start
            - Health endpoints return 200
            - TLS termination working via svalinn"))

        ((phase "Post-Deploy Verification")
         (steps
           "1. Run smoke tests against HTTP API
            2. Verify WAL journal is writing
            3. Check Forth block storage is accessible
            4. Confirm BEAM NIFs loaded")
         (success-criteria
           "- Smoke tests pass
            - Journal entries appearing
            - Block read/write working
            - NIF functions callable from Elixir"))))))

;; ============================================================================
;; INCIDENT RESPONSE
;; ============================================================================

(define incident-response
  '((block-corruption
      (severity . "critical")
      (symptoms
        "- Block checksum mismatch
         - core-zig bridge returns error on read
         - Forth kernel reports invalid block header")
      (steps
        "1. STOP: Do not write to affected blocks
         2. Identify: which block(s) are corrupted via core-zig diagnostics
         3. Journal replay: attempt recovery from WAL
         4. If WAL replay fails: restore from backup
         5. Post-mortem: check Idris2 ABI proofs still hold")
      (escalation . "If >10 blocks corrupted, escalate to full restore"))

    (abi-violation
      (severity . "critical")
      (symptoms
        "- Idris2 type-check fails after code change
         - C ABI call returns unexpected values
         - Memory layout proof failure")
      (steps
        "1. STOP: Revert the change that caused the violation
         2. Verify: idris2 --check all 3 ABI files
         3. Check: core-zig bridge test suite
         4. If ABI changed intentionally: update all 18 FFI declarations
         5. Re-verify: full build cycle")
      (escalation . "Never ship with ABI violations — hard block on release"))

    (believe-me-introduced
      (severity . "critical")
      (symptoms
        "- grep finds believe_me in src/Lith/
         - echidnabot CRITICAL alert
         - hypatia scan flags violation")
      (steps
        "1. IMMEDIATE: Remove believe_me — replace with proper proof
         2. If proof is non-trivial: use %foreign prim__callbackToAnyPtr pattern
         3. Verify: idris2 --check affected file
         4. Post-mortem: how did this get past CI?")
      (escalation . "This is a hard invariant — 0 believe_me is non-negotiable"))))

;; ============================================================================
;; OPERATIONAL CONTACTS
;; ============================================================================

(define contacts
  '((maintainer
      (name . "Jonathan D.A. Jewell")
      (email . "j.d.a.jewell@open.ac.uk")
      (github . "hyperpolymath"))
    (bots
      (rhodibot . "Repository standards enforcement")
      (echidnabot . "Dangerous pattern detection")
      (sustainabot . "Dependency freshness"))
    (ci-cd
      (hypatia . "Neurosymbolic CI/CD scanning")
      (github-actions . "Standard workflow suite"))))
