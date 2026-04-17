#!/usr/bin/env bash
# SPDX-License-Identifier: PMPL-1.0-or-later
# Enhanced NQC Launcher with TUI/CLI support and cross-launcher integration

set -euo pipefail

# Source the original launcher to maintain all existing functionality
source "/var/mnt/eclipse/repos/developer-ecosystem/nextgen-databases/nqc/nqc-launcher.sh"

# Enhanced functions
run_tui() {
    log "TUI mode not yet implemented for NQC"
    log "Falling back to web UI"
    
    # Add self-healing check
    if ! command -v deno >/dev/null 2>&1; then
        err "Deno is required for NQC but not found"
        err "Please install Deno first: https://deno.land"
        return 1
    fi
    
    start_server
}

run_cli() {
    log "CLI mode not yet implemented for NQC"
    log "Available CLI tools:"
    log "  - invariant-path: Claim path analysis"
    log "  - Use: invariant-path-launcher --auto"
    
    # Launch invariant-path as a fallback
    if command -v /var/mnt/eclipse/repos/.desktop-tools/invariant-path-launcher.sh >/dev/null 2>&1; then
        /var/mnt/eclipse/repos/.desktop-tools/invariant-path-launcher.sh --auto
    else
        err "invariant-path not found"
    fi
}

launch_invariant_path() {
    local ip_launcher="/var/mnt/eclipse/repos/.desktop-tools/invariant-path-launcher.sh"
    
    # Self-healing: check if invariant-path exists
    if [[ ! -f "$ip_launcher" ]]; then
        err "invariant-path launcher not found at $ip_launcher"
        err "Trying alternative location..."
        ip_launcher="/var/mnt/eclipse/repos/verification-ecosystem/invariant-path/invariant-path-launcher"
    fi
    
    if [[ -f "$ip_launcher" ]]; then
        log "Launching Invariant Path from $ip_launcher"
        "$ip_launcher" "$@"
    else
        err "invariant-path not found in any known location"
        err "Please install invariant-path first"
        return 1
    fi
}

show_enhanced_help() {
    cat <<EOF
$APP_DISPLAY Enhanced Launcher — $APP_DESC

Usage: $0 [MODE] [--force]

Runtime modes (original):
  --start      Start the process (default)
  --stop       Stop the process
  --status     Show running status
  --auto       Alias for --start
  --integ      Install desktop entry + shortcut + icon
  --disinteg   Remove everything --integ installed

Enhanced modes:
  --tui        Launch TUI interface (experimental)
  --cli        Launch CLI interface (falls back to invariant-path)
  --invariant-path [args]  Launch invariant-path with args
  --help       This enhanced help

Cross-launcher integration:
  --invariant-path-scan [repo] [profile]  Run invariant-path scan
  --invariant-path-status                Show invariant-path status
  --invariant-path-open                  Open last scan output

Examples:
  $0 --tui                              # Launch TUI (experimental)
  $0 --cli                              # Launch CLI mode
  $0 --invariant-path --scan . generic  # Scan current directory
  $0 --invariant-path --status          # Show invariant-path status

Detected platform: $PLATFORM
Runtime kind:      $RUNTIME_KIND
Repo:              $REPO_DIR
EOF
}

# Enhanced main switch
ENHANCED_MODE="${1:-}"

case "$ENHANCED_MODE" in
    --tui)
        run_tui
        ;;
    --cli)
        run_cli
        ;;
    --invariant-path)
        shift
        launch_invariant_path "$@"
        ;;
    --invariant-path-scan)
        shift
        launch_invariant_path --scan "$@"
        ;;
    --invariant-path-status)
        launch_invariant_path --status
        ;;
    --invariant-path-open)
        launch_invariant_path --open-output
        ;;
    --help|-h)
        show_enhanced_help
        ;;
    *)
        # Fall back to original launcher logic
        MODE="${ENHANCED_MODE:---auto}"
        case "$MODE" in
            --start)          start_server ;;
            --stop)           stop_server ;;
            --status)         
                if is_running; then
                    log "Running (PID $(cat "$PID_FILE"))${URL:+ — $URL}"
                else
                    log "Not running${URL:+ — $URL}"
                fi
                ;;
            --browser|--web)
                log "$APP_DISPLAY has no URL — --browser is not applicable"
                ;;
            --auto)
                start_server
                ;;
            --integ)          do_integ ;;
            --disinteg)       do_disinteg ;;
            --help|-h)        show_help ;;
            *)
                err "Unknown mode: $MODE"
                show_help
                exit 2
                ;;
        esac
        ;;
esac