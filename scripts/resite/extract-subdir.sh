#!/bin/sh
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# extract-subdir.sh — history-preserving extraction of a subdirectory into a new repo.
# Part of the resite runbook: docs/migration/RESITE-DATABASES-TO-OWN-REPOS.adoc
#
# This DOES NOT push and DOES NOT modify your working clone. It produces a rewritten
# clone in a temp directory for review.
#
# Usage:
#   scripts/resite/extract-subdir.sh <subdir> [dest-git-url]
# Example:
#   scripts/resite/extract-subdir.sh nqc/ https://github.com/hyperpolymath/nqc.git
#
# Requires: git, git-filter-repo (https://github.com/newren/git-filter-repo).

set -eu

SUBDIR="${1:-}"
DEST_URL="${2:-}"

if [ -z "$SUBDIR" ]; then
  echo "usage: $0 <subdir> [dest-git-url]" 1>&2
  exit 64
fi

# Normalise trailing slash.
case "$SUBDIR" in */) ;; *) SUBDIR="$SUBDIR/" ;; esac

if ! git filter-repo --help >/dev/null 2>&1; then
  echo "error: git-filter-repo is required." 1>&2
  echo "       install: https://github.com/newren/git-filter-repo" 1>&2
  exit 69
fi

SRC_ROOT="$(git rev-parse --show-toplevel)"
WORK="$(mktemp -d)/extract"

echo ">> Cloning coordination repo into $WORK (local history copy)"
git clone --no-local "$SRC_ROOT" "$WORK"
cd "$WORK"

echo ">> Rewriting history to '$SUBDIR' (moved to repo root; history preserved)"
git filter-repo --path "$SUBDIR" --path-rename "$SUBDIR:"

echo ">> Done. Rewritten repo is at: $WORK"
echo "   Review it, then to publish:"
if [ -n "$DEST_URL" ]; then
  echo "     cd $WORK && git remote add dest $DEST_URL && git push dest HEAD:main"
else
  echo "     cd $WORK && git remote add dest <dest-git-url> && git push dest HEAD:main"
fi
echo ">> NOTE: nothing was pushed. Removing '$SUBDIR' from the coordination repo is a"
echo "   separate, manual step (see the runbook)."
