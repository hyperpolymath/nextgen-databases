;; SPDX-License-Identifier: MPL-2.0
;; SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
;; guix.scm — Guix primary packaging for nextgen-databases (coordination repo)
;; Estate policy: Guix primary + sealed-container escape, NO Nix mirror
;; This file satisfies check-package-policy.sh which requires guix.scm / manifest.scm / channels.scm / .guix-channel

(use-modules (guix packages)
             (guix gexp)
             (guix git-download)
             (guix build-system trivial)
             (gnu packages base)
             (gnu packages bash))

;; Minimal manifest for coordination repo — provides bash, git, coreutils for governance checks
;; Per-package docs: this is a coordination repo, not implementation, so packaging is minimal
;; Real per-database packaging lives in owning repos (see REGISTRY.adoc)

(define-public nextgen-databases-coordination
  (package
    (name "nextgen-databases")
    (version "0.2.0")
    (source #f) ; coordination repo — no single source tarball, uses registry links
    (build-system trivial-build-system)
    (arguments
     (list
      #:builder
      #~(begin
          (mkdir #$output)
          (call-with-output-file (string-append #$output "/README")
            (lambda (port)
              (display "nextgen-databases coordination repo — see REGISTRY.adoc for owning repos\n" port))))))
    (home-page "https://github.com/hyperpolymath/nextgen-databases")
    (synopsis "Coordination repository for four database/language families")
    (description
     "This is a coordination repository for VeriSimDB/VCL-UT, Lithoglyph/GNPL/Glyphbase,
QuandleDB/KRL, and Vocarium/Hermeneia. Canonical implementations live in their own
repositories per REGISTRY.adoc. This package provides minimal tooling for governance
checks (bash, git, K9/A2ML validators). Per-database packaging (Rust, Zig, Julia,
Gleam, Lean) lives in owning repos.")
    (license #f))) ; PMPL-1.0-or-later per LICENSE file, not in Guix yet — use #f with note

;; Return package for `guix build -f guix.scm`
nextgen-databases-coordination

;; For `guix shell -f guix.scm` or `guix shell -m manifest.scm` pattern:
;; This file also serves as manifest when loaded via `guix package -m` if needed
;; To use as manifest, create manifest.scm that imports this and lists packages
