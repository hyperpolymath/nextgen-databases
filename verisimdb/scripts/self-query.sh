#!/usr/bin/env bash
# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <jonathan.jewell@open.ac.uk>
#
# self-query.sh — Query the self-hosted .verisimdb/ instance.
#
# Usage:
#   ./scripts/self-query.sh search "drift"       # Full-text search
#   ./scripts/self-query.sh type feature          # Filter by commit type
#   ./scripts/self-query.sh stats                 # Show statistics
#   ./scripts/self-query.sh issues [open|resolved]# List known issues
#   ./scripts/self-query.sh big                   # Largest commits by insertions
#   ./scripts/self-query.sh recent [N]            # Most recent N hexads

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
HEXAD_DIR="${REPO_ROOT}/.verisimdb/hexads"
INDEX_FILE="${REPO_ROOT}/.verisimdb/index.json"

# ============================================================================
# Query functions
# ============================================================================

cmd_search() {
    local query="$1"
    echo "Searching for: ${query}"
    echo "---"
    local count=0
    for f in "${HEXAD_DIR}"/*.json; do
        if grep -iq "$query" "$f" 2>/dev/null; then
            local id title type
            id=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d['id'])" "$f")
            title=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d['document']['title'])" "$f")
            type=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('document',{}).get('fields',{}).get('type','?'))" "$f")
            local date
            date=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('temporal',{}).get('timestamp','?')[:10])" "$f")
            printf "  [%s] %-14s %s  %s\n" "$date" "$id" "($type)" "$title"
            count=$((count + 1))
        fi
    done
    echo "---"
    echo "${count} results."
}

cmd_type() {
    local commit_type="$1"
    echo "Commits of type: ${commit_type}"
    echo "---"
    local count=0
    for f in "${HEXAD_DIR}"/commit-*.json; do
        local ctype
        ctype=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('semantic',{}).get('properties',{}).get('conventional_commit_type',''))" "$f" 2>/dev/null)
        if [ "$ctype" = "$commit_type" ]; then
            local id title date
            id=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d['id'])" "$f")
            title=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d['document']['title'])" "$f")
            date=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('temporal',{}).get('timestamp','?')[:10])" "$f")
            printf "  [%s] %-20s %s\n" "$date" "$id" "$title"
            count=$((count + 1))
        fi
    done
    echo "---"
    echo "${count} ${commit_type} commits."
}

cmd_stats() {
    echo "VeriSimDB Self-Hosted Instance Statistics"
    echo "========================================="

    if [ -f "$INDEX_FILE" ]; then
        python3 -c "
import json
d = json.load(open('$INDEX_FILE'))
s = d['stats']
print(f\"  Total hexads:  {s['total_hexads']}\")
print(f\"  Commits:       {s['commits']}\")
print(f\"  Known issues:  {s['known_issues']}\")
print(f\"  Generated:     {d['generated_at']}\")
"
    fi

    echo ""
    echo "Commit type breakdown:"
    python3 -c "
import json, os, collections
types = collections.Counter()
total_ins = 0
total_del = 0
for f in sorted(os.listdir('$HEXAD_DIR')):
    if not f.startswith('commit-'): continue
    d = json.load(open(os.path.join('$HEXAD_DIR', f)))
    ct = d.get('semantic',{}).get('properties',{}).get('conventional_commit_type','other')
    types[ct] += 1
    tensor = d.get('tensor',{}).get('data',[0,0,0])
    total_ins += tensor[0]
    total_del += tensor[1]
for t, c in types.most_common():
    print(f'  {t:15s} {c:4d}')
print(f'')
print(f'  Total insertions: {int(total_ins):,}')
print(f'  Total deletions:  {int(total_del):,}')
print(f'  Net lines:        {int(total_ins - total_del):+,}')
"

    echo ""
    echo "Known issues:"
    python3 -c "
import json, os, collections
statuses = collections.Counter()
for f in sorted(os.listdir('$HEXAD_DIR')):
    if not f.startswith('issue-'): continue
    d = json.load(open(os.path.join('$HEXAD_DIR', f)))
    s = d.get('document',{}).get('fields',{}).get('status','unknown')
    statuses[s] += 1
for s, c in statuses.most_common():
    print(f'  {s:15s} {c:4d}')
"
}

cmd_issues() {
    local filter="${1:-all}"
    echo "Known Issues (filter: ${filter})"
    echo "---"
    for f in "${HEXAD_DIR}"/issue-*.json; do
        [ -f "$f" ] || continue
        local status title id
        id=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d['id'])" "$f")
        title=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d['document']['title'])" "$f")
        status=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('document',{}).get('fields',{}).get('status','?'))" "$f")

        if [ "$filter" = "all" ] || [ "$filter" = "$status" ]; then
            local marker="  "
            [ "$status" = "resolved" ] && marker="ok"
            [ "$status" = "open" ] && marker="!!"
            printf "  [%s] %-12s %s\n" "$marker" "$id" "$title"
        fi
    done
}

cmd_big() {
    echo "Largest commits by insertions:"
    echo "---"
    python3 -c "
import json, os
commits = []
for f in sorted(os.listdir('$HEXAD_DIR')):
    if not f.startswith('commit-'): continue
    d = json.load(open(os.path.join('$HEXAD_DIR', f)))
    tensor = d.get('tensor',{}).get('data',[0,0,0])
    commits.append((tensor[0], tensor[1], tensor[2], d['id'], d['document']['title'][:60]))
commits.sort(reverse=True)
for ins, dels, files, cid, title in commits[:15]:
    print(f'  +{int(ins):5d} -{int(dels):5d}  ({int(files):2d} files)  {title}')
"
}

cmd_recent() {
    local n="${1:-10}"
    echo "Most recent ${n} hexads:"
    echo "---"
    python3 -c "
import json, os
hexads = []
for f in sorted(os.listdir('$HEXAD_DIR')):
    d = json.load(open(os.path.join('$HEXAD_DIR', f)))
    ts = d.get('temporal',{}).get('timestamp','1970-01-01')
    hexads.append((ts, d['id'], d['document']['title'][:70], d.get('document',{}).get('fields',{}).get('type','?')))
hexads.sort(reverse=True)
for ts, hid, title, htype in hexads[:${n}]:
    print(f'  [{ts[:10]}] {hid:20s}  ({htype:12s})  {title}')
"
}

# ============================================================================
# Main
# ============================================================================

case "${1:-help}" in
    search)  cmd_search "${2:?Usage: self-query.sh search <query>}" ;;
    type)    cmd_type "${2:?Usage: self-query.sh type <feat|fix|docs|chore>}" ;;
    stats)   cmd_stats ;;
    issues)  cmd_issues "${2:-all}" ;;
    big)     cmd_big ;;
    recent)  cmd_recent "${2:-10}" ;;
    *)
        echo "Usage: self-query.sh <command> [args]"
        echo ""
        echo "Commands:"
        echo "  search <query>       Full-text search across all hexads"
        echo "  type <commit-type>   Filter commits by type (feat/fix/docs/chore)"
        echo "  stats                Show instance statistics"
        echo "  issues [status]      List known issues (all/open/resolved)"
        echo "  big                  Largest commits by insertions"
        echo "  recent [N]           Most recent N hexads"
        ;;
esac
