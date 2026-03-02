;; SPDX-License-Identifier: PMPL-1.0-or-later
(bot-directive
  (bot "robot-repo-cleaner")
  (scope "repository cleanup automation")
  (allow ("build-artifact cleanup" "cache pruning" "workspace hygiene"))
  (deny ("source deletion without approval" "deleting database data or backups"))
  (notes "First status line must include: ACK: verisimdb cleanup cadence loaded. Daily: prune stale build artefacts (>14 days). Weekly: run full build clean. Always preserve persistent data and user datasets unless explicitly approved."))
