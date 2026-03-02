;; SPDX-License-Identifier: PMPL-1.0-or-later
;; VeriSimDB Operational Playbook
;; Media type: application/x-scheme
;; Last updated: 2026-01-22

(define-module (verisimdb playbook)
  #:version "1.0.0"
  #:updated "2026-01-22T12:30:00Z")

;; ============================================================================
;; DEPLOYMENT PLAYBOOKS
;; ============================================================================

(define deployment-playbooks
  '((standalone-deployment
      (phases
        ((phase "Infrastructure Preparation")
         (steps
           "1. Provision server: 4+ cores, 8GB+ RAM, 50GB+ disk
            2. Install dependencies: Rust 1.85+, Elixir 1.17+, Deno 2.0+
            3. Configure firewall: Allow ports 4000 (Elixir), 8080 (API), 9090 (metrics)
            4. Set up monitoring: Prometheus + Grafana or equivalent")
         (success-criteria
           "- All dependencies installed and versions verified
            - Ports accessible from expected networks
            - Monitoring dashboards showing server metrics"))

        ((phase "Database Installation")
         (steps
           "1. Clone repository: git clone https://github.com/hyperpolymath/verisimdb
            2. Build Rust stores: cargo build --release --workspace
            3. Build Elixir orchestration: mix deps.get && mix compile
            4. Build ReScript registry: deno task build
            5. Run tests: cargo test && mix test")
         (success-criteria
           "- All builds succeed without errors
            - All tests pass
            - Binaries created in target/release/"))

        ((phase "Configuration")
         (steps
           "1. Copy config template: cp config/verisimdb.example.toml config/verisimdb.toml
            2. Edit config: Set data directory, ports, logging level
            3. Initialize stores: ./scripts/init-stores.sh
            4. Verify configuration: ./verisimdb-cli verify-config")
         (success-criteria
           "- Config file valid TOML
            - All modality stores initialized
            - verisimdb-cli reports 'Configuration valid'"))

        ((phase "First Start")
         (steps
           "1. Start VeriSimDB: ./verisimdb start
            2. Check logs: tail -f logs/verisimdb.log
            3. Verify health: curl https://localhost:8080/health
            4. Run smoke tests: ./scripts/smoke-test.sh")
         (success-criteria
           "- Server starts without errors
            - Health endpoint returns HTTP 200
            - Smoke tests pass (basic queries work)"))))

    (federated-deployment
      (phases
        ((phase "Registry Setup")
         (steps
           "1. Deploy registry node (ReScript WASM)
            2. Generate federation keypair: ./verisimdb-cli keygen
            3. Register stores: ./verisimdb-cli register-store <name> <url> <pubkey>
            4. Verify registry: ./verisimdb-cli list-stores")
         (success-criteria
           "- Registry responsive
            - Stores registered with valid signatures
            - list-stores shows all expected stores"))

        ((phase "Store Configuration")
         (steps
           "1. On each store: Copy federation config
            2. Set registry URL in config
            3. Enable federation mode: federation.enabled = true
            4. Restart store: ./verisimdb restart")
         (success-criteria
           "- Each store connects to registry
            - Stores visible to each other
            - Federation metadata log synced"))

        ((phase "Quorum Testing")
         (steps
           "1. Create test hexad on Store A
            2. Query from Store B: SELECT * FROM FEDERATION /stores/* WHERE id = <test-id>
            3. Verify quorum: Check logs for quorum voting
            4. Simulate Byzantine fault: Stop Store C, verify quorum still works")
         (success-criteria
           "- Federated queries succeed
            - Quorum voting logged
            - System tolerates f=1 Byzantine faults"))))))

;; ============================================================================
;; OPERATIONAL RUNBOOKS
;; ============================================================================

(define operational-runbooks
  '((hexad-not-found
      (symptom . "Query returns 'Hexad not found' for valid ID")
      (diagnosis
        "1. Check if hexad exists in any modality:
            $ ./verisimdb-cli inspect-hexad <id>
         2. Check drift detection logs:
            $ grep 'drift:' logs/verisimdb.log | grep <id>
         3. Verify federation connectivity:
            $ ./verisimdb-cli federation-status")
      (resolution
        "If hexad exists but not found:
         - Option A: Trigger normalization repair:
           $ ./verisimdb-cli repair-drift --hexad <id> --level L1
         - Option B: Rebuild cross-modal index:
           $ ./verisimdb-cli rebuild-index --modality ALL
         - Option C: If federated, check quorum:
           $ ./verisimdb-cli quorum-check --hexad <id>")
      (prevention
        "- Enable adaptive learning to auto-tune drift detection
         - Increase cache TTL if false negatives common
         - Monitor drift metrics dashboard"))

    (query-timeout
      (symptom . "VQL queries timeout after 30 seconds")
      (diagnosis
        "1. Check query plan: Add EXPLAIN to query
         2. Check store load: ./verisimdb-cli store-stats
         3. Check federation latency: ./verisimdb-cli federation-latency
         4. Check for deadlocks: grep 'deadlock' logs/verisimdb.log")
      (resolution
        "If query plan inefficient:
         - Add indexes: CREATE INDEX ON <modality> (<field>)
         - Use LIMIT clause: LIMIT 100
         - Break into smaller queries: Query incrementally

         If store overloaded:
         - Scale vertically: Increase RAM, CPU
         - Scale horizontally: Add federation stores
         - Cache frequent queries: Enable query result cache

         If federation latency high:
         - Check network: ping between stores
         - Reduce quorum size: f=1 instead of f=2
         - Use LOCAL queries: SELECT FROM verisim:local (skip federation)")
      (prevention
        "- Set up query monitoring (Grafana dashboard)
         - Enable slow query log (queries > 1s)
         - Use VQL Explain regularly to review plans"))

    (proof-generation-fails
      (symptom . "Query with PROOF clause returns 'Proof generation failed'")
      (diagnosis
        "1. Check predicate verifiability:
            $ ./verisimdb-cli verify-predicate '<predicate>'
         2. Check circuit complexity:
            $ grep 'circuit_constraints' logs/verisimdb.log
         3. Check proven library version:
            $ cargo tree | grep proven")
      (resolution
        "If predicate not verifiable:
         - Remove non-arithmetic operations (substring, sha256)
         - Simplify predicate (fewer ∀ quantifiers)
         - Use EXISTENCE instead of UNIVERSAL (cheaper)

         If circuit too complex:
         - Reduce result set size: Add LIMIT
         - Use Merkle tree optimization: proof.optimization = 'merkle'
         - Split into multiple queries

         If proven library issue:
         - Update proven: cargo update -p proven
         - Check for known issues: https://github.com/proven-network/proven/issues")
      (prevention
        "- Validate predicates before deployment
         - Set circuit complexity limits in config
         - Monitor proof generation latency"))

    (federation-partition
      (symptom . "Federation stores unreachable, quorum fails")
      (diagnosis
        "1. Check network connectivity:
            $ ./verisimdb-cli ping-stores
         2. Check registry status:
            $ curl https://registry-node/health
         3. Check Raft log:
            $ ./verisimdb-cli raft-status")
      (resolution
        "If network partition:
         - Wait for partition to heal (queries will retry)
         - Use LOCAL queries: SELECT FROM verisim:local
         - Reduce timeout: Set query_timeout_ms = 5000

         If registry unavailable:
         - Fallback to local mode: federation.fallback_local = true
         - Query specific store: SELECT FROM verisim:store/<name>

         If split-brain (conflicting Raft leaders):
         - Stop all stores
         - Elect leader manually: ./verisimdb-cli raft-elect <store-id>
         - Restart stores sequentially")
      (prevention
        "- Set up network monitoring
         - Use multiple network paths (redundancy)
         - Configure appropriate timeouts"))

    (disk-space-full
      (symptom . "VeriSimDB crashes with 'No space left on device'")
      (diagnosis
        "1. Check disk usage: df -h
         2. Check data directory size: du -sh /var/lib/verisimdb
         3. Check log size: du -sh logs/
         4. Check temporal store: du -sh /var/lib/verisimdb/temporal")
      (resolution
        "Immediate:
         - Stop VeriSimDB: ./verisimdb stop
         - Free space: Delete old backups, truncate logs
         - Restart: ./verisimdb start

         Short-term:
         - Compress temporal log: ./verisimdb-cli compact-temporal
         - Archive old data: ./verisimdb-cli archive --before 2025-01-01
         - Enable log rotation: logrotate config

         Long-term:
         - Increase disk size: Provision larger volume
         - Enable compression: store.compression = 'zstd'
         - Set data retention policy: temporal.retention_days = 90")
      (prevention
        "- Set up disk space monitoring (alert at 80%)
         - Enable automatic compaction (daily cron)
         - Configure max log size (10GB per store)"))))

;; ============================================================================
;; MONITORING & ALERTS
;; ============================================================================

(define monitoring-config
  '((key-metrics
      (query-latency
        (description . "Time from query submission to result return")
        (target . "p50 < 50ms, p99 < 500ms")
        (alert-threshold . "p99 > 1000ms for 5 minutes")
        (dashboard . "VeriSimDB Performance"))

      (drift-detection-rate
        (description . "Number of drift events detected per hour")
        (target . "< 100 events/hour (1% of 10k hexads)")
        (alert-threshold . "> 1000 events/hour (indicates systemic issue)")
        (dashboard . "VeriSimDB Drift Monitor"))

      (proof-generation-success-rate
        (description . "Percentage of PROOF queries that succeed")
        (target . "> 95%")
        (alert-threshold . "< 90% for 10 minutes")
        (dashboard . "VeriSimDB ZKP"))

      (cache-hit-rate
        (description . "Percentage of queries served from cache")
        (target . "> 80%")
        (alert-threshold . "< 50% for 15 minutes")
        (dashboard . "VeriSimDB Cache"))

      (federation-availability
        (description . "Percentage of federation stores reachable")
        (target . "100%")
        (alert-threshold . "< 80% (quorum at risk)")
        (dashboard . "VeriSimDB Federation")))

    (alert-rules
      ((alert "QueryLatencyHigh")
       (expr . "histogram_quantile(0.99, rate(verisimdb_query_duration_seconds_bucket[5m])) > 1.0")
       (severity . "warning")
       (action . "Check slow query log, review query plans, consider adding indexes"))

      ((alert "DriftRateHigh")
       (expr . "rate(verisimdb_drift_events_total[1h]) > 1000")
       (severity . "critical")
       (action . "Investigate drift source, check for data corruption, verify federation sync"))

      ((alert "ProofGenerationFailing")
       (expr . "rate(verisimdb_proof_generation_failures_total[10m]) / rate(verisimdb_proof_generation_attempts_total[10m]) > 0.1")
       (severity . "critical")
       (action . "Check proven library logs, verify circuit complexity, review predicate restrictions"))

      ((alert "FederationPartition")
       (expr . "verisimdb_federation_reachable_stores / verisimdb_federation_total_stores < 0.8")
       (severity . "critical")
       (action . "Check network connectivity, ping stores, review Raft status, prepare for manual failover"))))

    (dashboards
      ((dashboard "VeriSimDB Overview")
       (panels
         "- Query rate (queries/sec)
          - Query latency (p50, p95, p99)
          - Cache hit rate
          - Store CPU/memory usage
          - Drift detection rate
          - Federation health"))

      ((dashboard "VeriSimDB ZKP")
       (panels
         "- Proof generation rate
          - Proof generation latency
          - Proof verification rate
          - Circuit complexity histogram
          - Proof size distribution
          - Proof success/failure ratio"))

      ((dashboard "VeriSimDB Federation")
       (panels
         "- Store availability heatmap
          - Quorum voting latency
          - Raft leader elections
          - Network latency matrix (store-to-store)
          - Byzantine fault detection
          - Metadata log lag")))))

;; ============================================================================
;; BACKUP & RECOVERY
;; ============================================================================

(define backup-procedures
  '((full-backup
      (frequency . "Weekly (Sunday 2am)")
      (procedure
        "1. Stop writes: ./verisimdb-cli set-read-only true
         2. Create snapshot: ./verisimdb-cli snapshot --output /backups/verisimdb-$(date +%Y%m%d).tar.gz
         3. Verify snapshot: tar -tzf /backups/verisimdb-*.tar.gz | head
         4. Resume writes: ./verisimdb-cli set-read-only false
         5. Upload to object storage: aws s3 cp /backups/verisimdb-*.tar.gz s3://backups/")
      (retention . "4 weeks (rolling)"))

    (incremental-backup
      (frequency . "Daily (midnight)")
      (procedure
        "1. Backup temporal log: ./verisimdb-cli backup-temporal --since $(date -d 'yesterday' +%Y-%m-%d)
         2. Backup changed hexads: ./verisimdb-cli backup-incremental --output /backups/incremental-$(date +%Y%m%d).tar.gz
         3. Verify incremental: ./verisimdb-cli verify-backup /backups/incremental-*.tar.gz
         4. Upload to object storage: aws s3 cp /backups/incremental-*.tar.gz s3://backups/incremental/")
      (retention . "7 days (rolling)"))

    (restore-from-backup
      (scenario . "Catastrophic data loss, restore from full backup")
      (procedure
        "1. Stop VeriSimDB: ./verisimdb stop
         2. Clear data directory: rm -rf /var/lib/verisimdb/*
         3. Download backup: aws s3 cp s3://backups/verisimdb-20260115.tar.gz /tmp/
         4. Extract backup: tar -xzf /tmp/verisimdb-20260115.tar.gz -C /var/lib/verisimdb
         5. Verify extraction: ls -lh /var/lib/verisimdb/
         6. Start VeriSimDB: ./verisimdb start
         7. Verify data: ./verisimdb-cli health-check --full
         8. Apply incremental backups (if available): ./verisimdb-cli restore-incremental /tmp/incremental-*.tar.gz")
      (expected-downtime . "15-30 minutes (depends on backup size)"))))

;; ============================================================================
;; UPGRADE PROCEDURES
;; ============================================================================

(define upgrade-procedures
  '((minor-upgrade
      (scenario . "Upgrade from v1.0.x to v1.1.x (backwards compatible)")
      (procedure
        "1. Review CHANGELOG: cat CHANGELOG.adoc | grep 'v1.1'
         2. Backup current version: ./verisimdb-cli snapshot --output /backups/pre-upgrade.tar.gz
         3. Stop VeriSimDB: ./verisimdb stop
         4. Download new version: wget https://github.com/hyperpolymath/verisimdb/releases/download/v1.1.0/verisimdb-linux-amd64.tar.gz
         5. Extract: tar -xzf verisimdb-*.tar.gz -C /opt/verisimdb
         6. Run migration: ./verisimdb-cli migrate --from 1.0 --to 1.1
         7. Start VeriSimDB: ./verisimdb start
         8. Verify upgrade: ./verisimdb-cli version && ./verisimdb-cli health-check")
      (rollback
        "If upgrade fails:
         1. Stop new version: ./verisimdb stop
         2. Restore old version: cp /opt/verisimdb.old /opt/verisimdb
         3. Restore data: ./verisimdb-cli restore /backups/pre-upgrade.tar.gz
         4. Start old version: ./verisimdb start")
      (expected-downtime . "5-10 minutes"))

    (major-upgrade
      (scenario . "Upgrade from v1.x to v2.x (breaking changes)")
      (procedure
        "1. Review migration guide: docs/MIGRATION-v1-to-v2.adoc
         2. Test upgrade in staging environment FIRST
         3. Export data: ./verisimdb-cli export --format vql --output /backups/data-export.vql
         4. Stop VeriSimDB: ./verisimdb stop
         5. Install new version: ./scripts/install-v2.sh
         6. Run migration: ./verisimdb-cli migrate --from 1.x --to 2.0 --verify
         7. Import data: ./verisimdb-cli import --format vql --input /backups/data-export.vql
         8. Start VeriSimDB: ./verisimdb start
         9. Verify: Run smoke tests ./scripts/smoke-test-v2.sh")
      (rollback
        "Major upgrades may not be reversible. Restore from full backup.")
      (expected-downtime . "30-60 minutes (depends on data size)"))))

;; Export public API
(define-public deployment-playbooks deployment-playbooks)
(define-public operational-runbooks operational-runbooks)
(define-public monitoring-config monitoring-config)
(define-public backup-procedures backup-procedures)
(define-public upgrade-procedures upgrade-procedures)
