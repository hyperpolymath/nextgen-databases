#!/usr/bin/env bash
# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <jonathan.jewell@open.ac.uk>
#
# self-ingest.sh — Ingest repository metadata into the self-hosted .verisimdb/ instance.
#
# Converts git commits, known issues, and scan results into hexad JSON files.
# Each hexad has all 6 modalities populated where data is available.
#
# Usage:
#   ./scripts/self-ingest.sh              # Full ingest (all commits)
#   ./scripts/self-ingest.sh --recent 10  # Last N commits only
#   ./scripts/self-ingest.sh --issues     # Known issues only

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
HEXAD_DIR="${REPO_ROOT}/.verisimdb/hexads"
INDEX_FILE="${REPO_ROOT}/.verisimdb/index.json"
BASE_IRI="https://verisim.db/self"

mkdir -p "${HEXAD_DIR}"

# ============================================================================
# Helpers
# ============================================================================

# Simple hash-based embedding: deterministic 64-dim vector from text.
# Not a real embedding model — serves as placeholder until one is integrated.
text_to_embedding() {
    local text="$1"
    local hash
    hash=$(printf '%s' "$text" | sha256sum | cut -d' ' -f1)
    local dims=()
    for i in $(seq 0 2 126); do
        local byte_hex="${hash:$((i % 64)):2}"
        local byte_val=$((16#${byte_hex}))
        # Normalize to [-1.0, 1.0]
        local norm
        norm=$(echo "scale=6; ($byte_val - 128) / 128" | bc -l | sed 's/^\./0./; s/^-\./-0./')
        dims+=("$norm")
    done
    # Pad to 64 dimensions
    while [ ${#dims[@]} -lt 64 ]; do
        dims+=("0.0")
    done
    local result="["
    for i in "${!dims[@]}"; do
        [ "$i" -gt 0 ] && result+=","
        result+="${dims[$i]}"
    done
    result+="]"
    echo "$result"
}

# Classify commit type from conventional commit prefix
classify_commit() {
    local msg="$1"
    case "$msg" in
        feat:*|feat\(*) echo "feature" ;;
        fix:*|fix\(*)   echo "bugfix" ;;
        docs:*|docs\(*) echo "documentation" ;;
        chore:*|chore\(*) echo "chore" ;;
        refactor:*|refactor\(*) echo "refactor" ;;
        test:*|test\(*) echo "test" ;;
        perf:*|perf\(*) echo "performance" ;;
        ci:*|ci\(*)     echo "ci" ;;
        *)              echo "other" ;;
    esac
}

# ============================================================================
# Commit ingestion
# ============================================================================

ingest_commits() {
    local limit="${1:-0}"
    local log_args=(--no-merges --format='%H|%aI|%an|%ae|%s')

    if [ "$limit" -gt 0 ]; then
        log_args+=("-n" "$limit")
    fi

    local count=0
    local co_change_map=""

    echo "Ingesting commits..."

    while IFS='|' read -r hash date author email subject; do
        local hexad_id="commit-${hash:0:12}"
        local hexad_file="${HEXAD_DIR}/${hexad_id}.json"

        # Skip if already ingested
        if [ -f "$hexad_file" ]; then
            continue
        fi

        # Get diff stats
        local stats
        stats=$(git diff-tree --no-commit-id --numstat "$hash" 2>/dev/null || echo "")
        local insertions=0 deletions=0 files_changed=0
        local changed_files=()

        while IFS=$'\t' read -r ins del file; do
            [ -z "$ins" ] && continue
            [ "$ins" = "-" ] && ins=0
            [ "$del" = "-" ] && del=0
            insertions=$((insertions + ins))
            deletions=$((deletions + del))
            files_changed=$((files_changed + 1))
            changed_files+=("$file")
        done <<< "$stats"

        # Build graph relationships: files changed in same commit are co-changed
        local graph_rels="[]"
        if [ ${#changed_files[@]} -gt 0 ] && [ ${#changed_files[@]} -le 20 ]; then
            graph_rels="["
            local first=true
            for f in "${changed_files[@]}"; do
                $first || graph_rels+=","
                first=false
                # Escape the filename for JSON
                local escaped_f
                escaped_f=$(printf '%s' "$f" | sed 's/"/\\"/g')
                graph_rels+="{\"predicate\":\"modifies\",\"target\":\"file:${escaped_f}\"}"
            done
            graph_rels+="]"
        fi

        # Commit type classification
        local commit_type
        commit_type=$(classify_commit "$subject")

        # Embedding (hash-based placeholder)
        local embedding
        embedding=$(text_to_embedding "$subject")

        # Escape subject for JSON
        local escaped_subject
        escaped_subject=$(printf '%s' "$subject" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g')

        # Write hexad JSON
        cat > "$hexad_file" << HEXAD_EOF
{
  "id": "${hexad_id}",
  "source": "git-log",
  "created_at": "${date}",
  "document": {
    "title": "${escaped_subject}",
    "body": "Commit ${hash:0:8} by ${author}: ${escaped_subject}",
    "fields": {
      "type": "commit",
      "hash": "${hash}",
      "author": "${author}",
      "email": "${email}",
      "commit_type": "${commit_type}"
    }
  },
  "graph": {
    "relationships": ${graph_rels}
  },
  "vector": {
    "embedding": ${embedding},
    "model": "sha256-hash-64d"
  },
  "tensor": {
    "shape": [1, 3],
    "data": [${insertions}.0, ${deletions}.0, ${files_changed}.0]
  },
  "semantic": {
    "types": ["${BASE_IRI}/type/Commit", "${BASE_IRI}/type/${commit_type}"],
    "properties": {
      "conventional_commit_type": "${commit_type}",
      "files_changed": "${files_changed}"
    }
  },
  "temporal": {
    "timestamp": "${date}",
    "version": 1,
    "author": "${author}"
  }
}
HEXAD_EOF

        count=$((count + 1))
    done < <(git log "${log_args[@]}")

    echo "  Ingested ${count} commits."
}

# ============================================================================
# Known issues ingestion
# ============================================================================

ingest_known_issues() {
    local issues_file="${REPO_ROOT}/KNOWN-ISSUES.adoc"
    [ -f "$issues_file" ] || { echo "No KNOWN-ISSUES.adoc found."; return; }

    echo "Ingesting known issues..."
    local count=0
    local current_id="" current_title="" current_status="" current_body=""
    local in_issue=false

    while IFS= read -r line; do
        if [[ "$line" =~ ^===\ ([0-9]+)\.\ (.+) ]]; then
            # Flush previous issue
            if [ -n "$current_id" ]; then
                write_issue_hexad "$current_id" "$current_title" "$current_status" "$current_body"
                count=$((count + 1))
            fi

            local num="${BASH_REMATCH[1]}"
            local title_raw="${BASH_REMATCH[2]}"
            current_id="issue-$(printf '%03d' "$num")"

            if [[ "$title_raw" == *"RESOLVED"* ]]; then
                current_status="resolved"
            elif [[ "$title_raw" == *"OPEN"* ]]; then
                current_status="open"
            else
                current_status="unknown"
            fi

            # Strip status markers from title
            current_title=$(printf '%s' "$title_raw" | sed 's/ — ✅ RESOLVED//; s/ (OPEN)//; s/ (OPEN — LOW)//')
            current_body=""
            in_issue=true
        elif $in_issue; then
            current_body+="${line}\n"
        fi
    done < "$issues_file"

    # Flush last issue
    if [ -n "$current_id" ]; then
        write_issue_hexad "$current_id" "$current_title" "$current_status" "$current_body"
        count=$((count + 1))
    fi

    echo "  Ingested ${count} known issues."
}

write_issue_hexad() {
    local id="$1" title="$2" status="$3" body="$4"
    local hexad_file="${HEXAD_DIR}/${id}.json"

    local escaped_title
    escaped_title=$(printf '%s' "$title" | sed 's/\\/\\\\/g; s/"/\\"/g')
    local escaped_body
    escaped_body=$(printf '%s' "$body" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\n/\\n/g' | head -c 2000)

    local embedding
    embedding=$(text_to_embedding "$title")

    local severity="medium"
    [[ "$status" == "resolved" ]] && severity="resolved"

    cat > "$hexad_file" << ISSUE_EOF
{
  "id": "${id}",
  "source": "known-issues",
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "document": {
    "title": "${escaped_title}",
    "body": "${escaped_body}",
    "fields": {
      "type": "known_issue",
      "status": "${status}",
      "severity": "${severity}"
    }
  },
  "graph": {
    "relationships": [{"predicate": "documented_in", "target": "file:KNOWN-ISSUES.adoc"}]
  },
  "vector": {
    "embedding": ${embedding},
    "model": "sha256-hash-64d"
  },
  "tensor": {
    "shape": [1, 2],
    "data": [$([ "$status" = "resolved" ] && echo "1.0, 0.0" || echo "0.0, 1.0")]
  },
  "semantic": {
    "types": ["${BASE_IRI}/type/KnownIssue", "${BASE_IRI}/type/${status}"],
    "properties": {
      "status": "${status}",
      "severity": "${severity}"
    }
  },
  "temporal": {
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "version": 1,
    "author": "self-ingest"
  }
}
ISSUE_EOF
}

# ============================================================================
# Index builder
# ============================================================================

build_index() {
    echo "Building index..."
    local hexad_count
    hexad_count=$(find "${HEXAD_DIR}" -name "*.json" | wc -l)

    local commits issues
    commits=$(find "${HEXAD_DIR}" -name "commit-*.json" | wc -l)
    issues=$(find "${HEXAD_DIR}" -name "issue-*.json" | wc -l)

    # Collect all hexad IDs
    local ids="["
    local first=true
    for f in "${HEXAD_DIR}"/*.json; do
        [ -f "$f" ] || continue
        local basename
        basename=$(basename "$f" .json)
        $first || ids+=","
        first=false
        ids+="\"${basename}\""
    done
    ids+="]"

    cat > "$INDEX_FILE" << INDEX_EOF
{
  "instance": "verisimdb-self",
  "version": "0.1.0-alpha",
  "base_iri": "${BASE_IRI}",
  "generated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "stats": {
    "total_hexads": ${hexad_count},
    "commits": ${commits},
    "known_issues": ${issues}
  },
  "hexad_ids": ${ids}
}
INDEX_EOF

    echo "  Index: ${hexad_count} hexads (${commits} commits, ${issues} issues)."
}

# ============================================================================
# Main
# ============================================================================

main() {
    local mode="full"
    local limit=0

    while [ $# -gt 0 ]; do
        case "$1" in
            --recent)
                mode="recent"
                limit="${2:-10}"
                shift 2
                ;;
            --issues)
                mode="issues"
                shift
                ;;
            --index)
                mode="index"
                shift
                ;;
            *)
                echo "Usage: $0 [--recent N] [--issues] [--index]"
                exit 1
                ;;
        esac
    done

    echo "VeriSimDB Self-Ingest"
    echo "====================="
    echo "Instance: verisimdb-self"
    echo "Store: ${HEXAD_DIR}"
    echo ""

    case "$mode" in
        full)
            ingest_commits 0
            ingest_known_issues
            build_index
            ;;
        recent)
            ingest_commits "$limit"
            build_index
            ;;
        issues)
            ingest_known_issues
            build_index
            ;;
        index)
            build_index
            ;;
    esac

    echo ""
    echo "Done. Hexads stored in ${HEXAD_DIR}"
}

main "$@"
