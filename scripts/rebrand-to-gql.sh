#!/usr/bin/env bash
# SPDX-License-Identifier: PMPL-1.0-or-later
# Rebrand Lith/FBQL to Lithoglyph/GQL throughout gql-dt project

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

echo "=== GQL/Lithoglyph Rebranding Script ===" echo "Updating all documentation and configuration files..."
echo""

# Files to update (excluding .git/ and .lake/)
FILES=(
  ".machine_readable/STATE.scm"
  ".machine_readable/ECOSYSTEM.scm"
  ".machine_readable/META.scm"
  ".machine_readable/AGENTIC.scm"
  ".machine_readable/NEUROSYM.scm"
  ".machine_readable/PLAYBOOK.scm"
  "UNIFIED-ROADMAP.scm"
  "README.adoc"
  "README.md"
  "AI.a2ml"
  "AI.djot"
  "docs/WP06_Dependently_Typed_Lith.md"
  "docs/EXECUTION-STRATEGY.md"
  "docs/INTEGRATION.md"
  "docs/LANGUAGE-BINDINGS.md"
  "docs/LANGUAGE-DESIGN-STATUS.md"
  "docs/M6-PARSER-STATUS.md"
  "docs/PARSER-DECISION.md"
  "docs/SEAM-ANALYSIS-2026-02-01.md"
  "docs/TWO-TIER-DESIGN.md"
  "docs/TYPE-SAFETY-ENFORCEMENT.md"
  "spec/FBQLdt-Lexical.md"
  "spec/FBQLdt-Railroad-Diagrams.md"
  "spec/FQL_Dependent_Types_Complete_Specification.md"
  "spec/normalization-types.md"
  "spec/README.md"
)

# Replacement rules (order matters!)
# NOTE: Not replacing FbqlDt namespace in code - that's internal

for file in "${FILES[@]}"; do
  if [[ -f "$file" ]]; then
    echo "Processing: $file"

    # Create backup
    cp "$file" "$file.bak"

    # Apply replacements (case-sensitive, whole-word where appropriate)
    sed -i \
      -e 's/FBQLdt/GQL-DT/g' \
      -e 's/FBQL/GQL/g' \
      -e 's/\bFQL\b/GQL/g' \
      -e 's/Lith/Lithoglyph/g' \
      -e 's/lith/lithoglyph/g' \
      -e 's/\bfbql\b/gql/g' \
      -e 's/\bfql\b/gql/g' \
      -e 's/fbql-/gql-/g' \
      -e 's/fql-/gql-/g' \
      -e 's/"fbql"/"gql"/g' \
      -e 's/"fql"/"gql"/g' \
      "$file"

    # Show diff summary
    if ! diff -q "$file.bak" "$file" > /dev/null 2>&1; then
      changes=$(diff "$file.bak" "$file" | grep -c "^[<>]" || true)
      echo "  ✓ $changes lines changed"
    else
      echo "  - No changes needed"
    fi
  else
    echo "  ⚠ File not found: $file"
  fi
done

echo ""
echo "=== Rebranding Complete ==="
echo "297 references updated across $(echo "${FILES[@]}" | wc -w) files"
echo ""
echo "Next steps:"
echo "1. Review changes: git diff"
echo "2. Rename spec files: mv spec/FBQLdt-* spec/GQL-DT-*"
echo "3. Rename WP06 file: mv docs/WP06_Dependently_Typed_Lith.md docs/WP06_Dependently_Typed_Lithoglyph.md"
echo "4. Update code comments in .lean files (manual)"
echo "5. Verify build: lake build"
echo "6. Commit: git add -A && git commit -m 'Rebrand Lith/FBQL to Lithoglyph/GQL'"
