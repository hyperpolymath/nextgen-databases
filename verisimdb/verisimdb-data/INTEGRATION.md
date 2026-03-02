# SPDX-License-Identifier: PMPL-1.0-or-later

# VeriSimDB Integration Guide

Complete guide for the panic-attack → verisimdb-data → hypatia → gitbot-fleet pipeline.

## Architecture

```
┌─────────────────┐
│ Repos with      │
│ security-scan   │──┐
│ workflow        │  │
└─────────────────┘  │
                     │  panic-attack scan
                     ↓  (JSON output)
            ┌──────────────────┐
            │ verisimdb-data   │
            │ (git-backed)     │
            │ - scans/*.json   │
            │ - index.json     │
            └──────────────────┘
                     │
                     ↓  read scans
            ┌──────────────────┐
            │ hypatia          │
            │ - Logtalk rules  │
            │ - Pattern detect │
            └──────────────────┘
                     │
                     ↓  dispatch findings
            ┌──────────────────┐
            │ gitbot-fleet     │
            │ - sustainabot    │
            │ - echidnabot     │
            │ - rhodibot       │
            └──────────────────┘
```

## Current Status (2026-02-12)

### ✅ Complete

- verisimdb-data repo created and deployed (GitHub + GitLab)
- Reusable scan-and-report workflow in panic-attacker repo
- 3 pilot repos with security-scan workflows (echidna, ambientops, verisimdb)
- Hypatia VeriSimDB connector (reads scans, generates Logtalk facts)
- Hypatia pattern analyzer (summary statistics)
- Hypatia fleet dispatcher (routes findings to bots)
- Helper scripts for manual scan ingestion
- **Verified working:** 3 repos scanned, 27 weak points found, facts generated
- **Workflow automation**: scan-and-report.yml accepts optional VERISIMDB_PAT with GITHUB_TOKEN fallback (2026-02-12)
- **Caller workflows updated**: All 3 pilot repos pass VERISIMDB_PAT secret to reusable workflow (2026-02-12)

### ⚠️ Remaining Setup

**One manual step required**: Create a GitHub classic PAT with `repo` scope and add it as `VERISIMDB_PAT` secret to the 3 pilot repos (see Steps 1-2 below). The workflow files are already configured to use it.

### 🔲 Not Yet Implemented

- Live GraphQL endpoints for gitbot-fleet
- Automated Logtalk rule evaluation
- Fleet dispatcher with real bot connections
- Temporal drift detection (comparing scans over time)

## Quick Start - Manual Workflow

### Scan a single repo

```bash
# 1. Run scan
cd ~/Documents/hyperpolymath-repos/echidna
panic-attack assail . --output /tmp/echidna-scan.json

# 2. Ingest result
cd ~/Documents/hyperpolymath-repos/verisimdb-data
./scripts/ingest-scan.sh echidna /tmp/echidna-scan.json

# 3. Push to remotes
git push
git push gitlab main
```

### Scan multiple repos

```bash
cd ~/Documents/hyperpolymath-repos/verisimdb-data
./scripts/scan-all.sh echidna ambientops verisimdb
git push
git push gitlab main
```

### Test Hypatia integration

```bash
cd ~/Documents/hyperpolymath-repos/hypatia
mix run test_integration.exs
```

## Automated Workflow Setup (PAT Method)

### Step 1: Create Personal Access Token

1. Go to https://github.com/settings/tokens
2. Click "Generate new token" → "Generate new token (classic)"
3. Name: `verisimdb-dispatch`
4. Scopes: **Check `repo` (Full control of private repositories)**
5. Generate token and **save it securely**

### Step 2: Add PAT to Scanning Repos

For each repo that will send scans (echidna, ambientops, verisimdb, etc.):

1. Go to repo Settings → Secrets and variables → Actions
2. Click "New repository secret"
3. Name: `VERISIMDB_PAT`
4. Value: [paste your PAT]
5. Click "Add secret"

### Step 3: Update scan-and-report Workflow ✅ DONE (2026-02-12)

The reusable workflow `panic-attacker/.github/workflows/scan-and-report.yml` now:
- Accepts optional `VERISIMDB_PAT` secret via `workflow_call`
- Uses `${{ secrets.VERISIMDB_PAT || secrets.GITHUB_TOKEN }}` with automatic fallback
- Uses `curl -sf` for silent failure detection on dispatch

### Step 4: Update Calling Workflows ✅ DONE (2026-02-12)

All 3 pilot repos now pass the `VERISIMDB_PAT` secret:
- `echidna/.github/workflows/security-scan.yml`
- `ambientops/.github/workflows/security-scan.yml`
- `verisimdb/.github/workflows/security-scan.yml`

### Step 5: Test Automated Dispatch

```bash
gh workflow run security-scan.yml --repo hyperpolymath/echidna
```

Then check verisimdb-data for new commits:

```bash
cd ~/Documents/hyperpolymath-repos/verisimdb-data
git pull
ls scans/
cat index.json
```

## Hypatia Pattern Detection

### Loading Scans

```elixir
# In Elixir REPL
scans = Hypatia.VerisimdbConnector.fetch_all_scans()
# => Loads all scans from verisimdb-data/scans/

summary = Hypatia.PatternAnalyzer.generate_summary(scans)
# => %{total_repos: 3, total_weak_points: 27, ...}
```

### Generating Logtalk Facts

```elixir
{:ok, analysis} = Hypatia.PatternAnalyzer.analyze_all_scans()
# => Writes facts to /tmp/scan_facts.lgt
```

Facts format:
```prolog
weak_point('echidna', 'src/rust/provers/z3.rs', 'PanicPath', 'Medium').
weak_point('echidna', 'src/rust/ffi/mod.rs', 'UnsafeCode', 'High').
```

### Pattern Detection Rules

See `hypatia/prolog/pattern_detection.lgt`:

- `widespread_unsafe/2` - Find patterns appearing in 3+ repos
- `critical_weak_points/2` - Count critical issues per repo
- `repo_risk_score/2` - Calculate numeric risk score

### Fleet Dispatch (Placeholder)

```elixir
findings = [
  %{type: :eco_score, repo: "echidna", score: 75, details: "..."},
  %{type: :proof_obligation, repo: "echidna", claim: "...", context: "..."},
  %{type: :fix_suggestion, repo: "echidna", file: "...", issue: "...", suggestion: "..."}
]

Hypatia.PatternAnalyzer.process_findings(findings)
# => Logs dispatch to sustainabot, echidnabot, rhodibot
```

**Note:** GraphQL mutations are currently logged, not sent. Bots need to expose GraphQL endpoints.

## Querying Scan Data

### Show all scan summaries

```bash
jq '.repos' ~/Documents/hyperpolymath-repos/verisimdb-data/index.json
```

### Find repos with most weak points

```bash
jq -r '.repos | to_entries | sort_by(.value.weak_points) | reverse | map("\(.key): \(.value.weak_points)") | .[]' index.json
```

### Get specific repo scan

```bash
jq '.' ~/Documents/hyperpolymath-repos/verisimdb-data/scans/echidna.json | less
```

## Future Enhancements

### Short-term
- Create PAT and add as VERISIMDB_PAT secret (only remaining manual step)
- Add more repos to security scanning
- Implement actual GraphQL endpoints for gitbot-fleet

### Medium-term
- Temporal drift detection (compare scans over time)
- Automated rule learning (detect new patterns)
- SARIF output for GitHub Security tab
- Fly.io deployment of verisim-api (optional, beyond flat files)

### Long-term
- GitHub App for organization-wide scanning
- Real-time pattern detection (immediate alerts)
- Integration with echidnabot for formal verification
- Automated fix generation via rhodibot

## Troubleshooting

### Workflow fails with "Action not pinned to SHA"

**Solution:** Update to SHA-pinned version (see `~/.claude/CLAUDE.md` for SHAs)

### Repository dispatch not received

**Check:**
1. Is PAT configured in scanning repo secrets?
2. Does PAT have `repo` scope?
3. Is reusable workflow using `secrets.VERISIMDB_PAT` instead of `GITHUB_TOKEN`?
4. Check verisimdb-data workflow runs: `gh run list --repo hyperpolymath/verisimdb-data`

### Scan fails with "unexpected argument --format"

**Solution:** panic-attack writes JSON automatically when `--output` is specified. Remove `--format json` flag.

### Hypatia can't load scans

**Check:**
1. Is verisimdb-data at `~/Documents/hyperpolymath-repos/verisimdb-data`?
2. Do JSON files exist in `scans/` directory?
3. Is Jason dependency installed? (`cd hypatia && mix deps.get`)

## Support

- panic-attack issues: https://github.com/hyperpolymath/panic-attacker/issues
- verisimdb issues: https://github.com/hyperpolymath/verisimdb/issues
- hypatia issues: https://github.com/hyperpolymath/hypatia/issues

## References

- SONNET-TASKS.md - Original implementation tasks
- scripts/README.md - Helper script documentation
- hypatia/test_integration.exs - Integration test example
- panic-attacker/.claude/CLAUDE.md - panic-attack documentation
- verisimdb/.claude/CLAUDE.md - VeriSimDB architecture
