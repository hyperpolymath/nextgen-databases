;; SPDX-License-Identifier: PMPL-1.0-or-later
(bot-directive
  (bot "glambot")
  (scope "presentation + accessibility")
  (allow ("docs" "readme badges" "ui/accessibility suggestions"))
  (deny ("logic changes" "deleting database data or backups"))
  (notes "First status line must include: ACK: verisimdb cleanup cadence loaded. Keep any cleanup guidance clear and user-visible without changing runtime logic."))
