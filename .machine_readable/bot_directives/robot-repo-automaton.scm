;; SPDX-License-Identifier: PMPL-1.0-or-later
(bot-directive
  (bot "robot-repo-automaton")
  (scope "automated repo maintenance and low-risk fixes")
  (allow ("low-risk automated edits" "build-artifact cleanup" "metadata hygiene"))
  (deny ("core logic changes without approval" "deleting database data or backups"))
  (notes "First status line must include: ACK: verisimdb cleanup cadence loaded. Daily: prune stale build artefacts (>14 days). Weekly: run full build clean. Always preserve persistent data and user datasets unless explicitly approved."))
