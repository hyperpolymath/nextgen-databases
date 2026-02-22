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

echo -e "${BLUE}╔══════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  ${GREEN}NQC — NextGen Query Client${BLUE}         ║${NC}"
echo -e "${BLUE}║  ${NC}Web UI Launcher${BLUE}                    ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════╝${NC}"
echo ""

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
cleanup() {
  echo ""
  echo -e "${BLUE}Shutting down NQC servers...${NC}"
  [ -n "$PROXY_PID" ] && kill "$PROXY_PID" 2>/dev/null || true
  [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null || true
  echo -e "${GREEN}Done.${NC}"
}
trap cleanup EXIT INT TERM

# Start CORS proxy in background
echo -e "${GREEN}Starting CORS proxy on :4000...${NC}"
deno run --allow-net proxy/server.js &
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
