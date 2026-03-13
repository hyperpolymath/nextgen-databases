#!/usr/bin/env bash
# SPDX-License-Identifier: PMPL-1.0-or-later
# SPDX-FileCopyrightText: 2026 hyperpolymath
#
# Generate railroad diagrams from EBNF grammar

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
SPEC_DIR="$REPO_ROOT/spec"
DIAGRAMS_DIR="$SPEC_DIR/diagrams"

# Create diagrams directory
mkdir -p "$DIAGRAMS_DIR"

echo "=== FBQLdt Railroad Diagram Generator ==="
echo ""
echo "This script generates SVG railroad diagrams from the EBNF grammar."
echo ""
echo "Options:"
echo "  1. Online generator (recommended)"
echo "  2. CLI tool (requires railroad-diagrams npm package)"
echo ""

generate_online() {
    echo "📊 Online Generation Instructions:"
    echo ""
    echo "1. Visit: https://www.bottlecaps.de/rr/ui"
    echo ""
    echo "2. Paste the following EBNF snippets and click 'View Diagram':"
    echo ""
    echo "   CREATE COLLECTION:"
    cat <<'EOF'
CreateCollection ::= 'CREATE' 'COLLECTION' ('IF' 'NOT' 'EXISTS')?
                     Identifier
                     '(' ColumnList ')'
                     CollectionOptions?

ColumnList ::= ColumnDef (',' ColumnDef)*

ColumnDef ::= Identifier ':' TypeExpr

CollectionOptions ::= 'WITH' OptionList

OptionList ::= Option (',' Option)*

Option ::= 'DEPENDENT_TYPES'
         | 'PROVENANCE_TRACKING'
         | 'TARGET_NORMAL_FORM' NormalForm
EOF
    echo ""
    echo "3. Download as SVG and save to: $DIAGRAMS_DIR/create-collection.svg"
    echo ""
    echo "4. Repeat for other constructs in spec/FBQLdt-Railroad-Diagrams.md"
}

generate_cli() {
    if ! command -v rr &> /dev/null; then
        echo "❌ Error: 'rr' command not found"
        echo ""
        echo "Install railroad-diagrams:"
        echo "  npm install -g railroad-diagrams"
        echo ""
        exit 1
    fi

    echo "🔧 Generating diagrams with CLI tool..."

    # Extract CREATE COLLECTION grammar
    cat > "$DIAGRAMS_DIR/create-collection.ebnf" <<'EOF'
CreateCollection ::= 'CREATE' 'COLLECTION' ('IF' 'NOT' 'EXISTS')?
                     Identifier
                     '(' ColumnList ')'
                     CollectionOptions?
ColumnList ::= ColumnDef (',' ColumnDef)*
ColumnDef ::= Identifier ':' TypeExpr
CollectionOptions ::= 'WITH' OptionList
OptionList ::= Option (',' Option)*
Option ::= 'DEPENDENT_TYPES' | 'PROVENANCE_TRACKING' | 'TARGET_NORMAL_FORM' NormalForm
EOF

    # Generate SVG
    rr < "$DIAGRAMS_DIR/create-collection.ebnf" > "$DIAGRAMS_DIR/create-collection.html"

    echo "✅ Generated: $DIAGRAMS_DIR/create-collection.html"
    echo ""
    echo "Note: You may need to manually convert HTML to SVG"
}

# Main menu
read -p "Choose option (1 or 2): " choice

case $choice in
    1)
        generate_online
        ;;
    2)
        generate_cli
        ;;
    *)
        echo "Invalid option"
        exit 1
        ;;
esac

echo ""
echo "📁 Diagrams should be saved to: $DIAGRAMS_DIR/"
echo ""
echo "Expected files:"
echo "  - create-collection.svg"
echo "  - insert-statement.svg"
echo "  - select-statement.svg"
echo "  - type-expressions.svg"
echo "  - proof-clauses.svg"
echo "  - update-statement.svg"
echo "  - normalization-commands.svg"
echo ""
echo "See spec/FBQLdt-Railroad-Diagrams.md for all EBNF snippets"
