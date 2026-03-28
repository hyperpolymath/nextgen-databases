; SPDX-License-Identifier: PMPL-1.0-or-later
;; guix.scm — GNU Guix package definition for nextgen-databases
;; Usage: guix shell -f guix.scm

(use-modules (guix packages)
             (guix build-system gnu)
             (guix licenses))

(package
  (name "nextgen-databases")
  (version "0.1.0")
  (source #f)
  (build-system gnu-build-system)
  (synopsis "nextgen-databases")
  (description "nextgen-databases — part of the hyperpolymath ecosystem.")
  (home-page "https://github.com/hyperpolymath/nextgen-databases")
  (license ((@@ (guix licenses) license) "PMPL-1.0-or-later"
             "https://github.com/hyperpolymath/palimpsest-license")))
