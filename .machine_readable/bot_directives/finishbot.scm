;; SPDX-License-Identifier: PMPL-1.0-or-later
(bot-directive
  (bot "finishbot")
  (scope "release readiness")
  (allow ("release checklists" "docs updates" "metadata fixes" "maintenance reminders"))
  (deny ("code changes without approval" "deleting database data or backups"))
  (notes "First status line must include: ACK: verisimdb cleanup cadence loaded. Ensure release notes and runbooks retain daily stale-prune and weekly full-clean guidance."))
