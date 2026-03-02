#!/usr/bin/env bash
# SPDX-License-Identifier: PMPL-1.0-or-later
#
# Scan multiple repos and ingest results into verisimdb-data
# Usage: ./scripts/scan-all.sh [repo1 repo2 ...]
#        ./scripts/scan-all.sh  # scans default repos

set -euo pipefail

# Default repos to scan (pilot set + IDApixiTIK enrollment)
DEFAULT_REPOS=(
    "echidna"
    "ambientops"
    "verisimdb"
    "IDApixiTIK"
)

REPOS_TO_SCAN=("${@:-${DEFAULT_REPOS[@]}}")
if [[ -d "/var/mnt/eclipse/repos" ]]; then
    REPOS_BASE="/var/mnt/eclipse/repos"
else
    REPOS_BASE="$HOME/Documents/hyperpolymath-repos"
fi
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERISIMDB_DATA="$(dirname "$SCRIPT_DIR")"

echo "=== VeriSimDB Bulk Scanner ==="
echo "Scanning ${#REPOS_TO_SCAN[@]} repos..."
echo

for REPO in "${REPOS_TO_SCAN[@]}"; do
    REPO_PATH="$REPOS_BASE/$REPO"

    if [[ ! -d "$REPO_PATH" ]]; then
        echo "⚠️  Skipping $REPO (not found at $REPO_PATH)"
        continue
    fi

    echo "📊 Scanning $REPO..."

    # Run panic-attack scan
    SCAN_FILE="/tmp/${REPO}-scan.json"
    (cd "$REPO_PATH" && panic-attack assail . --output "$SCAN_FILE") || {
        echo "❌ Scan failed for $REPO"
        continue
    }

    # Ingest the result
    "$SCRIPT_DIR/ingest-scan.sh" "$REPO" "$SCAN_FILE" || {
        echo "❌ Ingest failed for $REPO"
        continue
    }

    echo "✓ Completed $REPO"
    echo
done

echo "=== Scan Complete ==="
echo
echo "Summary:"
jq -r '.repos | to_entries | map("\(.key): \(.value.weak_points) weak points") | .[]' "$VERISIMDB_DATA/index.json"
echo
echo "Total scans: $(jq '.total_scans' "$VERISIMDB_DATA/index.json")"
echo
echo "Next steps:"
echo "  cd $VERISIMDB_DATA"
echo "  git push"
echo "  git push gitlab main"
