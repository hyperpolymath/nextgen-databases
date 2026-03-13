;; SPDX-License-Identifier: PMPL-1.0-or-later
;; Rhodibot Directives - Git Operations Automation
;;
;; Rhodibot handles automated git operations, commit standardization,
;; and repository health maintenance for Lithoglyph.

(rhodibot-config
  (repo-name "lithoglyph")
  (primary-language "zig")
  (additional-languages "factor" "forth" "elixir")

  (commit-standards
    (format "conventional-commits")
    (scopes "core-zig" "core-factor" "core-forth" "api" "docs" "tests")
    (require-co-author #t)
    (co-author "Claude Sonnet 4.5 <noreply@anthropic.com>")
    (sign-commits #f))

  (branch-protection
    (main-branch "main")
    (require-reviews 1)
    (require-tests-pass #t)
    (allow-force-push #f))

  (automated-tasks
    (auto-rebase #f)
    (auto-merge-dependabot #f)
    (auto-tag-releases #t)
    (sync-forks #t))

  (monitoring
    (check-for-drift #t)
    (verify-ci-status #t)
    (alert-on-failed-builds #t))

  (cleanup-rules
    (delete-merged-branches #t)
    (squash-on-merge #f)
    (update-changelog #t)))
