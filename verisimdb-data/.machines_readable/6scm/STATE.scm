;; SPDX-License-Identifier: PMPL-1.0-or-later
;; STATE.scm - Project state tracking for verisimdb-data
;; Media-Type: application/vnd.state+scm

(define-state verisimdb-data
  (metadata
    (version "1.0.0")
    (schema-version "1.0.0")
    (created "2026-02-08")
    (updated "2026-02-12")
    (project "verisimdb-data")
    (repo "hyperpolymath/verisimdb-data"))

  (project-context
    (name "verisimdb-data")
    (tagline "Git-backed flat-file storage for VeriSimDB scan results")
    (tech-stack ("GitHub Actions" "JSON" "Bash"))
    (purpose "Stores panic-attack security scan results as JSON files in a git repo, serves as data layer for the verisimdb pipeline without requiring a persistent server"))

  (current-position
    (phase "operational")
    (overall-completion 85)
    (components
      ((scan-storage . 100)
       (ingest-workflow . 100)
       (index-management . 100)
       (helper-scripts . 100)
       (automated-dispatch . 90)
       (documentation . 100)
       (temporal-drift . 0)))
    (working-features
      ("Git-backed scan storage (scans/*.json)"
       "Master index (index.json) with per-repo metadata"
       "Ingest workflow (.github/workflows/ingest.yml) accepts repository_dispatch"
       "Reusable scan-and-report workflow in panic-attacker"
       "3 pilot repos: echidna (15 weak pts), ambientops (0), verisimdb (12)"
       "Helper scripts: ingest-scan.sh, scan-all.sh"
       "VERISIMDB_PAT support with GITHUB_TOKEN fallback in workflows"
       "All caller workflows pass VERISIMDB_PAT secret"
       "Deployed to GitHub and GitLab"
       "Comprehensive documentation (INTEGRATION.md, SESSION-SUMMARY.md)")))

  (route-to-mvp
    (milestones
      ((name "Initial Setup")
       (status "complete")
       (completion 100)
       (items
         ("Create verisimdb-data repo" . done)
         ("Add ingest workflow" . done)
         ("Create helper scripts" . done)
         ("Deploy to GitHub + GitLab" . done)))

      ((name "Pilot Deployment")
       (status "complete")
       (completion 100)
       (items
         ("Add security-scan workflow to echidna" . done)
         ("Add security-scan workflow to ambientops" . done)
         ("Add security-scan workflow to verisimdb" . done)
         ("Verify scan results" . done)))

      ((name "Automated Dispatch")
       (status "in-progress")
       (completion 90)
       (items
         ("Update scan-and-report.yml with PAT support" . done)
         ("Update caller workflows to pass VERISIMDB_PAT" . done)
         ("Create PAT with repo scope" . todo)
         ("Add VERISIMDB_PAT secret to pilot repos" . todo)))

      ((name "Temporal Analysis")
       (status "planned")
       (completion 0)
       (items
         ("Compare scans over time" . todo)
         ("Drift detection between scan runs" . todo)
         ("Trend reporting" . todo)))))

  (blockers-and-issues
    (critical ())
    (high ())
    (medium ("PAT creation required for fully automated dispatch"
             "echidna GitLab mirror diverged (protected branch + expired PAT)"))
    (low ("Temporal drift detection not yet implemented"
          "No SARIF output for GitHub Security tab")))

  (critical-next-actions
    (immediate
      "Create GitHub classic PAT with repo scope"
      "Add VERISIMDB_PAT secret to echidna, ambientops, verisimdb")
    (this-week
      "Test end-to-end automated dispatch"
      "Add more repos to security scanning")
    (this-month
      "Implement temporal drift detection"
      "SARIF output for GitHub Security tab"))

  (session-history
    ((session . "2026-02-12 workflow-automation")
     (summary . "Updated all workflow files for automated PAT-based dispatch")
     (changes
       ("Updated scan-and-report.yml with optional VERISIMDB_PAT secret and GITHUB_TOKEN fallback"
        "Updated all 3 pilot repo security-scan.yml to pass VERISIMDB_PAT"
        "Fixed ambientops GitLab mirror (unshallowed + remote added)"
        "Updated INTEGRATION.md (Steps 3-4 marked DONE)"
        "Added SESSION-SUMMARY.md addendum for 2026-02-12")))

    ((session . "2026-02-08 initial-deployment")
     (summary . "Created verisimdb-data repo and full pipeline")
     (changes
       ("Created repo with scan storage, ingest workflow, index management"
        "Deployed security-scan workflows to 3 pilot repos"
        "Scanned 3 repos: 27 total weak points"
        "Created helper scripts and comprehensive documentation"
        "Pushed to GitHub and GitLab")))))

;; Helper functions
(define (get-completion-percentage state)
  (current-position 'overall-completion state))

(define (get-blockers state severity)
  (blockers-and-issues severity state))

(define (get-milestone state name)
  (find (lambda (m) (equal? (car m) name))
        (route-to-mvp 'milestones state)))
