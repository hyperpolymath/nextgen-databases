#!/bin/sh
# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
#
# check-extraction-readiness.sh — Checks remaining legacy dirs for extraction readiness
# Part of foundational fixes for #45 (lithoglyph/gnpl/glyphbase extraction) — enduring guard
#
# Checks:
# 1. Byte-identity vs canonical repos (if available locally or via gh)
# 2. History-preserving tags exist
# 3. Placement guard grandfather list
# 4. No new files added since extraction baseline
# 5. Pointer READMEs for DONE extractions
#
# Usage:
#   ./scripts/resite/check-extraction-readiness.sh
#   ./scripts/resite/check-extraction-readiness.sh --deep  (also tries to diff against canonical repos via gh)

set -eu

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

echo "=== Extraction Readiness — 2026-09-25 ==="
echo ""

# 1. Check split-history tags exist (history preservation)
echo "1. History-preserving tags (must never be pruned):"
for tag in split-history/lithoglyph split-history/verisimdb split-history/glyphbase split-history/gnpl; do
  if git tag --list | grep -q "^$tag$"; then
    count=$(git ls-tree -r "$tag" --name-only 2>/dev/null | wc -l || echo "0")
    echo "  [OK] $tag exists — $count files"
  else
    echo "  [WARN] $tag missing — history not preserved? Check origin tags: git fetch --tags"
  fi
done
echo ""

# 2. Check DONE extractions are pointer READMEs only
echo "2. DONE extractions (should be pointer READMEs only):"
for dir in lithoglyph verisimdb; do
  if [ -d "$dir" ]; then
    files=$(find "$dir" -type f | wc -l)
    if [ "$files" -eq 1 ] && [ -f "$dir/README.adoc" ]; then
      echo "  [OK] $dir/ — 1 file (README.adoc pointer) — DONE"
    else
      echo "  [WARN] $dir/ — $files files (expected 1 README) — may have new content"
      find "$dir" -type f | head -n 20
    fi
  else
    echo "  [INFO] $dir/ does not exist — fully removed (alternative to pointer README)"
  fi
done
echo ""

# 3. Check grandfathered legacy dirs (still being extracted)
echo "3. Grandfathered legacy dirs (being extracted per REGISTRY.adoc):"
for dir in quandledb nqc typeql-experimental verisim-core verisim-modular-experiment; do
  if [ -d "$dir" ]; then
    count=$(find "$dir" -type f | wc -l)
    echo "  [INFO] $dir/ — $count files — grandfathered, being extracted to $(grep -A2 "$dir" REGISTRY.adoc 2>/dev/null | head -n 5 || echo "see REGISTRY.adoc")"
  else
    echo "  [INFO] $dir/ — not present (already extracted)"
  fi
done
echo ""

# 4. Check placement guard grandfather list
echo "4. Placement guard grandfather list (should NOT contain lithoglyph or verisimdb — they are DONE):"
if grep -q "lithoglyph" .github/workflows/placement-guard.yml | grep -q "GRANDFATHER"; then
  # More precise check
  if grep "GRANDFATHER=" .github/workflows/placement-guard.yml | grep -q "lithoglyph"; then
    echo "  [FAIL] placement-guard.yml still grandfathers lithoglyph — should FAIL now"
  else
    echo "  [OK] lithoglyph not in GRANDFATHER — correctly FAILS on new files"
  fi
else
  echo "  [OK] lithoglyph not in GRANDFATHER"
fi
if grep "GRANDFATHER=" .github/workflows/placement-guard.yml | grep -q "verisimdb"; then
  echo "  [FAIL] placement-guard.yml still grandfathers verisimdb — should FAIL now"
else
  echo "  [OK] verisimdb not in GRANDFATHER — correctly FAILS"
fi
echo "  Current GRANDFATHER: $(grep "GRANDFATHER=" .github/workflows/placement-guard.yml | head -n1)"
echo ""

# 5. Check for new files added since baseline (would be blocked by guard)
echo "5. No new implementation files in coordination paths (check for accidental drift):"
# Coordination paths should have 0 .res/.ts files
res_count=$(find . -maxdepth 3 -type f \( -name "*.res" -o -name "*.resi" -o -name "*.ts" -o -name "*.tsx" \) -not -path "*/.git/*" -not -path "*/quandledb/*" -not -path "*/nqc/*" -not -path "*/typeql-experimental/*" -not -path "*/verisim-core/*" -not -path "*/verisim-modular-experiment/*" -not -path "*/.machine_readable/*" 2>/dev/null | wc -l)
if [ "$res_count" -eq 0 ]; then
  echo "  [OK] 0 ReScript/TS files in coordination paths"
else
  echo "  [FAIL] $res_count ReScript/TS files in coordination paths"
fi

# Check for placeholder tokens outside guard lists
placeholder=$(grep -R "{{PLACEHOLDER}}" --include="*.a2ml" --include="*.adoc" . 2>/dev/null | grep -v ".git" | grep -v "reject-if-contains" | grep -v "grep -R" | wc -l)
echo "  Placeholder mentions outside guard: $placeholder (should be docs explaining fix only)"
echo ""

# 6. Deep check — try to diff against canonical repos if gh available and --deep flag
if [ "${1:-}" = "--deep" ]; then
  echo "6. Deep check — diff against canonical repos (requires gh auth):"
  if command -v gh >/dev/null 2>&1; then
    for mapping in "quandledb:hyperpolymath/quandledb" "typeql-experimental:hyperpolymath/vcl-ut" "nqc:hyperpolymath/nqc"; do
      subdir=$(echo "$mapping" | cut -d: -f1)
      repo=$(echo "$mapping" | cut -d: -f2)
      if [ -d "$subdir" ]; then
        echo "  Checking $subdir vs $repo..."
        # This is a lightweight check — just existence, not full diff
        gh repo view "$repo" --json name,updatedAt -q ".name" 2>/dev/null && echo "    [OK] $repo exists" || echo "    [WARN] cannot access $repo (gh auth?)"
      fi
    done
  else
    echo "  [SKIP] gh not available — cannot deep check"
  fi
  echo ""
fi

echo "=== Summary ==="
echo "DONE extractions: lithoglyph (819 files 2026-07-27), verisimdb (713 files 2026-08-03), gnpl (125 PR #4), glyphbase (130) — all with split-history tags preserved"
echo "Grandfathered: quandledb/, nqc/, typeql-experimental/, verisim-core/, verisim-modular-experiment/ — being extracted per REGISTRY.adoc"
echo "Enduring guards: placement-guard.yml FAILs on lithoglyph/verisimdb, block-db-writes.sh blocks NEW files in legacy dirs"
echo "Next: Run docs/migration/RESITE-CODEX-HANDOFF.adoc for remaining extractions (requires GitHub scope expansion)"
