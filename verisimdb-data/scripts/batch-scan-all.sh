#!/usr/bin/env bash
# SPDX-License-Identifier: PMPL-1.0-or-later
#
# Batch scan ALL repos and ingest into verisimdb-data
# Optimized: scans in parallel, single registry update, single commit
#
# Usage: ./scripts/batch-scan-all.sh [--rescan] [--dry-run] [--jobs N]
#   --rescan   Re-scan repos that already have scan data
#   --dry-run  Scan but don't update verisimdb-data
#   --jobs N   Parallel scan jobs (default: 4)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERISIMDB_DATA="$(dirname "$SCRIPT_DIR")"
REPOS_BASE="/var/mnt/eclipse/repos"
SCAN_TMP="/tmp/verisimdb-batch-scans"

# Parse args
RESCAN=false
DRY_RUN=false
JOBS=4

while [[ $# -gt 0 ]]; do
    case "$1" in
        --rescan)  RESCAN=true; shift ;;
        --dry-run) DRY_RUN=true; shift ;;
        --jobs)    JOBS="$2"; shift 2 ;;
        *)         echo "Unknown option: $1"; exit 1 ;;
    esac
done

echo "=== VeriSimDB Full Fleet Scan ==="
echo "Repos base: ${REPOS_BASE}"
echo "Rescan existing: ${RESCAN}"
echo "Dry run: ${DRY_RUN}"
echo "Parallel jobs: ${JOBS}"
echo

# Prepare temp directory
rm -rf "${SCAN_TMP}"
mkdir -p "${SCAN_TMP}"

# Build repo list
REPO_LIST=()
SKIPPED=0
ALREADY_SCANNED=0

for d in "${REPOS_BASE}"/*/; do
    name=$(basename "$d")

    # Skip verisimdb-data itself
    [ "$name" = "verisimdb-data" ] && continue

    # Must be a git repo
    [ -d "${d}.git" ] || { SKIPPED=$((SKIPPED + 1)); continue; }

    # Skip already-scanned unless --rescan
    if [ "$RESCAN" = "false" ] && [ -f "${VERISIMDB_DATA}/scans/${name}.json" ]; then
        ALREADY_SCANNED=$((ALREADY_SCANNED + 1))
        continue
    fi

    REPO_LIST+=("$name")
done

echo "Found ${#REPO_LIST[@]} repos to scan (${ALREADY_SCANNED} already scanned, ${SKIPPED} non-git skipped)"
echo

if [ "${#REPO_LIST[@]}" -eq 0 ]; then
    echo "Nothing to scan. Use --rescan to re-scan existing repos."
    exit 0
fi

# Phase 1: Scan all repos
echo "--- Phase 1: Scanning repos ---"

SCAN_SUCCESS=0
SCAN_FAIL=0
SCAN_EMPTY=0

scan_repo() {
    local name="$1"
    local repo_path="${REPOS_BASE}/${name}"
    local output="${SCAN_TMP}/${name}.json"

    if ASDF_RUST_VERSION=nightly panic-attack assail "$repo_path" --output "$output" 2>/dev/null; then
        # Check if scan produced results
        local wp_count
        wp_count=$(jq '.weak_points | length' "$output" 2>/dev/null || echo "-1")
        if [ "$wp_count" = "-1" ]; then
            echo "FAIL ${name} (invalid JSON)"
            return 1
        else
            echo "OK   ${name} (${wp_count} weak points)"
            return 0
        fi
    else
        echo "FAIL ${name} (scan error)"
        return 1
    fi
}

export -f scan_repo
export REPOS_BASE SCAN_TMP

# Run scans (sequential but fast — ~37ms each)
for name in "${REPO_LIST[@]}"; do
    result=$(scan_repo "$name" 2>&1) || true
    status="${result%%\ *}"
    echo "  $result"
    case "$status" in
        OK)   SCAN_SUCCESS=$((SCAN_SUCCESS + 1)) ;;
        FAIL) SCAN_FAIL=$((SCAN_FAIL + 1)) ;;
    esac
done

echo
echo "Scan results: ${SCAN_SUCCESS} success, ${SCAN_FAIL} failed"
echo

if [ "$DRY_RUN" = "true" ]; then
    echo "Dry run — skipping ingest."
    echo "Scan files in: ${SCAN_TMP}/"
    exit 0
fi

# Phase 2: Copy scans to verisimdb-data
echo "--- Phase 2: Copying scan files ---"

INGESTED=0
for scan_file in "${SCAN_TMP}"/*.json; do
    [ -f "$scan_file" ] || continue
    name=$(basename "$scan_file" .json)
    cp "$scan_file" "${VERISIMDB_DATA}/scans/${name}.json"
    INGESTED=$((INGESTED + 1))
done
echo "Copied ${INGESTED} scan files"
echo

# Phase 3: Rebuild index.json from all scans
echo "--- Phase 3: Rebuilding index.json ---"

TIMESTAMP="$(date -Iseconds)"

# Build a fresh index from ALL scan files
cd "${VERISIMDB_DATA}"

# Start with base structure, preserve existing fields for repos that have them
jq -n --arg time "$TIMESTAMP" '{
    last_updated: $time,
    total_scans: 0,
    repos: {}
}' > index.new.json

total_wp=0
total_repos=0

for scan_file in scans/*.json; do
    [ -f "$scan_file" ] || continue
    name=$(basename "$scan_file" .json)

    wp_count=$(jq '.weak_points | length' "$scan_file" 2>/dev/null || echo "0")
    summary=$(jq -r '.summary // empty' "$scan_file" 2>/dev/null || echo "null")
    total_wp=$((total_wp + wp_count))
    total_repos=$((total_repos + 1))

    # Get existing fields if repo was in old index
    existing_fixes_applied=$(jq -r --arg r "$name" '.repos[$r].fixes_applied // 0' index.json 2>/dev/null || echo "0")
    existing_fixes_pending=$(jq -r --arg r "$name" '.repos[$r].fixes_pending // 0' index.json 2>/dev/null || echo "0")

    jq --arg repo "$name" \
       --arg time "$TIMESTAMP" \
       --argjson wp "$wp_count" \
       --argjson fa "$existing_fixes_applied" \
       --argjson fp "$existing_fixes_pending" \
       '.repos[$repo] = {
          last_scan: $time,
          weak_points: $wp,
          summary: null,
          pattern_ids: [],
          fixes_applied: $fa,
          fixes_pending: $fp,
          triangle_status: {"eliminate": 0, "substitute": 0, "control": 0}
        } |
        .total_scans += 1 |
        .last_updated = $time' \
       index.new.json > index.tmp && mv index.tmp index.new.json
done

mv index.new.json index.json
echo "Index rebuilt: ${total_repos} repos, ${total_wp} total weak points"
echo

# Phase 4: Rebuild pattern registry from all scans
echo "--- Phase 4: Rebuilding pattern registry ---"

REGISTRY_FILE="patterns/registry.json"
SUBSTITUTIONS_FILE="recipes/proven-substitutions.json"

# Start fresh registry
jq -n --arg time "$TIMESTAMP" '{
    description: "Canonical pattern registry — deduplicates findings across repos into trackable patterns",
    last_updated: $time,
    patterns: {}
}' > "${REGISTRY_FILE}.new"

for scan_file in scans/*.json; do
    [ -f "$scan_file" ] || continue
    name=$(basename "$scan_file" .json)

    # Skip scans with no weak points
    wp_count=$(jq '.weak_points | length' "$scan_file" 2>/dev/null || echo "0")
    [ "$wp_count" = "0" ] && continue

    jq --arg repo "$name" \
       --arg time "$TIMESTAMP" \
       --slurpfile subs "$SUBSTITUTIONS_FILE" \
       --slurpfile scan_data "$scan_file" \
    '
    ($subs[0].substitutions | map({(.category): .}) | add) as $sub_lookup |

    reduce ($scan_data[0].weak_points // [] | to_entries[]) as $entry (
      .;
      $entry.value as $wp |
      ($wp.category // "unknown") as $cat |
      ($wp.description // $wp.category // "unknown") as $desc |

      (if $cat == "UncheckedAllocation" then "PA001"
       elif $cat == "UnboundedLoop" then "PA002"
       elif $cat == "BlockingIO" then "PA003"
       elif $cat == "UnsafeCode" then "PA004"
       elif $cat == "PanicPath" then "PA005"
       elif $cat == "RaceCondition" then "PA006"
       elif $cat == "DeadlockPotential" then "PA007"
       elif $cat == "ResourceLeak" then "PA008"
       elif $cat == "CommandInjection" then "PA009"
       elif $cat == "UnsafeDeserialization" then "PA010"
       elif $cat == "DynamicCodeExecution" then "PA011"
       elif $cat == "UnsafeFFI" then "PA012"
       elif $cat == "AtomExhaustion" then "PA013"
       elif $cat == "InsecureProtocol" then "PA014"
       elif $cat == "ExcessivePermissions" then "PA015"
       elif $cat == "PathTraversal" then "PA016"
       elif $cat == "HardcodedSecret" then "PA017"
       elif $cat == "UncheckedError" then "PA018"
       elif $cat == "InfiniteRecursion" then "PA019"
       elif $cat == "UnsafeTypeCoercion" then "PA020"
       else "PA000" end) as $pa_rule |

      ($desc | gsub("[^a-zA-Z0-9]"; "-") | gsub("-+"; "-") | .[0:30] | ascii_downcase) as $slug |
      ($pa_rule + "-" + $slug) as $pattern_id |

      (($sub_lookup[$cat] // {}).triangle_tier // "control") as $tier |

      if .patterns[$pattern_id] then
        .patterns[$pattern_id].occurrences += 1 |
        .patterns[$pattern_id].last_seen = $time |
        (if (.patterns[$pattern_id].repos_affected_list | index($repo)) == null
         then .patterns[$pattern_id].repos_affected += 1 |
              .patterns[$pattern_id].repos_affected_list += [$repo]
         else . end)
      else
        .patterns[$pattern_id] = {
          id: $pattern_id,
          category: $cat,
          severity: ($wp.severity // "Medium"),
          description: $desc,
          pa_rule: $pa_rule,
          occurrences: 1,
          repos_affected: 1,
          repos_affected_list: [$repo],
          first_seen: $time,
          last_seen: $time,
          trend: "new",
          triangle_tier: $tier,
          recipe_id: null
        }
      end
    ) |
    .last_updated = $time
    ' "${REGISTRY_FILE}.new" > "${REGISTRY_FILE}.tmp" && mv "${REGISTRY_FILE}.tmp" "${REGISTRY_FILE}.new"
done

mv "${REGISTRY_FILE}.new" "${REGISTRY_FILE}"

PATTERN_COUNT=$(jq '.patterns | length' "$REGISTRY_FILE")
echo "Pattern registry rebuilt: ${PATTERN_COUNT} unique patterns"

# Phase 5: Update index.json with pattern_ids per repo
echo "--- Phase 5: Linking patterns to repos ---"

for scan_file in scans/*.json; do
    [ -f "$scan_file" ] || continue
    name=$(basename "$scan_file" .json)

    PATTERN_IDS=$(jq -r --arg repo "$name" \
      '[.patterns | to_entries[] | select(.value.repos_affected_list | index($repo)) | .key]' \
      "$REGISTRY_FILE")

    # Count by triangle tier
    ELIM=$(jq -r --arg repo "$name" \
      '[.patterns | to_entries[] | select(.value.repos_affected_list | index($repo)) | select(.value.triangle_tier == "eliminate")] | length' \
      "$REGISTRY_FILE")
    SUBST=$(jq -r --arg repo "$name" \
      '[.patterns | to_entries[] | select(.value.repos_affected_list | index($repo)) | select(.value.triangle_tier == "substitute")] | length' \
      "$REGISTRY_FILE")
    CTRL=$(jq -r --arg repo "$name" \
      '[.patterns | to_entries[] | select(.value.repos_affected_list | index($repo)) | select(.value.triangle_tier == "control")] | length' \
      "$REGISTRY_FILE")

    jq --arg repo "$name" \
       --argjson pids "$PATTERN_IDS" \
       --argjson e "$ELIM" \
       --argjson s "$SUBST" \
       --argjson c "$CTRL" \
       '.repos[$repo].pattern_ids = $pids |
        .repos[$repo].triangle_status = {"eliminate": $e, "substitute": $s, "control": $c} |
        .repos[$repo].fixes_pending = ($pids | length)' \
       index.json > index.tmp && mv index.tmp index.json
done

echo "Pattern linkage complete"
echo

# Phase 6: Summary
echo "=== Batch Scan Complete ==="
echo
echo "Repos scanned: ${total_repos}"
echo "Total weak points: ${total_wp}"
echo "Unique patterns: ${PATTERN_COUNT}"
echo
echo "Triangle distribution:"
jq -r '
  .patterns | to_entries | group_by(.value.triangle_tier) |
  map({tier: .[0].value.triangle_tier, count: length}) |
  sort_by(.tier) |
  .[] | "  \(.tier): \(.count) patterns"
' "$REGISTRY_FILE"
echo
echo "Top 10 most common patterns:"
jq -r '
  [.patterns | to_entries[] | {id: .key, occ: .value.occurrences, repos: .value.repos_affected, cat: .value.category}] |
  sort_by(-.occ) | .[0:10] |
  .[] | "  \(.occ) occurrences across \(.repos) repos: \(.id) [\(.cat)]"
' "$REGISTRY_FILE"
echo
echo "Repos with most weak points:"
jq -r '
  [.repos | to_entries[] | {name: .key, wp: .value.weak_points}] |
  sort_by(-.wp) | .[0:15] |
  .[] | "  \(.wp)\t\(.name)"
' index.json
echo

# Cleanup
rm -rf "${SCAN_TMP}"

echo "Next steps:"
echo "  cd ${VERISIMDB_DATA}"
echo "  git add -A && git commit -m 'scan: full fleet scan (${total_repos} repos)'"
echo "  git push && git push gitlab main"
echo "  cd /var/mnt/eclipse/repos/hypatia"
echo "  mix run -e 'Hypatia.PatternAnalyzer.analyze_all_scans()'"
