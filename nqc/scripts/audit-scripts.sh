#!/usr/bin/env bash
# SPDX-License-Identifier: PMPL-1.0-or-later
# Simple script auditor for NQC - inspired by git-scripts

set -euo pipefail

echo "🔍 NQC Script Auditor"
echo "======================"
echo ""

SCRIPT_DIR="${1:-.}"

if [[ ! -d "$SCRIPT_DIR" ]]; then
    echo "❌ Directory not found: $SCRIPT_DIR"
    exit 1
fi

echo "Auditing scripts in: $SCRIPT_DIR"
echo ""

# Find all executable scripts
SCRIPTS=$(find "$SCRIPT_DIR" -type f -executable -name "*.sh" -o -name "*.js" -o -name "*.ts" 2>/dev/null || true)

if [[ -z "$SCRIPTS" ]]; then
    echo "✅ No scripts found to audit"
    exit 0
fi

echo "Found $(echo "$SCRIPTS" | wc -l) scripts to audit:"
echo ""

ISSUES_FOUND=0

for script in $SCRIPTS; do
    echo "📄 Checking: $script"
    
    # Check for shebang
    if [[ ! $(head -1 "$script" 2>/dev/null) =~ ^#! ]]; then
        echo "  ⚠️  Missing shebang"
        ((ISSUES_FOUND++))
    fi
    
    # Check for common issues
    if grep -q "set -e" "$script" 2>/dev/null; then
        echo "  ✅ Has error handling (set -e)"
    else
        echo "  ⚠️  Missing error handling (set -e)"
        ((ISSUES_FOUND++))
    fi
    
    if grep -q "SPDX-License-Identifier" "$script" 2>/dev/null; then
        echo "  ✅ Has license header"
    else
        echo "  ⚠️  Missing license header"
        ((ISSUES_FOUND++))
    fi
    
    echo ""
done

echo "======================"
echo "Audit complete"
echo "Issues found: $ISSUES_FOUND"

if [[ $ISSUES_FOUND -gt 0 ]]; then
    echo "⚠️  Some issues were found. Consider fixing them."
    exit 1
else
    echo "✅ All scripts passed basic audit"
    exit 0
fi