#!/usr/bin/env bash
# SPDX-License-Identifier: PMPL-1.0-or-later
# Comprehensive Glyphbase Rebrand Script
# Renames Lith/Lith → Lithoglyph throughout codebase

set -euo pipefail

echo "=== Glyphbase Comprehensive Rebrand Script ==="
echo "Lith/Lith → Lithoglyph"
echo "formbase → glyphbase (where needed)"
echo ""

# Count changes
TOTAL_FILES=0
TOTAL_CHANGES=0

# Function to rebrand a single file
rebrand_file() {
    local file="$1"
    if [ ! -f "$file" ]; then
        return
    fi

    # Skip backup files
    if [[ "$file" == *.bak ]]; then
        return
    fi

    # Create backup
    cp "$file" "$file.bak"

    # Count lines before
    local before=$(wc -l < "$file" 2>/dev/null || echo "0")

    # Perform replacements
    sed -i \
        -e 's/Lith/Lithoglyph/g' \
        -e 's/lith/lithoglyph/g' \
        -e 's/Lith/Lithoglyph/g' \
        -e 's/lith/lithoglyph/g' \
        -e 's/FormBase/Glyphbase/g' \
        -e 's/formbase/glyphbase/g' \
        -e 's/FORMBD/LITHOGLYPH/g' \
        -e 's/FORMDB/LITHOGLYPH/g' \
        "$file"

    # Check if file changed
    if ! diff -q "$file" "$file.bak" > /dev/null 2>&1; then
        local changed=$(diff "$file.bak" "$file" | grep -c '^[<>]' || echo "0")
        echo "✓ $file ($changed lines changed)"
        TOTAL_FILES=$((TOTAL_FILES + 1))
        TOTAL_CHANGES=$((TOTAL_CHANGES + changed))
    else
        # No changes, remove backup
        rm "$file.bak"
    fi
}

# Rebrand source files
echo "Rebranding Gleam source files..."
for file in server/src/**/*.gleam; do
    rebrand_file "$file"
done

# Rebrand Erlang NIF files
echo ""
echo "Rebranding Erlang NIF files..."
for file in server/src/*.erl server/native/src/*.erl server/*.erl; do
    rebrand_file "$file"
done

# Rebrand Zig FFI files
echo ""
echo "Rebranding Zig FFI files..."
for file in server/ffi/zig/src/*.zig server/ffi/zig/*.zig server/native/src/*.zig; do
    rebrand_file "$file"
done

# Rebrand Idris ABI files
echo ""
echo "Rebranding Idris ABI files..."
for file in server/src/abi/*.idr; do
    rebrand_file "$file"
done

# Rebrand Rust files
echo ""
echo "Rebranding Rust files..."
for file in server/native_rust/src/*.rs server/native_rust/*.toml; do
    rebrand_file "$file"
done

# Rebrand ReScript UI files
echo ""
echo "Rebranding ReScript UI files..."
for file in ui/src/**/*.res; do
    rebrand_file "$file"
done

# Rebrand documentation
echo ""
echo "Rebranding documentation..."
for file in *.md *.adoc docs/*.md docs/*.adoc server/*.md server/ffi/zig/*.md; do
    rebrand_file "$file"
done

# Rebrand test files
echo ""
echo "Rebranding test files..."
for file in server/test/*.gleam; do
    rebrand_file "$file"
done

# Rebrand build files
echo ""
echo "Rebranding build files..."
for file in justfile docker-compose.yml server/ffi/zig/build.zig server/native/build.zig server/native/Makefile; do
    rebrand_file "$file"
done

# Rebrand UI config files
echo ""
echo "Rebranding UI config files..."
for file in ui/package.json ui/rescript.json; do
    rebrand_file "$file"
done

# Rebrand CI workflows
echo ""
echo "Rebranding CI workflows..."
for file in .github/workflows/*.yml; do
    rebrand_file "$file"
done

echo ""
echo "=== File Renames Required ==="
echo "The following files should be renamed manually:"
echo ""

# Check for files that need renaming
if [ -f "server/src/formbase_server.gleam" ]; then
    echo "  server/src/formbase_server.gleam → server/src/glyphbase_server.gleam"
fi

if [ -f "server/src/lith.gleam" ]; then
    echo "  server/src/lith.gleam → server/src/lithoglyph.gleam"
fi

if [ -f "server/src/lith_nif.erl" ]; then
    echo "  server/src/lith_nif.erl → server/src/lithoglyph_nif.erl"
fi

if [ -f "server/src/lith_nif.erl" ]; then
    echo "  server/src/lith_nif.erl → server/src/lithoglyph_nif.erl.old"
fi

if [ -f "server/native/src/lith_nif.erl" ]; then
    echo "  server/native/src/lith_nif.erl → server/native/src/lithoglyph_nif.erl"
fi

if [ -f "server/native/src/lith_nif.zig" ]; then
    echo "  server/native/src/lith_nif.zig → server/native/src/lithoglyph_nif.zig"
fi

if [ -f "server/test_lith_nif.erl" ]; then
    echo "  server/test_lith_nif.erl → server/test_lithoglyph_nif.erl"
fi

if [ -f "FORMBD-INTEGRATION.md" ]; then
    echo "  FORMBD-INTEGRATION.md → LITHOGLYPH-INTEGRATION.md"
fi

if [ -d "server/src/lith" ]; then
    echo "  server/src/lith/ → server/src/lithoglyph/"
fi

echo ""
echo "=== Summary ==="
echo "Files modified: $TOTAL_FILES"
echo "Lines changed: $TOTAL_CHANGES"
echo ""
echo "Next steps:"
echo "1. Review changes with: git diff"
echo "2. Rename files listed above"
echo "3. Update import statements to use new names"
echo "4. Test build: cd server && gleam build"
echo "5. Commit changes: git commit -am 'feat: rebrand Lith/Lith to Lithoglyph'"
