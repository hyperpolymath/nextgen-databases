;; SPDX-License-Identifier: PMPL-1.0-or-later
;; Bot Directives - Lithoglyph
;;
;; This directory contains directives for the gitbot-fleet automation system.
;; Bots read these files to understand how to operate on this repository.

(bot-directives
  (version "1.0")
  (repo "lithoglyph")
  (fleet-members
    "rhodibot"    ; Git operations
    "echidnabot"  ; Code quality
    "sustainabot" ; Dependency updates
    "seambot"     ; Integration checks
    "finishbot")) ; Task completion

;; Bot Responsibilities:
;;
;; rhodibot - Automated git operations (commits, tags, releases)
;; echidnabot - Code quality enforcement (linting, tests, analysis)
;; sustainabot - Dependency updates (Zig, Factor, Elixir packages)
;; seambot - Integration verification (cross-language FFI checks)
;; finishbot - Task completion tracking (TODOs, milestones)

;; Configuration Format:
;; Each bot has its own .scm file defining its behavior for this repo.
;; The format is S-expression based for easy parsing by Scheme/Elixir bots.
