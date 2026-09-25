#!/bin/sh
# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
#
# pointer-readmes.sh — Verify DONE extractions are pointer READMEs only
# Part of extraction readiness for #45

set -eu

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

echo "=== Pointer READMEs Check ==="

# DONE extractions should be 1 file (README.adoc) only
for dir in lithoglyph verisimdb; do
  if [ -d "$ROOT/$dir" ]; then
    count=$(find "$ROOT/$dir" -type f | wc -l)
    if [ "$count" -eq 1 ] && [ -f "$ROOT/$dir/README.adoc" ]; then
      echo "[OK] $dir/ — 1 file (README.adoc) — DONE extraction"
    else
      echo "[WARN] $dir/ — $count files (expected 1 README) — may have drift"
      find "$ROOT/$dir" -type f | head -n 20
    fi
  else
    echo "[INFO] $dir/ not present — fully removed"
  fi
done

# Grandfathered should still exist but be documented
echo ""
echo "Grandfathered legacy dirs (should be in GRANDFATHER list):"
for dir in quandledb nqc typeql-experimental verisim-core verisim-modular-experiment; do
  if [ -d "$ROOT/$dir" ]; then
    count=$(find "$ROOT/$dir" -type f | wc -l)
    echo "[INFO] $dir/ — $count files — grandfathered"
  fi
done

echo ""
echo "Checking placement-guard GRANDFATHER does NOT contain DONE extractions:"
if grep "GRANDFATHER=" "$ROOT/.github/workflows/placement-guard.yml" | grep -q "lithoglyph"; then
  echo "[FAIL] lithoglyph still in GRANDFATHER — should FAIL now"
  exit 1
else
  echo "[OK] lithoglyph not in GRANDFATHER"
fi

if grep "GRANDFATHER=" "$ROOT/.github/workflows/placement-guard.yml" | grep -q "verisimdb"; then
  echo "[FAIL] verisimdb still in GRANDFATHER"
  exit 1
else
  echo "[OK] verisimdb not in GRANDFATHER"
fi

echo ""
echo "Pointer READMEs check PASS"
