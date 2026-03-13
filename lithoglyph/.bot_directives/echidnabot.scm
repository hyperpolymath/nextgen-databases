;; SPDX-License-Identifier: PMPL-1.0-or-later
;; Echidnabot Directives - Code Quality Automation
;;
;; Echidnabot enforces code quality standards, runs static analysis,
;; and ensures industrial-grade code for Lithoglyph.

(echidnabot-config
  (repo-name "lithoglyph")

  (quality-gates
    (block-on-failing-tests #t)
    (block-on-linter-errors #t)
    (block-on-security-issues #t)
    (require-test-coverage 80))

  (zig-analysis
    (run-zig-test #t)
    (check-memory-leaks #t)
    (verify-abi-exports #t)
    (check-alignment #t)
    (verify-block-formats #t))

  (factor-analysis
    (check-syntax #t)
    (verify-ffi-signatures #t)
    (check-for-stubs #t))

  (forth-analysis
    (verify-stack-effects #t)
    (check-block-layout #t)
    (verify-crc-implementation #t))

  (security-checks
    (scan-for-secrets #t)
    (check-for-unsafe-operations #t)
    (verify-input-validation #t)
    (check-buffer-bounds #t))

  (automated-fixes
    (auto-format-code #f)
    (auto-fix-lints #f)
    (suggest-improvements #t))

  (reporting
    (post-pr-comments #t)
    (generate-quality-report #t)
    (track-quality-trends #t)))
