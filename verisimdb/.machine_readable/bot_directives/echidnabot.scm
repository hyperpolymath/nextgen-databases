;; SPDX-License-Identifier: PMPL-1.0-or-later
(bot-directive
  (bot "echidnabot")
  (scope "formal verification and fuzzing")
  (allow ("analysis" "fuzzing" "proof checks"))
  (deny ("write to core modules" "write to bindings" "deleting database data or backups"))
  (notes "First status line must include: ACK: verisimdb cleanup cadence loaded. If maintenance tasks are requested, follow cadence: daily stale-prune (>14 days), weekly full build clean."))
