#!/usr/bin/env bash
# SPDX-License-Identifier: PMPL-1.0-or-later
# Setup script for NQC Web UI — creates symlinks for local ReScript packages
# that the ReScript compiler resolves via node_modules.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "==> Installing npm dependencies via Deno..."
deno install

echo "==> Linking local ReScript packages into node_modules..."

# rescript-tea (TEA framework)
TEA_PKG="../../developer-ecosystem/rescript-ecosystem/packages/web/tea"
mkdir -p node_modules
ln -sfn "$(realpath "$TEA_PKG")" node_modules/rescript-tea

# cadre-router (URL routing)
ROUTER_PKG="../../developer-ecosystem/rescript-ecosystem/cadre-router"
mkdir -p node_modules/@anthropics
ln -sfn "$(realpath "$ROUTER_PKG")" node_modules/@anthropics/cadre-router

# Stub transitive dependencies that rescript-tea and cadre-router declare
# but whose code is not needed at compile-time for our app.

# @proven/rescript-bindings (transitive dep of rescript-tea)
PROVEN_DIR="node_modules/@proven/rescript-bindings"
if [ ! -d "$PROVEN_DIR" ]; then
  mkdir -p "$PROVEN_DIR/src"
  cat > "$PROVEN_DIR/rescript.json" <<'RJSON'
{"name": "@proven/rescript-bindings", "sources": [{"dir": "src"}], "suffix": ".res.mjs"}
RJSON
fi

# rescript-wasm-runtime (transitive dep of cadre-router)
WASM_DIR="node_modules/rescript-wasm-runtime"
if [ ! -d "$WASM_DIR" ]; then
  mkdir -p "$WASM_DIR/src"
  cat > "$WASM_DIR/rescript.json" <<'RJSON'
{"name": "rescript-wasm-runtime", "sources": [{"dir": "src"}], "suffix": ".res.mjs"}
RJSON
fi

echo "==> Making launcher executable..."
chmod +x "$SCRIPT_DIR/nqc-launcher.sh"

echo "==> Building ReScript..."
if node_modules/.bin/rescript-legacy.exe 2>&1; then
  echo ""
  echo "==> Build successful!"
else
  echo ""
  echo "==> Build had issues (see above). You may need to fix errors before running."
fi

# ---- First-build desktop shortcut offer ----
# Only ask on first setup (marker file tracks this)
MARKER="$SCRIPT_DIR/.setup-complete"
if [ ! -f "$MARKER" ]; then
  echo ""
  echo "======================================================"
  echo "  Would you like to install a desktop shortcut?"
  echo "  This adds an 'NQC Query Client' icon to your Desktop"
  echo "  that launches the web UI with one click."
  echo "======================================================"
  echo ""
  read -rp "Install desktop shortcut? [Y/n] " answer
  answer="${answer:-Y}"
  if [[ "$answer" =~ ^[Yy] ]]; then
    DESKTOP_DIR="${HOME}/Desktop"
    if [ -d "$DESKTOP_DIR" ]; then
      cp "$SCRIPT_DIR/nqc-web.desktop" "$DESKTOP_DIR/nqc-web.desktop"
      chmod +x "$DESKTOP_DIR/nqc-web.desktop"
      # Mark as trusted on GNOME so it doesn't show "untrusted" warning
      if command -v gio &> /dev/null; then
        gio set "$DESKTOP_DIR/nqc-web.desktop" metadata::trusted true 2>/dev/null || true
      fi
      echo "==> Desktop shortcut installed at $DESKTOP_DIR/nqc-web.desktop"
    else
      echo "==> Desktop directory not found at $DESKTOP_DIR — skipping."
      echo "    You can manually copy nqc-web.desktop to your Desktop."
    fi
  else
    echo "==> Skipped. You can install it later:"
    echo "    cp nqc-web.desktop ~/Desktop/ && chmod +x ~/Desktop/nqc-web.desktop"
  fi
  # Mark setup as complete so we don't ask again
  touch "$MARKER"
fi

echo ""
echo "==> All done! To launch NQC Web UI:"
echo "    bash nqc-launcher.sh"
echo ""
echo "    Or use the desktop shortcut if you installed one."
