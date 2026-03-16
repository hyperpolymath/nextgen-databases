# Lithoglyph HTTP API

**Production-ready HTTP API for Lithoglyph with Rust NIF integration**

![License](https://img.shields.io/badge/License-PMPL--1.0-blue.svg)
![Build](https://img.shields.io/badge/build-passing-green.svg)
![Status](https://img.shields.io/badge/status-production--ready-green.svg)

## Status: M15 Complete ✅

All milestones complete and production-ready:

| Milestone | Status | Description |
|-----------|--------|-------------|
| M10 | ✅ Complete | Foundation (Phoenix, Bandit, project structure) |
| M11 | ✅ Complete | HTTP API (15 endpoints: CRUD, geo, analytics, journal) |
| M12 | ✅ Complete | Observability & Auth (metrics, JWT, graceful shutdown) |
| M13 | ✅ Complete | Performance (benchmarks, LRU cache, spatial/temporal indices) |
| M14 | ✅ Complete | Rust NIF integration (zero warnings, all tests passing) |
| **M15** | **✅ Complete** | **Production deployment (Kubernetes, podman, Chainguard Wolfi)** |

## Quick Start

### Local Development

```bash
# Install dependencies
mix setup

# Start Phoenix server
mix phx.server

# Or start in IEx
iex -S mix phx.server

# Visit: http://localhost:4000
```

### Production Deployment

**Build OCI image with podman:**
```bash
podman build -t ghcr.io/hyperpolymath/lith-http-api:v1.0.0 -f Containerfile .
```

**Run locally:**
```bash
podman run --rm -p 4000:4000 \
  -e SECRET_KEY_BASE="$(openssl rand -base64 48)" \
  ghcr.io/hyperpolymath/lith-http-api:v1.0.0 start
```

**Deploy to Kubernetes:**
```bash
# See k8s/ directory for complete manifests
kubectl apply -k k8s/overlays/production/
```

## Architecture

### Tech Stack
- **Elixir 1.15.7** / **OTP 26.2.1** - BEAM VM with fault tolerance
- **Phoenix 1.8.3** - Web framework with Bandit server
- **Rust NIF** - Native implemented functions for performance
- **ETS** - In-memory storage for indices and cache

### Security-Focused Build
- **Podman** - Rootless, daemonless OCI container builder
- **Chainguard Wolfi** - Security-hardened distroless base image
- **Multi-stage build** - Minimal attack surface (~140MB)
- **Non-root user** - Runs as UID 1000

### Key Features
- 🚀 **High Performance** - 68K temporal inserts/sec, 656 spatial inserts/sec
- 🔒 **Security-Hardened** - JWT auth, rate limiting, CORS, TLS ready
- 📊 **Observable** - Prometheus metrics, health checks, structured logging
- 🎯 **Spatial/Temporal** - R-tree and B-tree indices with ETS storage
- ⚡ **Zero-Copy IPC** - Rust NIF integration for performance-critical operations
- 🔄 **Graceful Shutdown** - SIGTERM handling for zero-downtime updates

## API Endpoints

**Health & Metrics:**
- `GET /health` - Basic health check
- `GET /health/live` - Liveness probe
- `GET /health/ready` - Readiness probe
- `GET /metrics` - Prometheus metrics

**API (v1):**
- Data: `GET|POST|PUT|DELETE /api/v1/data/:id`
- Geo: `GET /api/v1/geo/within`, `/nearby`, `/intersects`
- Analytics: `GET /api/v1/analytics/aggregate`, `/timeseries`, `/heatmap`, `/summary`
- Journal: `GET /api/v1/journal/since/:timestamp`
- WebSocket: `/socket` (Phoenix Channels)

## Performance

**Benchmarks (M13):**
- Spatial index: 656 inserts/sec, 550 queries/sec
- Temporal index: 68,654 inserts/sec, 1,596 queries/sec
- Query cache: 80.4% hit rate, 29,987 reads/sec
- LRU eviction: Fixed and verified

See `PERFORMANCE-BASELINE-M13.md` for details.

## Production Deployment

### Kubernetes
Complete production manifests in `k8s/`:
- 13 base manifests (deployment, service, ingress, HPA, PDB, etc.)
- Production overlay with 5 replicas, higher resources
- Security: TLS, RBAC, NetworkPolicy, pod security contexts
- Observability: Prometheus ServiceMonitor, health checks
- HA: Auto-scaling (3-10 replicas), PodDisruptionBudget

### Security
- **Chainguard Wolfi** base - Security-hardened runtime
- **TLS** - Let's Encrypt certificates via cert-manager
- **RBAC** - Minimal permissions (read-only)
- **NetworkPolicy** - Ingress/egress filtering
- **Pod Security** - Non-root, read-only FS, seccomp
- **Rate Limiting** - 100 RPS (staging), 500 RPS (production)

See `SECURITY-BUILD-M15.md` for complete security documentation.

## Documentation

- **M13-COMPLETE.md** - Performance benchmarking completion
- **M14-COMPLETE.md** - Rust NIF integration completion
- **M15-COMPLETE.md** - Production deployment completion
- **SECURITY-BUILD-M15.md** - Security-focused build guide
- **PERFORMANCE-BASELINE-M13.md** - Performance analysis
- **k8s/README.md** - Kubernetes deployment guide

## Future: Verified Container Integration

This project will integrate with the **verified container toolchain** (Q2-Q3 2026):
- **Cerro Torre** (82%) - Package as `.ctp` bundle with cryptographic provenance
- **Svalinn** (90%) - Edge gateway with policy enforcement
- **Vörðr** (mixed) - Formally verified container runtime
- **Selur** (dev) - Zero-copy WASM IPC bridge
- **selur-compose** (planned) - Multi-container orchestration

## Testing

```bash
# Run tests
mix test

# Run with coverage
mix test --cover

# Run benchmarks
./bench/run_all_benchmarks.sh
```

## Development

```bash
# Compile (warnings as errors)
mix compile --warnings-as-errors

# Format code
mix format

# Run precommit checks
mix precommit
```

## License

SPDX-License-Identifier: PMPL-1.0-or-later

See `LICENSE` for details.

## Maintainer

**Jonathan D.A. Jewell** <j.d.a.jewell@open.ac.uk>

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
