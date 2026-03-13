#!/usr/bin/env bash
# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# bofig-ingest.sh — Batch ingest Docudactyl Cap'n Proto output into Lithoglyph
#
# Reads shard directories produced by Docudactyl, converts each .capnp
# StageResults file to a bofig_evidence JSON record via the Zig adapter,
# and POSTs to Lithoglyph's REST API. Deduplicates by SHA-256 hash.
#
# Usage:
#   ./bofig-ingest.sh <shard_dir> [options]
#
# Options:
#   -u, --url URL              Lithoglyph API base URL (default: https://localhost:8080)
#   -i, --investigation ID     Investigation ID (required)
#   -r, --run-id ID            Pipeline run ID (default: auto-generated)
#   -a, --adapter PATH         Path to lith_adapter binary (default: searches PATH)
#   -d, --dry-run              Print JSON records without POSTing
#   -v, --verbose              Verbose output
#   -h, --help                 Show this help
#
# Prerequisites:
#   - lith_adapter binary (built from docudactyl/ffi/zig/src/lith_adapter.zig)
#   - curl
#   - jq (optional, for pretty-printing in dry-run mode)

set -euo pipefail

# ── Defaults ─────────────────────────────────────────────────────────────

LITH_URL="${LITH_URL:-https://localhost:8080}"
INVESTIGATION_ID=""
RUN_ID=""
ADAPTER_BIN=""
DRY_RUN=false
VERBOSE=false
SHARD_DIR=""

# ── Counters ─────────────────────────────────────────────────────────────

COUNT_TOTAL=0
COUNT_SUCCESS=0
COUNT_SKIPPED=0
COUNT_FAILED=0
COUNT_DEDUP=0

# ── Functions ────────────────────────────────────────────────────────────

usage() {
    sed -n '2,/^$/{ s/^# //; s/^#//; p }' "$0"
    exit 0
}

log() {
    printf '[%s] %s\n' "$(date -Iseconds)" "$*" >&2
}

verbose() {
    if $VERBOSE; then
        log "$@"
    fi
}

die() {
    log "ERROR: $*"
    exit 1
}

# Check if a record with this SHA-256 already exists in Lithoglyph.
# Returns 0 if duplicate found (skip), 1 if new (proceed).
check_dedup() {
    local sha256="$1"
    if [ -z "$sha256" ]; then
        return 1 # No hash → cannot dedup, proceed with insert
    fi

    local query="SELECT sha256_hash FROM bofig_evidence WHERE sha256_hash = '${sha256}' LIMIT 1"
    local response
    response=$(curl -sf -X POST "${LITH_URL}/query" \
        -H "Content-Type: application/json" \
        -d "{\"gql\": \"${query}\"}" 2>/dev/null) || return 1

    # If the response contains a result row, the record already exists.
    if echo "$response" | grep -q '"sha256_hash"'; then
        return 0 # duplicate
    fi
    return 1 # new
}

# POST a JSON evidence record to Lithoglyph.
post_record() {
    local json_file="$1"
    local run_id="$2"

    local gql_body
    gql_body=$(cat <<ENDJSON
{
  "gql": "INSERT INTO bofig_evidence $(cat "$json_file")\nWITH PROVENANCE {\n  actor: \"docudactyl-pipeline\",\n  rationale: \"Batch extraction run ${run_id}\"\n}",
  "provenance": {
    "actor": "docudactyl-pipeline",
    "rationale": "Batch extraction run ${run_id}"
  }
}
ENDJSON
)

    local http_code
    http_code=$(curl -sf -o /dev/null -w '%{http_code}' -X POST "${LITH_URL}/query" \
        -H "Content-Type: application/json" \
        -d "$gql_body" 2>/dev/null) || http_code="000"

    if [ "$http_code" = "200" ] || [ "$http_code" = "201" ]; then
        return 0
    else
        verbose "POST failed with HTTP ${http_code}"
        return 1
    fi
}

# ── Argument Parsing ─────────────────────────────────────────────────────

while [ $# -gt 0 ]; do
    case "$1" in
        -u|--url)       LITH_URL="$2"; shift 2 ;;
        -i|--investigation) INVESTIGATION_ID="$2"; shift 2 ;;
        -r|--run-id)    RUN_ID="$2"; shift 2 ;;
        -a|--adapter)   ADAPTER_BIN="$2"; shift 2 ;;
        -d|--dry-run)   DRY_RUN=true; shift ;;
        -v|--verbose)   VERBOSE=true; shift ;;
        -h|--help)      usage ;;
        -*)             die "Unknown option: $1" ;;
        *)
            if [ -z "$SHARD_DIR" ]; then
                SHARD_DIR="$1"
            else
                die "Unexpected argument: $1"
            fi
            shift
            ;;
    esac
done

# ── Validation ───────────────────────────────────────────────────────────

[ -z "$SHARD_DIR" ] && die "Shard directory required. Usage: $0 <shard_dir> -i <investigation_id>"
[ -d "$SHARD_DIR" ] || die "Shard directory not found: $SHARD_DIR"
[ -z "$INVESTIGATION_ID" ] && die "Investigation ID required (-i/--investigation)"

if [ -z "$RUN_ID" ]; then
    RUN_ID="docudactyl-$(date +%Y%m%d-%H%M%S)-$$"
    log "Auto-generated run ID: $RUN_ID"
fi

# Locate the adapter binary.
if [ -z "$ADAPTER_BIN" ]; then
    ADAPTER_BIN=$(command -v lith_adapter 2>/dev/null || true)
    if [ -z "$ADAPTER_BIN" ]; then
        # Try common build output locations.
        local_bin="$(dirname "$0")/../../bofig/docudactyl/zig-out/bin/lith_adapter"
        if [ -x "$local_bin" ]; then
            ADAPTER_BIN="$local_bin"
        else
            die "lith_adapter binary not found. Build it from docudactyl/ffi/zig/ or specify with -a."
        fi
    fi
fi
[ -x "$ADAPTER_BIN" ] || die "Adapter binary not executable: $ADAPTER_BIN"

if ! $DRY_RUN; then
    command -v curl >/dev/null 2>&1 || die "curl is required for API access"
fi

# ── Main Processing Loop ────────────────────────────────────────────────

log "Starting bofig ingest"
log "  Shard directory:  $SHARD_DIR"
log "  Investigation:    $INVESTIGATION_ID"
log "  Run ID:           $RUN_ID"
log "  Lithoglyph URL:   $LITH_URL"
log "  Dry run:          $DRY_RUN"

# Find all .capnp files in the shard directory tree.
# Docudactyl outputs: {shard_dir}/{shard_N}/{docname}.stages.capnp
capnp_files=()
while IFS= read -r -d '' f; do
    capnp_files+=("$f")
done < <(find "$SHARD_DIR" -name '*.stages.capnp' -type f -print0 | sort -z)

COUNT_TOTAL=${#capnp_files[@]}
log "Found $COUNT_TOTAL .stages.capnp files"

if [ "$COUNT_TOTAL" -eq 0 ]; then
    log "Nothing to ingest."
    exit 0
fi

tmp_json=$(mktemp /tmp/bofig-ingest-XXXXXX.json)
trap 'rm -f "$tmp_json"' EXIT

for capnp_file in "${capnp_files[@]}"; do
    # Derive source filename from the capnp path.
    # Pattern: {shard_dir}/shard_N/original-name.stages.capnp → original-name
    base=$(basename "$capnp_file" .stages.capnp)
    verbose "Processing: $capnp_file (title: $base)"

    # Convert Cap'n Proto → JSON via the Zig adapter.
    if ! "$ADAPTER_BIN" \
        --input "$capnp_file" \
        --title "$base" \
        --investigation "$INVESTIGATION_ID" \
        --run-id "$RUN_ID" \
        --output "$tmp_json" 2>/dev/null; then
        log "WARN: Adapter failed for $capnp_file"
        COUNT_FAILED=$((COUNT_FAILED + 1))
        continue
    fi

    # Extract SHA-256 hash from the JSON for deduplication.
    sha256=""
    if command -v jq >/dev/null 2>&1; then
        sha256=$(jq -r '.sha256_hash // empty' "$tmp_json" 2>/dev/null || true)
    else
        # Fallback: grep the hash from JSON.
        sha256=$(grep -o '"sha256_hash":"[^"]*"' "$tmp_json" | head -1 | cut -d'"' -f4 || true)
    fi

    if $DRY_RUN; then
        echo "--- $base ---"
        if command -v jq >/dev/null 2>&1; then
            jq . "$tmp_json"
        else
            cat "$tmp_json"
        fi
        echo
        COUNT_SUCCESS=$((COUNT_SUCCESS + 1))
        continue
    fi

    # Deduplication check.
    if [ -n "$sha256" ] && check_dedup "$sha256"; then
        verbose "DEDUP: Skipping $base (SHA-256 $sha256 already exists)"
        COUNT_DEDUP=$((COUNT_DEDUP + 1))
        continue
    fi

    # POST to Lithoglyph.
    if post_record "$tmp_json" "$RUN_ID"; then
        verbose "OK: $base"
        COUNT_SUCCESS=$((COUNT_SUCCESS + 1))
    else
        log "WARN: POST failed for $base"
        COUNT_FAILED=$((COUNT_FAILED + 1))
    fi
done

# ── Summary ──────────────────────────────────────────────────────────────

log "─── Ingest Summary ───"
log "  Total files:    $COUNT_TOTAL"
log "  Inserted:       $COUNT_SUCCESS"
log "  Deduplicated:   $COUNT_DEDUP"
log "  Failed:         $COUNT_FAILED"
log "  Skipped:        $COUNT_SKIPPED"
log "  Run ID:         $RUN_ID"

if [ "$COUNT_FAILED" -gt 0 ]; then
    exit 1
fi
exit 0
