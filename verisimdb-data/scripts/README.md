# SPDX-License-Identifier: PMPL-1.0-or-later

# VeriSimDB Data Scripts

Helper scripts for ingesting scan results into verisimdb-data.

## Scripts

### `ingest-scan.sh`

Ingest a single scan result into verisimdb-data.

**Usage:**
```bash
# Run panic-attack on a repo
cd ~/Documents/hyperpolymath-repos/echidna
panic-attack assail . --output /tmp/echidna-scan.json

# Ingest the result
cd ~/Documents/hyperpolymath-repos/verisimdb-data
./scripts/ingest-scan.sh echidna /tmp/echidna-scan.json
```

**What it does:**
1. Copies scan result to `scans/<repo>.json`
2. Updates `index.json` with summary
3. Commits the changes

**After running:**
```bash
git push
git push gitlab main
```

### `scan-all.sh`

Scan multiple repos and ingest all results in one go.

**Usage:**
```bash
# Scan default repos (echidna, ambientops, verisimdb)
cd ~/Documents/hyperpolymath-repos/verisimdb-data
./scripts/scan-all.sh

# Scan specific repos
./scripts/scan-all.sh panic-attacker hypatia echidna

# Scan all repos in a directory
./scripts/scan-all.sh ~/Documents/hyperpolymath-repos/*
```

**What it does:**
1. Runs `panic-attack assail` on each repo
2. Ingests each result using `ingest-scan.sh`
3. Shows summary of all scans

**After running:**
```bash
git push
git push gitlab main
```

## Integration with GitHub Actions

Once a Personal Access Token (PAT) is configured, the reusable workflow will automatically send scan results to verisimdb-data:

```yaml
# In any repo's .github/workflows/security-scan.yml
jobs:
  scan:
    uses: hyperpolymath/panic-attacker/.github/workflows/scan-and-report.yml@main
    secrets:
      PAT_TOKEN: ${{ secrets.VERISIMDB_PAT }}
```

**PAT Requirements:**
- Scope: `repo` (to trigger repository_dispatch events)
- Stored as secret `VERISIMDB_PAT` in each scanning repo
- Alternative: Use GitHub App with repository_dispatch permissions

## Querying Results

### View index
```bash
jq '.' index.json
```

### Find repos with high weak point counts
```bash
jq -r '.repos | to_entries | map(select(.value.weak_points > 10)) | map("\(.key): \(.value.weak_points)") | .[]' index.json
```

### Get latest scan time
```bash
jq -r '.last_updated' index.json
```

## Hypatia Integration

Test pattern detection with current scan data:

```bash
cd ~/Documents/hyperpolymath-repos/hypatia
mix run test_integration.exs
```

This will:
- Load all scans from verisimdb-data
- Generate Logtalk facts
- Show summary statistics
