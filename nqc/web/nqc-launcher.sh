#!/usr/bin/env bash
# SPDX-License-Identifier: PMPL-1.0-or-later
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath)
#
# NQC Web UI Launcher
# -------------------
# Starts the CORS proxy, the dev server, and opens the browser.
# Designed to be invoked from the desktop shortcut or directly.
#
# What it does:
#   1. Starts the CORS proxy on :4000 (forwards to database engines)
#   2. Starts the static file server on :8000 (serves the web UI)
#   3. Waits briefly for servers to be ready
#   4. Opens the default browser to http://localhost:8000
#   5. On exit (Ctrl+C or window close), cleans up both servers
#
# Usage:
#   ./nqc-launcher.sh          # Normal launch
#   ./nqc-launcher.sh --term   # Stay in terminal (don't open browser)

set -euo pipefail

# Resolve the web/ directory regardless of where the script is called from
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colour output helpers
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No colour

# Make this window visually distinct from normal terminals.
set_launcher_terminal_identity() {
  # Window title
  printf '\033]0;NQC Web UI Launcher\007'
  # Hint a distinct background/cursor colour (supported on many terminals, ignored on others).
  printf '\033]11;#1D2433\007'
  printf '\033]12;#7FDBFF\007'
}

set_launcher_terminal_identity

echo -e "${BLUE}╔══════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  ${GREEN}NQC — NextGen Query Client${BLUE}         ║${NC}"
echo -e "${BLUE}║  ${NC}Web UI Launcher${BLUE}                    ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════╝${NC}"
echo ""

TEA_PKG="../../../developer-ecosystem/rescript-ecosystem/packages/web/tea"
ROUTER_PKG="../../../developer-ecosystem/rescript-ecosystem/cadre-router"

ensure_local_package_link() {
  local src="$1"
  local dst="$2"
  local label="$3"

  if [ ! -d "$src" ]; then
    echo -e "${YELLOW}Missing ${label} at:${NC} $src"
    echo -e "${YELLOW}Run: bash setup.sh${NC}"
    exit 1
  fi

  mkdir -p "$(dirname "$dst")"
  ln -sfn "$(realpath "$src")" "$dst"
}

ensure_rescript_core_suffix_compat() {
  local core_src="node_modules/@rescript/core/src"

  if [ ! -d "$core_src" ]; then
    return
  fi

  while IFS= read -r file; do
    local compat="${file%.mjs}.res.mjs"
    if [ ! -e "$compat" ]; then
      ln -s "$(basename "$file")" "$compat"
    fi
  done < <(find "$core_src" -maxdepth 1 -type f -name "*.mjs")
}

ensure_deno_package_link() {
  local pattern="$1"
  local dst="$2"
  local label="$3"
  local src

  src="$(find node_modules/.deno -maxdepth 6 -type d -path "$pattern" | head -n 1)"

  if [ -z "$src" ]; then
    echo -e "${YELLOW}Missing ${label} in node_modules/.deno${NC}"
    echo -e "${YELLOW}Run: deno install${NC}"
    exit 1
  fi

  mkdir -p "$(dirname "$dst")"
  ln -sfn "$(realpath "$src")" "$dst"
}

rewrite_browser_imports() {
  while IFS= read -r -d '' file; do
    sed -i -E \
      -e 's|"react-dom/client"|"/vendor/esm/react-dom-client.mjs"|g' \
      -e 's|"/node_modules/react-dom/client.js"|"/vendor/esm/react-dom-client.mjs"|g' \
      -e 's|"https://esm.sh/react-dom@19.2.4/client"|"/vendor/esm/react-dom-client.mjs"|g' \
      -e 's|"react/jsx-runtime"|"/vendor/esm/react-jsx-runtime.mjs"|g' \
      -e 's|"/node_modules/react/jsx-runtime.js"|"/vendor/esm/react-jsx-runtime.mjs"|g' \
      -e 's|"https://esm.sh/react@19.2.4/jsx-runtime"|"/vendor/esm/react-jsx-runtime.mjs"|g' \
      -e 's|"rescript-tea/([^"]+)"|"/node_modules/rescript-tea/\1"|g' \
      -e 's|"@anthropics/cadre-router/([^"]+)"|"/node_modules/@anthropics/cadre-router/\1"|g' \
      -e 's|"@rescript/core/([^"]+)"|"/node_modules/@rescript/core/\1"|g' \
      "$file"
  done < <(find src -type f -name "*.res.mjs" -print0)
}

rewrite_dependency_imports() {
  local roots=(
    "node_modules/rescript-tea/src"
    "node_modules/@anthropics/cadre-router/src/tea"
    "node_modules/@rescript/core/src"
  )

  local root
  for root in "${roots[@]}"; do
    [ -d "$root" ] || continue

    while IFS= read -r -d '' file; do
      sed -i -E \
        -e 's|"react"|"/vendor/esm/react.mjs"|g' \
        -e 's|"react/jsx-runtime"|"/vendor/esm/react-jsx-runtime.mjs"|g' \
        -e 's|"react-dom/client"|"/vendor/esm/react-dom-client.mjs"|g' \
        -e 's|"rescript/lib/es6/belt_([^"]+)"|"/node_modules/@rescript/runtime/lib/es6/Belt_\1"|g' \
        -e 's|"rescript/lib/es6/js_([^"]+)"|"/node_modules/@rescript/runtime/lib/es6/Js_\1"|g' \
        -e 's|"rescript/lib/es6/caml_option.js"|"/node_modules/@rescript/runtime/lib/es6/Primitive_option.js"|g' \
        -e 's|"rescript/lib/es6/caml_js_exceptions.js"|"/node_modules/@rescript/runtime/lib/es6/Primitive_exceptions.js"|g' \
        -e 's|"/node_modules/rescript/lib/es6/belt_([^"]+)"|"/node_modules/@rescript/runtime/lib/es6/Belt_\1"|g' \
        -e 's|"/node_modules/rescript/lib/es6/js_([^"]+)"|"/node_modules/@rescript/runtime/lib/es6/Js_\1"|g' \
        -e 's|"/node_modules/rescript/lib/es6/caml_option.js"|"/node_modules/@rescript/runtime/lib/es6/Primitive_option.js"|g' \
        -e 's|"/node_modules/rescript/lib/es6/caml_js_exceptions.js"|"/node_modules/@rescript/runtime/lib/es6/Primitive_exceptions.js"|g' \
        -e 's|"rescript/lib/es6/([^"]+)"|"/node_modules/rescript/lib/es6/\1"|g' \
        -e 's|"@rescript/core/([^"]+)"|"/node_modules/@rescript/core/\1"|g' \
        -e 's|"@rescript/runtime/([^"]+)"|"/node_modules/@rescript/runtime/\1"|g' \
        "$file"
    done < <(find "$root" -type f -name "*.mjs" -print0)
  done
}

# Ensure local ReScript packages are linked for browser import-map resolution.
ensure_local_package_link "$TEA_PKG" "node_modules/rescript-tea" "rescript-tea"
ensure_local_package_link "$ROUTER_PKG" "node_modules/@anthropics/cadre-router" "@anthropics/cadre-router"
ensure_deno_package_link "*/node_modules/rescript" "node_modules/rescript" "rescript"
ensure_deno_package_link "*/node_modules/@rescript/runtime" "node_modules/@rescript/runtime" "@rescript/runtime"
ensure_rescript_core_suffix_compat
rewrite_browser_imports
rewrite_dependency_imports

# Check if ReScript has been built
if [ ! -f "src/Index.res.mjs" ]; then
  echo -e "${YELLOW}ReScript not compiled yet. Running first build...${NC}"
  if command -v deno &> /dev/null; then
    deno task build 2>&1 || {
      echo -e "${YELLOW}Build failed. Run 'bash setup.sh' first, then 'deno task build'.${NC}"
      echo "Press Enter to exit..."
      read -r
      exit 1
    }
  else
    echo "Deno not found. Install Deno first: https://deno.land"
    echo "Press Enter to exit..."
    read -r
    exit 1
  fi
fi

# Trap to clean up background processes on exit
PROXY_PID=""
SERVER_PID=""
CLEANED_UP=0
cleanup() {
  if [ "$CLEANED_UP" -eq 1 ]; then
    return
  fi
  CLEANED_UP=1
  echo ""
  echo -e "${BLUE}Shutting down NQC servers...${NC}"
  [ -n "$PROXY_PID" ] && kill "$PROXY_PID" 2>/dev/null || true
  [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null || true
  echo -e "${GREEN}Done.${NC}"
}
trap cleanup EXIT INT TERM

# Start CORS proxy in background
echo -e "${GREEN}Starting CORS proxy on :4000...${NC}"
deno run --allow-net --allow-env proxy/server.js &
PROXY_PID=$!

# Start dev server in background
echo -e "${GREEN}Starting web server on :8000...${NC}"
deno run --allow-net --allow-read serve.js &
SERVER_PID=$!

# Wait for servers to start
sleep 1

# Open browser unless --term flag was passed
if [[ "${1:-}" != "--term" ]]; then
  echo -e "${GREEN}Opening browser...${NC}"
  if command -v xdg-open &> /dev/null; then
    xdg-open "http://localhost:8000" 2>/dev/null &
  elif command -v open &> /dev/null; then
    open "http://localhost:8000" 2>/dev/null &
  fi
fi

echo ""
echo -e "${GREEN}NQC Web UI is running:${NC}"
echo -e "  Web UI:     ${BLUE}http://localhost:8000${NC}"
echo -e "  CORS Proxy: ${BLUE}http://localhost:4000${NC}"
echo ""
echo -e "  Database engines expected at:"
echo -e "    VeriSimDB (VQL): ${BLUE}http://localhost:8080${NC}"
echo -e "    Lithoglyph (GQL): ${BLUE}http://localhost:8081${NC}"
echo -e "    QuandleDB (KQL): ${BLUE}http://localhost:8082${NC}"
echo ""
echo -e "${YELLOW}Press Ctrl+C to stop.${NC}"
echo ""

# Wait for either server to exit (keeps the script alive)
wait
