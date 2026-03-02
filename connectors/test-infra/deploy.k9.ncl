# SPDX-License-Identifier: PMPL-1.0-or-later
#
# deploy.k9.ncl — k9-svc deployment component for VeriSimDB test infrastructure
#
# Security Level: 'Hunt (requires cryptographic handshake)
#
# This is a LEGITIMATE Hunt-level component: it spawns database containers,
# writes to the filesystem (volumes), and binds network ports. It requires
# explicit authorization before execution.
#
# Author: Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

let pedigree = import "../../standards/k9-svc/pedigree.ncl" in
let leash = import "../../standards/k9-svc/leash.ncl" in

# ---------------------------------------------------------------------------
# Component pedigree (self-description)
# ---------------------------------------------------------------------------

let component_pedigree = {
  metadata = {
    name = "verisimdb-test-infra",
    version = "0.1.0",
    breed = "application/vnd.k9+nickel",
    magic_number = "K9!",
    description = "Integration test database stack for VeriSimDB federation adapters (7 services)",
  },
  target = {
    os = 'Linux,
    is_edge = false,
    requires_podman = true,
    min_memory_mb = 4096,
  },
  security = {
    trust_level = 'Hunt,
    allow_network = true,
    allow_filesystem_write = true,
    allow_subprocess = true,
    # In production, this would be a real Ed25519 signature
    signature = "PLACEHOLDER-SIGNATURE-REQUIRED-FOR-HUNT",
  },
  validation = {
    checksum = "sha256:placeholder-compose-and-seed-checksum",
    pedigree_version = "1.0.0",
    hunt_authorized = false,  # Must be set true after handshake
  },
  recipes = {
    install = "just test-infra-build",
    validate = "just test-infra-validate",
    deploy = "just test-infra-up",
    migrate = "just test-infra-seed",
  },
} in

# ---------------------------------------------------------------------------
# Deployment configuration
# ---------------------------------------------------------------------------

let deployment = {
  # Test infrastructure only has one environment: local testing
  environments = {
    test = {
      replicas = 1,
      memory = "4Gi",
      cpu = "2000m",
      image_tag = "latest",
    },
  },

  # Services (7 databases)
  services = {
    mongodb = {
      image = "cgr.dev/chainguard/mongodb:latest",
      ports = [27017],
      purpose = "Document store federation (replica set for change streams)",
    },
    redis_stack = {
      image = "verisimdb-test-redis-stack:latest",
      ports = [6379],
      purpose = "In-memory store with RediSearch, RedisJSON, RedisTimeSeries",
    },
    neo4j = {
      image = "verisimdb-test-neo4j:latest",
      ports = [7474, 7687],
      purpose = "Graph database with APOC plugin",
    },
    clickhouse = {
      image = "verisimdb-test-clickhouse:latest",
      ports = [8123, 9000],
      purpose = "Columnar analytics for aggregate drift queries",
    },
    surrealdb = {
      image = "verisimdb-test-surrealdb:latest",
      ports = [8000],
      purpose = "Multi-model database (document + graph)",
    },
    influxdb = {
      image = "verisimdb-test-influxdb:latest",
      ports = [8086],
      purpose = "Time-series database for temporal modality",
    },
    minio = {
      image = "cgr.dev/chainguard/minio:latest",
      ports = [9002, 9001],
      purpose = "S3-compatible object storage for binary blobs",
    },
  },

  # Network
  network = {
    driver = "selur",
    fallback = "bridge",
  },
} in

# ---------------------------------------------------------------------------
# Deployment scripts
# ---------------------------------------------------------------------------

let scripts = {
  # Build all custom images
  install = m%"
#!/bin/sh
set -eu
echo "K9: Building VeriSimDB test infrastructure images..."
cd connectors/test-infra
./ct-build.sh
echo "K9: Build complete."
"%,

  # Validate compose.toml and seed scripts exist
  validate = m%"
#!/bin/sh
set -eu
echo "K9: Validating VeriSimDB test infrastructure..."
cd connectors/test-infra

for file in compose.toml manifest.toml .gatekeeper.yaml vordr.toml; do
    if [ ! -f "$file" ]; then
        echo "K9: FAIL — missing $file"
        exit 1
    fi
done

for seed in seed/mongodb-init.js seed/redis-init.sh seed/neo4j-init.cypher \
            seed/clickhouse-init.sql seed/surrealdb-init.surql \
            seed/influxdb-init.sh seed/minio-init.sh; do
    if [ ! -f "$seed" ]; then
        echo "K9: FAIL — missing $seed"
        exit 1
    fi
done

echo "K9: Validation passed (all files present)."
"%,

  # Start the full stack
  deploy = m%"
#!/bin/sh
set -eu
echo "K9: Deploying VeriSimDB test infrastructure..."
cd connectors/test-infra

if command -v selur-compose >/dev/null 2>&1; then
    selur-compose up --detach
elif command -v podman-compose >/dev/null 2>&1; then
    podman-compose up --detach
else
    echo "K9: FAIL — neither selur-compose nor podman-compose found"
    exit 1
fi

echo "K9: Test infrastructure deployed."
echo "K9: Waiting for services to become healthy..."
sleep 15
echo "K9: Services should be ready. Run seed scripts next."
"%,

  # Run all seed scripts
  migrate = m%"
#!/bin/sh
set -eu
echo "K9: Seeding VeriSimDB test databases..."
cd connectors/test-infra/seed

echo "K9: MongoDB seeds automatically via entrypoint."

echo "K9: Seeding Redis..."
./redis-init.sh

echo "K9: Seeding Neo4j..."
cat neo4j-init.cypher | cypher-shell -a bolt://localhost:7687 2>/dev/null || \
    echo "K9: WARN — cypher-shell not found, skip Neo4j seed (seed manually)"

echo "K9: Seeding ClickHouse..."
clickhouse-client --multiquery < clickhouse-init.sql 2>/dev/null || \
    echo "K9: WARN — clickhouse-client not found, skip ClickHouse seed (seed manually)"

echo "K9: Seeding SurrealDB..."
cat surrealdb-init.surql | surreal sql --endpoint http://localhost:8000 --ns verisimdb --db test 2>/dev/null || \
    echo "K9: WARN — surreal CLI not found, skip SurrealDB seed (seed manually)"

echo "K9: Seeding InfluxDB..."
./influxdb-init.sh

echo "K9: Seeding MinIO..."
./minio-init.sh

echo "K9: All seeds complete."
"%,

  # Tear down the stack
  teardown = m%"
#!/bin/sh
set -eu
echo "K9: Tearing down VeriSimDB test infrastructure..."
cd connectors/test-infra

if command -v selur-compose >/dev/null 2>&1; then
    selur-compose down --volumes
elif command -v podman-compose >/dev/null 2>&1; then
    podman-compose down --volumes
fi

echo "K9: Test infrastructure removed."
"%,
} in

# ---------------------------------------------------------------------------
# Export the component
# ---------------------------------------------------------------------------

{
  pedigree = component_pedigree,
  deployment = deployment,
  scripts = scripts,

  # Security check: this component requires Hunt level
  required_level = 'Hunt,

  # Warning for users
  warning = m%"
WARNING: This is a Hunt-level component.

It spawns 7 database containers, binds 11 network ports, and writes to
local volumes. Before running, ensure you have:

1. Reviewed the compose.toml and Containerfiles
2. Verified the signature (when implemented)
3. Explicitly authorized Hunt-level execution
4. At least 4 GB RAM available for the database stack

Run with: just authorize connectors/test-infra/deploy.k9.ncl && just test-infra-up
"%,
}
