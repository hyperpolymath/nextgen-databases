#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Post-commit hook: auto-ingest the latest commit into .verisimdb/
#
# Install: cp scripts/post-commit-hook.sh .git/hooks/post-commit

REPO_ROOT="$(git rev-parse --show-toplevel)"
"${REPO_ROOT}/scripts/self-ingest.sh" --recent 1 2>/dev/null || true
