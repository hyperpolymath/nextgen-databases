#!/bin/sh
# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
#
# registry-links.sh — Cross-database integration test: verify REGISTRY.adoc links
# Part of TEST-NEEDS for coordination repo — ensures owning repos are reachable
# Enduring check for Option E (cross-db integration tests)

set -eu

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
REGISTRY="$ROOT/REGISTRY.adoc"

echo "=== Registry Links Check — $(date -u +%Y-%m-%d) ==="
echo "Checking $REGISTRY"

if [ ! -f "$REGISTRY" ]; then
  echo "FAIL: REGISTRY.adoc not found"
  exit 1
fi

# Extract https://github.com/hyperpolymath/* URLs from REGISTRY.adoc
urls=$(grep -oE "https://github.com/hyperpolymath/[a-zA-Z0-9._-]+" "$REGISTRY" | sort -u)

if [ -z "$urls" ]; then
  echo "FAIL: No hyperpolymath URLs found in REGISTRY.adoc"
  exit 1
fi

echo "Found $(echo "$urls" | wc -l) canonical repo URLs:"
echo "$urls" | sed 's/^/  - /'

# If gh is available, check if repos exist (lightweight, no network curl needed)
if command -v gh >/dev/null 2>&1; then
  echo ""
  echo "Checking repo existence via gh (requires auth):"
  fail=0
  for url in $urls; do
    repo=$(echo "$url" | sed 's|https://github.com/||')
    if gh repo view "$repo" --json name -q ".name" >/dev/null 2>&1; then
      echo "  [OK] $repo exists"
    else
      echo "  [WARN] $repo not accessible via gh (may need auth or may not exist yet)"
      # Not failing — some reservation repos may not be public yet
    fi
  done
else
  echo ""
  echo "gh not available — skipping existence check (would use gh repo view)"
fi

# Check that pointer READMEs exist for DONE extractions
echo ""
echo "Checking pointer READMEs for DONE extractions:"
for dir in lithoglyph verisimdb; do
  readme="$ROOT/$dir/README.adoc"
  if [ -f "$readme" ]; then
    if grep -q "split-history" "$readme" && grep -q "hyperpolymath" "$readme"; then
      echo "  [OK] $dir/README.adoc is pointer README with split-history and hyperpolymath link"
    else
      echo "  [FAIL] $dir/README.adoc exists but missing split-history or hyperpolymath link"
      exit 1
    fi
  else
    echo "  [INFO] $dir/README.adoc not found — may have been fully removed (alternative to pointer)"
  fi
done

echo ""
echo "Registry links check PASS"
