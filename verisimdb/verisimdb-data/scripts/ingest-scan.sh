#!/usr/bin/env bash
# SPDX-License-Identifier: PMPL-1.0-or-later
#
# Manual scan ingestion helper for verisimdb-data
# Usage: ./scripts/ingest-scan.sh <repo-name> <scan-result.json>
#
# Updates: scans/, index.json, and patterns/registry.json

set -euo pipefail

REPO_NAME="${1:-}"
SCAN_FILE="${2:-}"
NO_COMMIT=false
[[ "${3:-}" == "--no-commit" ]] && NO_COMMIT=true

if [[ -z "$REPO_NAME" || -z "$SCAN_FILE" ]]; then
    echo "Usage: $0 <repo-name> <scan-result.json> [--no-commit]"
    echo
    echo "Example:"
    echo "  cd ~/Documents/hyperpolymath-repos/echidna"
    echo "  panic-attack assail . --output /tmp/echidna-scan.json"
    echo "  cd ~/Documents/hyperpolymath-repos/verisimdb-data"
    echo "  ./scripts/ingest-scan.sh echidna /tmp/echidna-scan.json"
    exit 1
fi

if [[ ! -f "$SCAN_FILE" ]]; then
    echo "Error: Scan file not found: $SCAN_FILE"
    exit 1
fi

# Get repository root
REPO_ROOT=$(git rev-parse --show-toplevel)
cd "$REPO_ROOT"

echo "Ingesting scan for $REPO_NAME..."

# Copy scan result
cp "$SCAN_FILE" "scans/${REPO_NAME}.json"
echo "  Copied scan to scans/${REPO_NAME}.json"

# Update index.json with extended fields
SCAN_DATA=$(cat "scans/${REPO_NAME}.json")
TIMESTAMP="$(date -Iseconds)"

jq --arg repo "$REPO_NAME" \
   --arg time "$TIMESTAMP" \
   --argjson scan_data "$SCAN_DATA" \
   '.repos[$repo] = {
      last_scan: $time,
      weak_points: ($scan_data.weak_points | length),
      summary: $scan_data.summary,
      pattern_ids: (.repos[$repo].pattern_ids // []),
      fixes_applied: (.repos[$repo].fixes_applied // 0),
      fixes_pending: (.repos[$repo].fixes_pending // 0),
      triangle_status: (.repos[$repo].triangle_status // {"eliminate": 0, "substitute": 0, "control": 0})
    } |
    .total_scans += 1 |
    .last_updated = $time' \
   index.json > index.tmp && mv index.tmp index.json

echo "  Updated index.json"

# Update pattern registry from scan weak_points
REGISTRY_FILE="patterns/registry.json"
SUBSTITUTIONS_FILE="recipes/proven-substitutions.json"

if [[ -f "$REGISTRY_FILE" && -f "$SUBSTITUTIONS_FILE" ]]; then
    # Extract unique (category, description) pairs and update registry
    jq --arg repo "$REPO_NAME" \
       --arg time "$TIMESTAMP" \
       --slurpfile subs "$SUBSTITUTIONS_FILE" \
       --argjson scan_data "$SCAN_DATA" \
    '
    # Build a lookup from PA category to substitution info
    ($subs[0].substitutions | map({(.category): .}) | add) as $sub_lookup |

    # Process each weak point from the scan
    reduce ($scan_data.weak_points // [] | to_entries[]) as $entry (
      .;
      $entry.value as $wp |
      ($wp.category // "unknown") as $cat |
      ($wp.description // $wp.category // "unknown") as $desc |

      # Build pattern ID from category
      # Map known categories to PA rule numbers
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

      # Generate a short description slug
      ($desc | gsub("[^a-zA-Z0-9]"; "-") | gsub("-+"; "-") | .[0:30] | ascii_downcase) as $slug |
      ($pa_rule + "-" + $slug) as $pattern_id |

      # Get triangle tier from substitutions lookup
      (($sub_lookup[$cat] // {}).triangle_tier // "control") as $tier |

      # Update or create pattern entry
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
    ' "$REGISTRY_FILE" > "${REGISTRY_FILE}.tmp" && mv "${REGISTRY_FILE}.tmp" "$REGISTRY_FILE"

    # Update index.json with pattern_ids for this repo
    PATTERN_IDS=$(jq -r --arg repo "$REPO_NAME" \
      '[.patterns | to_entries[] | select(.value.repos_affected_list | index($repo)) | .key]' \
      "$REGISTRY_FILE")

    jq --arg repo "$REPO_NAME" \
       --argjson pids "$PATTERN_IDS" \
       '.repos[$repo].pattern_ids = $pids' \
       index.json > index.tmp && mv index.tmp index.json

    echo "  Updated pattern registry"
fi

# Show summary
WEAK_COUNT=$(jq '.weak_points | length' "scans/${REPO_NAME}.json")
PATTERN_COUNT=$(jq --arg repo "$REPO_NAME" \
  '[.patterns | to_entries[] | select(.value.repos_affected_list | index($repo))] | length' \
  "$REGISTRY_FILE" 2>/dev/null || echo 0)

echo "  Found $WEAK_COUNT weak points in $REPO_NAME ($PATTERN_COUNT unique patterns)"

# Commit (unless --no-commit)
if [ "$NO_COMMIT" = "false" ]; then
    git add "scans/${REPO_NAME}.json" index.json patterns/ recipes/ outcomes/
    git commit -m "scan: update ${REPO_NAME} results

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
    echo "  Committed changes"
else
    echo "  Skipped commit (--no-commit)"
fi
echo
echo "Next steps:"
echo "  git push"
echo "  git push gitlab main"
