#!/bin/sh
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# block-db-writes.sh — Claude Code PreToolUse hook for nextgen-databases.
#
# nextgen-databases is a COORDINATION repo. Per-database code/docs belong in each
# database's own repo (see REGISTRY.adoc). This hook blocks creation of a NEW file
# inside a legacy per-database directory (that is the misplacement we are stopping),
# while still allowing edits to files that already exist during the transition.
#
# Reads the hook payload (JSON) on stdin. Exit 2 = BLOCK (reason on stderr); 0 = ALLOW.

set -u

payload="$(cat)"
root="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# --- extract a leaf value from the JSON payload ------------------------------
extract() { # $1 = jq path, e.g. .tool_input.file_path
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$payload" | jq -r "$1 // empty" 2>/dev/null
  else
    leaf="${1##*.}"
    printf '%s' "$payload" | tr ',{}' '\n\n\n' \
      | sed -n "s/.*\"${leaf}\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -n1
  fi
}

tool="$(extract .tool_name)"
fp="$(extract .tool_input.file_path)"

# Only police file-writing tools.
case "$tool" in
  Write|Edit|MultiEdit|NotebookEdit) ;;
  *) exit 0 ;;
esac

[ -n "$fp" ] || exit 0

# Normalise to a repo-relative path.
rel="$fp"
case "$fp" in
  "$root"/*) rel="${fp#"$root"/}" ;;
  /*) exit 0 ;;            # absolute path outside the project — not ours to police
esac

# Map a legacy database directory to its destination repo (for a helpful message).
dest=""
case "$rel" in
  verisimdb/*)                  dest="hyperpolymath/verisimdb" ;;
  lithoglyph/glyphbase/*)       dest="hyperpolymath/glyphbase" ;;
  lithoglyph/gql-dt/*)          dest="hyperpolymath/gnpl" ;;
  lithoglyph/*)                 dest="hyperpolymath/lithoglyph" ;;
  quandledb/*)                  dest="hyperpolymath/quandledb" ;;
  nqc/*)                        dest="hyperpolymath/nqc" ;;
  typeql-experimental/*)        dest="hyperpolymath/vcl-ut" ;;
  verisim-core/*)               dest="hyperpolymath/verisim-core (or fold into verisimdb)" ;;
  verisim-modular-experiment/*) dest="" ;;   # research-only — allowed for now
esac

# Block creation of a NEW file in a database directory; allow edits to existing files.
if [ -n "$dest" ] && [ ! -e "$fp" ]; then
  printf '%s\n' "BLOCKED: nextgen-databases is a COORDINATION repo — do not add new per-database content here." 1>&2
  printf '%s\n' "  New file:        $rel" 1>&2
  printf '%s\n' "  This belongs in: $dest  (see REGISTRY.adoc)" 1>&2
  printf '%s\n' "  If this really is coordination content, place it outside the database directories." 1>&2
  exit 2
fi

exit 0
