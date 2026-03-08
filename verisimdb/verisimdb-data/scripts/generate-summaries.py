#!/usr/bin/env python3
# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# generate-summaries.py - Auto-generate summary fields for repos in index.json
#
# Reads each scan file in scans/ and builds a concise summary string from:
#   - weak point count and severity breakdown
#   - top categories of weak points
#   - detected language
#   - scan timestamp from index.json
#
# Usage: python3 scripts/generate-summaries.py [--dry-run]

import json
import os
import sys
from collections import Counter
from datetime import datetime, timezone

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INDEX_PATH = os.path.join(REPO_ROOT, "index.json")
SCANS_DIR = os.path.join(REPO_ROOT, "scans")

# Severity ordering for "top severity" reporting
SEVERITY_ORDER = {"Critical": 4, "High": 3, "Medium": 2, "Low": 1}


def build_summary(repo_name, scan_data, index_entry):
    """Build a concise summary string from scan data and index entry.

    Format examples:
      "71 weak points (8 High, 58 Medium, 5 Low); top: PanicPath (30), CommandInjection (25); lang: rust"
      "0 weak points; clean scan; lang: elixir"
      "16 weak points (3 Critical, 12 Medium, 1 Low); top: UnsafeCode (8), PanicPath (5); lang: idris2"
    """
    weak_points = scan_data.get("weak_points", [])
    wp_count = len(weak_points)
    language = scan_data.get("language", "unknown")
    last_scan = index_entry.get("last_scan", "unknown")

    # Extract just the date portion from the ISO timestamp
    try:
        scan_date = last_scan[:10]
    except (TypeError, IndexError):
        scan_date = "unknown"

    if wp_count == 0:
        return f"0 weak points; clean scan; lang: {language}; scanned: {scan_date}"

    # Severity breakdown
    severities = Counter(wp.get("severity", "Unknown") for wp in weak_points)
    sev_parts = []
    for sev in sorted(severities.keys(), key=lambda s: SEVERITY_ORDER.get(s, 0), reverse=True):
        sev_parts.append(f"{severities[sev]} {sev}")
    sev_str = ", ".join(sev_parts)

    # Top categories (up to 3)
    categories = Counter(wp.get("category", "Unknown") for wp in weak_points)
    top_cats = categories.most_common(3)
    cat_parts = [f"{cat} ({count})" for cat, count in top_cats]
    cat_str = ", ".join(cat_parts)

    # Top severity for quick triage
    top_sev = max(severities.keys(), key=lambda s: SEVERITY_ORDER.get(s, 0))

    return (
        f"{wp_count} weak points ({sev_str}); "
        f"top: {cat_str}; "
        f"lang: {language}; scanned: {scan_date}"
    )


def main():
    dry_run = "--dry-run" in sys.argv

    # Load index
    with open(INDEX_PATH) as f:
        index = json.load(f)

    repos = index.get("repos", {})
    updated_count = 0
    skipped_count = 0
    error_count = 0

    for repo_name, entry in sorted(repos.items()):
        # Only update NULL summaries
        if entry.get("summary") is not None:
            skipped_count += 1
            continue

        scan_file = os.path.join(SCANS_DIR, f"{repo_name}.json")
        if not os.path.exists(scan_file):
            print(f"  SKIP (no scan file): {repo_name}")
            skipped_count += 1
            continue

        try:
            with open(scan_file) as f:
                scan_data = json.load(f)
        except (json.JSONDecodeError, OSError) as e:
            print(f"  ERROR reading {scan_file}: {e}")
            error_count += 1
            continue

        summary = build_summary(repo_name, scan_data, entry)
        entry["summary"] = summary
        updated_count += 1

        if dry_run:
            wp_count = len(scan_data.get("weak_points", []))
            print(f"  {repo_name}: {summary}")

    # Update timestamp
    index["last_updated"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S+00:00")

    if not dry_run:
        # Write updated index
        with open(INDEX_PATH, "w") as f:
            json.dump(index, f, indent=2)
            f.write("\n")
        print(f"Updated index.json")

    print(f"\nResults: {updated_count} summaries generated, {skipped_count} skipped, {error_count} errors")
    return 0 if error_count == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
