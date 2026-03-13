# Changelog

All notable changes to Lith will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

---

## [2.0.0] - 2026-01-12

**Lith 2.0.0 - Feature-Complete Major Release**

This release marks a major milestone: all 18 milestones complete, representing the feature-complete vision of Lith as a narrative-first, self-normalizing database.

### Highlights

- **18 Milestones Complete** - From M1 (Specification) through M18 (Advanced Analytics)
- **Distributed Mode** - Full cluster coordination, Raft consensus, sharding, and replication
- **Advanced Analytics** - Statistical aggregations, time series analysis, window functions
- **Production Hardened** - Health checks, graceful shutdown, configuration validation
- **Multi-Protocol API** - REST, gRPC, GraphQL, WebSocket
- **CMS Integrations** - Strapi, Directus, Ghost, Payload
- **Client Libraries** - ReScript, PHP with full SDK generator

### What's New Since 1.0.0

#### Distributed Computing (v1.1.0)
- Cluster coordination with node discovery and membership
- Raft consensus for leader election and log replication
- Consistent hashing with virtual nodes for data sharding
- Configurable consistency levels (One, Quorum, All)

#### Advanced Analytics (v1.2.0)
- Statistical aggregations (sum, avg, stddev, percentile, etc.)
- Time series analysis with trend detection and anomaly detection
- SQL-style window functions (Rank, Lag, Lead, CumulativeSum)
- Visualization exports (CSV, JSON, Chart.js, Vega-Lite, D3)

### Complete Feature Set

| Category | Features |
|----------|----------|
| **Storage** | 4KiB blocks, CRC32C integrity, append-only journal |
| **Query** | GQL language, query planner, EXPLAIN modes |
| **Normalization** | DFD discovery, 1NF-BCNF analysis, three-phase migration |
| **API** | REST, gRPC, GraphQL, WebSocket subscriptions |
| **Distributed** | Cluster, Raft consensus, sharding, replication |
| **Analytics** | Aggregations, time series, window functions, exports |
| **Performance** | Query cache, connection pool, batch operations, metrics |
| **Stability** | Config validation, health checks, graceful shutdown |
| **Clients** | ReScript, PHP with SDK generator |
| **CMS** | Strapi, Directus, Ghost, Payload integrations |
| **Testing** | Property-based, fuzz, integration, E2E |

### Breaking Changes

None - v2.0.0 maintains backward compatibility with the v1.x series.

### Thank You

Lith 2.0.0 represents the complete realization of the narrative-first database vision. Every schema change, every constraint, every migration is now a story that can be told, verified, and understood.

---

## [1.2.0] - 2026-01-12

Advanced Analytics milestone: **M18 Complete**

This release adds comprehensive analytics capabilities to Lith.

### Added

#### Aggregations (`analytics/src/Lith_Analytics_Aggregations.res`)
- Statistical aggregations: Count, Sum, Avg, Min, Max
- Advanced: Median, Stddev, Variance, Percentile
- CountDistinct for unique value counting
- Group by with multiple aggregations
- Numeric value extraction from JSON

#### Time Series (`analytics/src/Lith_Analytics_TimeSeries.res`)
- Time bucketing (Second to Year granularity)
- Trend analysis with linear regression
- Moving average calculation
- Anomaly detection using standard deviation
- R-squared and slope metrics

#### Window Functions (`analytics/src/Lith_Analytics_Window.res`)
- Ranking: RowNumber, Rank, DenseRank, PercentRank, Ntile
- Navigation: Lag, Lead, FirstValue, LastValue, NthValue
- Running calculations: CumulativeSum, RunningAvg
- Partition by and order by support
- Configurable frame boundaries

#### Visualization Export (`analytics/src/Lith_Analytics_Export.res`)
- CSV export with configurable options
- JSON export for APIs
- Chart.js configuration export
- Vega-Lite specification export
- D3-compatible data format
- Table data format (columns + rows)

#### Documentation
- `analytics/README.md` - Comprehensive analytics documentation
- Use case examples (sales, financial, user analytics)
- Function reference for all modules

### Changed

- STATE.scm updated to M18 100% completion
- Added analytics module to working-features

---

## [1.1.0] - 2026-01-12

Distributed Mode milestone: **M17 Complete**

This release adds distributed computing capabilities to Lith.

### Added

#### Cluster Coordination (`distributed/src/Lith_Distributed_Cluster.res`)
- Node discovery and membership management
- Node status tracking (Starting, Joining, Active, Leaving, Down)
- Node roles (Leader, Follower, Candidate)
- Cluster state versioning
- JSON serialization for cluster state

#### Raft Consensus (`distributed/src/Lith_Distributed_Consensus.res`)
- Leader election with term tracking
- Log replication with entry types (Command, Configuration, NoOp)
- Vote request/response handling
- Append entries request/response handling
- Election timeout detection

#### Data Sharding (`distributed/src/Lith_Distributed_Sharding.res`)
- Consistent hashing with virtual nodes
- Multiple sharding strategies (Hash, Range, Directory)
- Shard status tracking (Initializing, Active, Migrating, Inactive)
- Node-to-shard mapping
- Shard statistics

#### Data Replication (`distributed/src/Lith_Distributed_Replication.res`)
- Configurable consistency levels (One, Quorum, All, LocalQuorum)
- Replication modes (Synchronous, Asynchronous, SemiSync)
- Replication event queue
- Replica status tracking
- Lag statistics

#### Documentation
- `distributed/README.md` - Comprehensive distributed mode documentation
- Deployment patterns (single region, multi-region)
- Best practices for cluster sizing and consistency tuning

### Changed

- STATE.scm updated to M17 100% completion
- Added distributed module to working-features

---

## [1.0.0] - 2026-01-12

**Lith 1.0.0 - First Production Release**

🎉 The database where the database is part of the story.

This release marks the first stable, production-ready version of Lith - a narrative-first database where schemas, constraints, migrations, blocks, and journals are treated as narrative artefacts.

### Highlights

- **16 Milestones Complete** - All foundational work from M1 (Specification) through M16 (Stabilization)
- **Multi-Protocol API** - REST, gRPC, GraphQL, and WebSocket support
- **Self-Normalizing Engine** - Automatic FD discovery and normalization proposals
- **Proof-Carrying Operations** - Lean 4 integration for verified transformations
- **Production Ready** - Health checks, graceful shutdown, configuration validation

### Core Features

#### Storage Layer (Form.Blocks)
- 4 KiB fixed-size blocks with 64-byte headers
- CRC32C integrity verification
- Block types: SUPERBLOCK, DOCUMENT, EDGE, JOURNAL, SCHEMA

#### Journal System
- Append-only journal with sequence numbering
- Full operation history with inverses
- Crash recovery and replay semantics
- Provenance tracking for audit trails

#### Query Language (GQL)
- SELECT, INSERT, UPDATE, DELETE operations
- CREATE, DROP for schema management
- EXPLAIN, INTROSPECT for debugging
- WITH PROVENANCE clause for audit context
- Graph traversal syntax (TRAVERSE)

#### Self-Normalizing Database
- DFD (Depth-First Discovery) for FD detection
- Normal form analysis (1NF through BCNF)
- Three-phase migration: Announce → Shadow → Commit
- Denormalization proposals with rationale

### Platform Support

#### API Protocols
| Protocol | Features |
|----------|----------|
| REST | OpenAPI 3.1, full CRUD, health/metrics |
| gRPC | Protobuf, all service methods |
| GraphQL | SDL schema, subscriptions, introspection |
| WebSocket | RFC 6455, graphql-ws, journal streaming |

#### Client Libraries
| Language | Features |
|----------|----------|
| ReScript | Type-safe, fluent query builder, Deno runtime |
| PHP | PSR-18, PHP 8.1+, Laravel/Symfony integration |

#### CMS Integrations
| CMS | Type | Sync Modes |
|-----|------|------------|
| Strapi | Plugin | Bidirectional, CMS→Lith, Lith→CMS |
| Directus | Hook Extension | Bidirectional, CMS→Lith, Lith→CMS |
| Ghost | Webhook Server | Bidirectional, CMS→Lith, Lith→CMS |
| Payload | Adapter | Bidirectional, CMS→Lith, Lith→CMS |

### Quality & Reliability

#### Testing
- Property-based tests with random generators
- Fuzz testing with 8 mutation strategies
- Integration tests for all CMS plugins
- E2E tests for API and sync scenarios

#### Performance
- Query plan LRU cache with TTL
- Connection pooling with auto-scaling
- Batch operations with configurable flush
- Prometheus-compatible metrics

#### Stability
- Type-safe configuration validation
- Component health monitoring
- Graceful shutdown with phased execution
- Production readiness checker

### Breaking Changes

None - this is the first stable release.

### Upgrade Notes

For projects using pre-1.0 versions:
- API stability is now guaranteed per [VERSIONING.adoc](VERSIONING.adoc)
- Binary format stability guaranteed within 1.x series
- Deprecation warnings will be provided before any breaking changes

### Thank You

Lith represents a new approach to databases - one where the database itself becomes part of the story your data tells. Thank you to everyone who contributed to making this release possible.

---

## [0.0.10] - 2026-01-12

Final Stabilization milestone: **M16 Complete - Ready for 1.0.0**

This release completes Milestone M16, the final stabilization before the 1.0.0 production release.

### Added

#### Configuration Validation (`stability/src/Lith_Stability_Config.res`)
- Type-safe configuration schema
- Environment-specific validation rules
- Production security enforcement (API key, CORS)
- Environment variable loading
- Validation error formatting

#### Health Checks (`stability/src/Lith_Stability_Health.res`)
- Component health monitoring (Healthy/Degraded/Unhealthy)
- Extensible health check registry
- Built-in checks: memory, storage, bridge
- Latency tracking per component
- JSON export for Kubernetes probes

#### Graceful Shutdown (`stability/src/Lith_Stability_Shutdown.res`)
- Coordinated shutdown sequence
- Priority-based handler execution
- Four shutdown phases: DrainConnections → FlushBuffers → CloseResources → Terminated
- Configurable timeout
- Status reporting

#### Production Readiness (`stability/src/Lith_Stability_Readiness.res`)
- Pre-flight checks across 5 categories:
  - Security: API key, CORS, TLS
  - Performance: Pool size, query cache
  - Reliability: Health endpoint, graceful shutdown
  - Observability: Metrics, tracing, logging
  - Configuration: Environment setting
- Severity levels (Critical/Warning/Info)
- Human-readable report formatting

#### Documentation
- `stability/README.md` - Comprehensive stability documentation
- Kubernetes integration examples (liveness/readiness probes)
- Production deployment best practices

### Changed

- STATE.scm updated to M16 100% completion
- Added stability module to working-features

---

## [0.0.9] - 2026-01-12

Performance Optimization milestone: **M15 Complete**

This release completes Milestone M15, delivering production-ready performance features.

### Added

#### Query Plan Cache (`perf/src/Lith_Perf_Cache.res`)
- LRU cache with TTL-based expiration
- Configurable max size and TTL
- Cache hit/miss statistics
- Thread-safe entry management
- Automatic stale entry cleanup

#### Connection Pool (`perf/src/Lith_Perf_Pool.res`)
- Connection pooling with min/max sizing
- Idle timeout and automatic cleanup
- Acquire timeout with waiting queue
- Pool statistics (total, idle, in-use, waiting)
- Connection health management

#### Batch Operations (`perf/src/Lith_Perf_Batch.res`)
- Batch insert, update, delete operations
- Configurable batch size and flush intervals
- Retry on failure with max retries
- Auto-flush when batch size limit reached
- Error tracking per operation

#### Performance Metrics (`perf/src/Lith_Perf_Metrics.res`)
- Prometheus-compatible metric export
- Counter and Gauge metric types
- Timer context for latency measurement
- Pre-defined metrics:
  - `lith_query_total` - Total queries executed
  - `lith_query_latency_ms` - Last query latency
  - `lith_cache_hits_total` / `lith_cache_misses_total`
  - `lith_connection_pool_size` / `lith_active_connections`
  - `lith_batch_size` / `lith_errors_total`

#### Documentation
- `perf/README.md` - Comprehensive performance module documentation
- Best practices for caching, pooling, batching, and monitoring
- Configuration reference for all modules

### Changed

- STATE.scm updated to M15 100% completion
- Added performance module to working-features

---

## [0.0.8] - 2026-01-12

Testing & Verification milestone: **M14 Complete**

This release completes Milestone M14, delivering a comprehensive testing framework.

### Added

#### Property-Based Tests (`tests/property/`)
- Random GQL statement generators
- Structural property verification
- Configurable iterations and seed
- Property test runner with result tracking

#### Fuzz Testing (`tests/fuzz/`)
- Multiple mutation strategies (BitFlip, ByteFlip, Dictionary, etc.)
- Corpus-based fuzzing with seed inputs
- Crash and interesting input detection
- GQL parser fuzz targets

#### Integration Tests (`tests/integration/`)
- Strapi plugin tests (9 test cases)
- Directus extension tests (7 test cases)
- Ghost webhook tests (8 test cases)
- Payload adapter tests (9 test cases)
- Mock HTTP client for isolated testing

#### E2E Tests (`tests/e2e/`)
- API suite (health, CRUD, queries, introspection)
- Sync suite (create, update, delete, provenance, bidirectional)
- HTTP client utilities for Deno

#### Test Documentation
- `tests/README.md` - Comprehensive test suite documentation
- Quick start guide for all test categories
- CI integration examples
- Configuration reference

### Changed

- STATE.scm updated to M14 100% completion
- Added test components to working-features

---

## [0.0.7] - 2026-01-12

CMS Integrations milestone: **M13 Complete**

This release completes Milestone M13, delivering official CMS integration plugins for popular headless CMS platforms.

### Added

#### CMS Integrations (`integrations/`)

- **Strapi Plugin** (`integrations/strapi/`)
  - Strapi v4/v5 plugin written in ReScript
  - Real-time content sync to Lith
  - Lifecycle hooks: afterCreate, afterUpdate, afterDelete
  - Collection mapping with configurable sync modes
  - Field exclusion support for sensitive data
  - Provenance metadata for audit trails
  - Types: StrapiContext, ContentTypeConfig, SyncMode

- **Directus Extension** (`integrations/directus/`)
  - Hook extension for Directus CMS
  - Action handlers for items.create, items.update, items.delete
  - Environment-based configuration
  - Selective collection sync via LITH_SYNC_COLLECTIONS
  - Lith client with GQL query execution

- **Ghost Integration** (`integrations/ghost/`)
  - Webhook server for Ghost CMS (Deno runtime)
  - Event types: post.published, post.updated, post.deleted
  - Page and member events support
  - HMAC signature verification
  - Configurable collection mappings
  - Docker deployment support

- **Payload CMS Adapter** (`integrations/payload/`)
  - Plugin for Payload CMS
  - Collection hooks: afterChange, afterDelete
  - Field exclusion configuration
  - Localized field support (nested locale objects)
  - TypeScript type definitions included

#### Sync Modes (All Integrations)

| Mode | Description |
|------|-------------|
| `bidirectional` | Sync changes both ways |
| `cms-to-lith` | Only sync CMS changes to Lith |
| `lithoglyph-to-cms` | Only sync Lith changes to CMS |

#### Provenance Tracking

All integrations add provenance metadata to Lith:
```json
{
  "actor": "strapi-plugin",
  "rationale": "Auto-sync from Strapi create event",
  "source": "strapi",
  "model": "article",
  "action": "create",
  "timestamp": "2026-01-12T10:30:00Z"
}
```

#### Documentation

- `integrations/README.md` - Comprehensive integration overview
- Quick start examples for all four CMS platforms
- Environment variable reference
- Architecture diagram

### Changed

- STATE.scm updated to M13 100% completion
- Added CMS integration components to working-features

---

## [0.0.6] - 2026-01-12

Language Bindings milestone: **M12 Complete**

This release completes Milestone M12, delivering official client libraries for ReScript and PHP.

### Added

#### Client Libraries

- **ReScript Client** (`clients/rescript/`)
  - Type-safe client for Deno runtime
  - Full type definitions: Provenance, QueryResult, Collection, JournalEntry
  - Fluent query builder with type-safe WHERE clauses
  - Filter expressions: Field, And, Or, Not
  - Support for all GQL operations (SELECT, INSERT, UPDATE, DELETE)
  - Collection management (list, create, delete)
  - Journal access with filtering
  - Normalization operations (discover dependencies, analyze normal form)
  - Migration operations (start, commit)
  - Health check endpoint
  - Environment-based configuration (LITH_URL, LITH_API_KEY)
  - API key and Bearer token authentication

- **PHP Client** (`clients/php/`)
  - PSR-18 HTTP client compatible
  - PHP 8.1+ with strict types
  - Full type definitions as final readonly classes
  - Enums: CollectionType, JournalOperation, NormalForm, ConfidenceLevel, MigrationPhase, HealthStatus
  - Fluent query builders: QueryBuilder, InsertBuilder, UpdateBuilder, DeleteBuilder
  - Filter classes: FieldFilter, AndFilter, OrFilter, NotFilter with CompareOp enum
  - All comparison operators: =, !=, <, <=, >, >=, LIKE, IN
  - Framework integration examples: Laravel, Symfony
  - LithException with error codes and details
  - Environment-based configuration

#### SDK Generator (`tools/sdk-gen/`)

- API specification in ReScript (`ApiSpec.res`)
  - Full Lith REST API model
  - Type definitions, endpoints, parameters
  - HTTP methods, request/response types

- Code generators
  - `ReScriptGen.res` - Generate ReScript client code
  - `PhpGen.res` - Generate PHP client code

- CLI entry point (`Main.res`)
  - `deno task gen:rescript` - Generate ReScript SDK
  - `deno task gen:php` - Generate PHP SDK

#### Documentation

- `clients/README.md` - Comprehensive client library documentation
  - Quick start examples for both languages
  - Query builder usage patterns
  - Filter expression examples
  - Authentication configuration
  - Error handling patterns

### Changed

- STATE.scm updated to M12 100% completion
- Tech stack now includes "clients" section with ReScript and PHP

---

## [0.0.5] - 2026-01-12

Multi-Protocol API Server milestone: **M11 Complete**

This release completes Milestone M11, delivering a production-ready multi-protocol API server with full Form.Bridge FFI integration.

### Added

#### Multi-Protocol API Server
- **REST API** (`api/src/rest.zig`)
  - OpenAPI 3.1 specification compliance
  - Full CRUD endpoints for collections, documents, and queries
  - Health and metrics endpoints
  - Wired to Form.Bridge FFI for real database operations

- **gRPC API** (`api/src/grpc.zig`)
  - Protocol Buffer serialization/deserialization
  - Full protobuf encoder with varint, tag/wire type handling
  - Protobuf decoder for message parsing
  - All service methods wired to Form.Bridge FFI
  - Support for Query, ListCollections, GetCollection, CreateCollection
  - Support for GetJournal, DiscoverDependencies, AnalyzeNormalForm
  - Migration operations (StartMigration, GetMigrationStatus)

- **GraphQL API** (`api/src/graphql.zig`)
  - GraphQL SDL schema with full type system
  - Query, Mutation, and Subscription support
  - GraphiQL UI for exploration
  - Introspection support
  - WebSocket integration for subscriptions

- **WebSocket Support** (`api/src/websocket.zig`)
  - RFC 6455 compliant WebSocket implementation
  - WebSocket upgrade handling with SHA-1 accept key
  - Frame encoding/decoding (text, binary, ping, pong, close)
  - graphql-ws protocol for GraphQL subscriptions
  - Subscription management with connection state
  - Journal streaming subscription type

- **Form.Bridge Integration** (`api/src/bridge_client.zig`)
  - FFI bindings to core Lith engine
  - CBOR encoding for all operations
  - Graceful degraded mode when bridge unavailable
  - Health check, query execution, collection management

#### Integration Tests (`api/src/integration_tests.zig`)
- REST API endpoint tests
- gRPC protobuf encoder/decoder tests
- gRPC frame encoding tests
- GraphQL request parsing tests
- WebSocket accept key computation tests (RFC 6455 compliance)
- WebSocket frame encoding tests
- WebSocket subscription message tests
- Bridge client integration tests

#### Ecosystem Coordination
- **UNIFIED-ROADMAP.scm** - Cross-repo roadmap for MVP 1.0.0
  - Dependency graph for Lith, FQLdt, Studio, Debugger
  - Critical path phases P1-P3
  - Post-MVP roadmap (1.1.0, 1.2.0, 2.0.0)
  - Success metrics and quality gates

### Changed
- Updated STATE.scm to M11 100% completion
- All API handlers now use Form.Bridge FFI instead of mock responses
- Build configuration includes all new modules in test suite

---

## [0.0.4] - 2026-01-12

MVP Completion milestone: **Form.Runtime + Form.Normalizer Complete**

This release completes Milestones M8-M10, delivering a fully functional query engine and self-normalizing database capabilities.

### Added

#### Form.Runtime (M8) - Query Engine
- **GQL Parser** (`core-factor/gql/gql.factor`)
  - Full PEG-based parser for GQL statements
  - Support for SELECT, INSERT, UPDATE, DELETE, CREATE, DROP
  - EXPLAIN, INTROSPECT statements
  - WHERE clause with comparison operators
  - LIMIT/OFFSET pagination
  - Graph traversal (TRAVERSE) syntax
  - WITH PROVENANCE clause

- **Query Planner**
  - Cost-based query planning
  - Step types: scan, project, limit, traverse, insert, update, delete
  - Plan optimization for filtered queries
  - Rationale generation for plan decisions

- **Query Executor**
  - In-memory and pluggable persistent storage
  - Full CRUD operations
  - Filter evaluation engine
  - Introspection commands (SCHEMA, CONSTRAINTS, COLLECTIONS, JOURNAL)

- **EXPLAIN Modes**
  - `EXPLAIN` - Show query plan
  - `EXPLAIN ANALYZE` - Execute and report timing
  - `EXPLAIN VERBOSE` - PostgreSQL-style readable plan output
  - `EXPLAIN ANALYZE VERBOSE` - Combined timing and verbose output

#### Form.Normalizer (M9) - Self-Normalizing Engine
- **FD Discovery** (`normalizer/factor/fd-discovery.factor`)
  - DFD (Depth-First Discovery) algorithm implementation
  - Configurable sampling and confidence thresholds
  - Three-tier confidence classification (high/medium/low)
  - Attribute partition refinement
  - Discovered FD validation

- **Normal Form Analysis**
  - 1NF through BCNF detection
  - Violation identification with explanations
  - Prime attribute detection
  - Key inference from functional dependencies

- **Denormalization Proposals**
  - Automatic denormalization suggestion generation
  - Join-based vs materialized view approaches
  - Migration path generation

- **Three-Phase Migration Framework** (`normalizer/factor/migration.factor`)
  - Announce phase: Signal intent, generate rewrite rules
  - Shadow phase: Dual-write to old and new schemas
  - Commit phase: Complete migration, remove compatibility views
  - Query rewriting during migration
  - Rollback support (abort migration)
  - Migration state tracking and narrative generation

#### Lean4 Integration
- **Bridge.lean** - FFI bindings with CBOR encoding
  - Status codes matching Zig ABI
  - FD proof encoding/decoding
  - Normalization proof encoding
  - Verification API

- **Proofs.lean** - Proof-carrying transformations
  - VerifiedFD, VerifiedNormalizationStep, VerifiedDenormalizationStep
  - VerifiedMigration with phase tracking
  - Journal packaging for proof blobs
  - Round-trip verification support

- **lakefile.toml** - Lean4 project configuration
  - Dependencies on Std, Mathlib4
  - Build configuration for FormNormalizer library

#### Production Hardening (M10)
- **Seam Tests** (`core-factor/gql/seam-tests.factor`)
  - End-to-end pipeline validation: Parser → Planner → Executor → Normalizer
  - EXPLAIN correlation tests
  - Error propagation tests
  - Large dataset stress tests

- **Benchmarks** (`core-factor/gql/benchmarks.factor`)
  - Parser performance benchmarks
  - Planner performance benchmarks
  - Executor benchmarks (SELECT, INSERT, UPDATE with varying data sizes)
  - FD discovery benchmarks
  - Normal form analysis benchmarks
  - Full pipeline benchmarks
  - Memory estimation utilities
  - Quick benchmark for CI regression detection

- **Storage Backend** (`core-factor/gql/storage-backend.factor`)
  - Pluggable storage abstraction
  - Memory backend (default, for testing)
  - Bridge backend (persistent storage via Form.Bridge)
  - Runtime backend selection

#### Ecosystem Alignment
- Updated ECOSYSTEM.scm with alignment status for gql-dt and lithoglyph-debugger
- Cross-repo STATE.scm synchronization with integration points
- Documented FFI compatibility (CBOR proof blobs)
- Identified alignment gaps for future work

### Changed
- Executor now uses pluggable storage backend instead of direct hash table
- STATE.scm updated to Phase 8: MVP Complete (85% overall completion)
- All milestones M1-M10 now at 100%

### Migration Tests
- Comprehensive test suite for three-phase migration lifecycle
- Phase transition validation
- Rewrite rule generation tests
- Compatibility view tests
- Error handling and recovery tests

---

## [0.0.3] - 2026-01-12

Documentation milestone release: **Complete Documentation Suite**

This release completes Milestone M7, providing comprehensive documentation for production deployment and integration.

### Added
- Comprehensive QUICKSTART.adoc tutorial (15-minute guide with full examples)
- Complete VERSIONING.adoc stability policy document
- Complete documentation suite in `docs/`:
  - `docs/DEPLOYMENT.adoc` - Production deployment guide (Docker, Kubernetes, systemd)
  - `docs/SECURITY-AUTH.adoc` - Authentication, authorization, and security hardening
  - `docs/API-REFERENCE.adoc` - Complete programmatic interface reference (Form.Bridge FFI, GQL API)
  - `docs/MIGRATION-FROM-RDBMS.adoc` - PostgreSQL/MySQL/SQLite migration guide with type mappings
  - `docs/OBSERVABILITY.adoc` - Logging, Prometheus metrics, OpenTelemetry tracing, Grafana dashboards
  - `docs/INTEGRATION-PATTERNS.adoc` - Message queues, search engines, analytics, AI/ML pipelines

### Changed
- License updated from MPL-2.0 to Palimpsest-MPL 1.0 (PMPL-1.0)
- README.adoc reorganized with comprehensive Documentation section

### Fixed
- License badge now correctly shows PMPL-1.0
- Fixed typo in Palimpsest link (licence → license)

---

## [0.0.2] - 2026-01-11

Major milestone release: **Core Specifications Complete + PoC Implementation**

This release completes Milestones M1-M6, establishing Lith as a functional proof-of-concept.

### Added

#### Core Specifications (M1)
- **GQL Language Specification** (`spec/gql.adoc`)
  - Complete EBNF grammar for PoC subset
  - 10 example queries covering all operations
  - Document, edge, schema, and introspection operations
  - Provenance syntax (`WITH PROVENANCE {...}`)

- **GQL Dependent Types Specification** (`spec/gql-dependent-types.md`)
  - Full FQLdt specification with Lean 4 integration
  - Compile-time query verification
  - Proof-carrying schema evolution
  - Type-level encoding of database constraints

- **Self-Normalizing Database Specification** (`spec/self-normalizing.adoc`)
  - Automatic functional dependency discovery (DFD/TANE/FDHits)
  - Normal form predicates (1NF through BCNF)
  - Proof-carrying normalization decisions
  - Narrative explanations for all schema changes

- **Block Format Specification** (`spec/blocks.adoc`)
  - 4 KiB fixed-size blocks with 64-byte headers
  - Block types: SUPERBLOCK, DOCUMENT, EDGE, JOURNAL, SCHEMA, etc.
  - CRC32C checksums for integrity
  - Compression and encryption flags

- **Journal Format Specification** (`spec/journal.adoc`)
  - Append-only journal with sequence numbers
  - Full operation history with inverses
  - Crash recovery and replay semantics

- **Cloud Storage Specification** (`spec/cloud-storage.adoc`)
  - Object storage integration patterns
  - Tiered storage for hot/warm/cold data

- **GQL Design Philosophy** (`spec/gql-philosophy.adoc`)
  - Narrative-first query design
  - Comparison with SQL philosophy
  - Constraints as ethics

#### Forth Implementation (M2-M5)
- **Form.Blocks** (`core-forth/src/lithoglyph-blocks.fs`)
  - Fixed-size block storage layer
  - Block header structure with magic, version, type, checksums
  - Memory buffer management
  - CRC32C implementation (Castagnoli polynomial)

- **Form.Journal** (`core-forth/src/lithoglyph-journal.fs`)
  - Append-only journal implementation
  - Sequence numbering
  - Operation logging with inverses
  - Crash recovery primitives

- **Form.Model** (`core-forth/src/lithoglyph-model.fs`)
  - Document collection support
  - Edge collection support
  - Schema metadata storage
  - Constraint storage

- **Test Suite** (`core-forth/test/`)
  - Block operations tests
  - Journal operations tests
  - Model layer tests

#### Documentation
- Architecture guide (`ARCHITECTURE.adoc`)
- Roadmap (`ROADMAP.adoc`)
- Philosophy document (`PHILOSOPHY.adoc`)
- Contributing guidelines (`CONTRIBUTING.adoc`)
- Maintainers list (`MAINTAINERS.adoc`)

#### Ecosystem Integration
- Related projects documentation:
  - Lith Studio (zero-friction GUI)
  - Lith Debugger (proof-carrying debugger)
  - FormBase (Airtable alternative)
  - Zotero-Lith (reference manager)
  - FQLdt (dependently-typed GQL)

#### Machine-Readable Artefacts
- 6SCM files for AI agent integration:
  - `STATE.scm` - Project state tracking
  - `META.scm` - Architecture decisions
  - `ECOSYSTEM.scm` - Ecosystem position
  - `PLAYBOOK.scm` - Operational runbook
  - `AGENTIC.scm` - AI interaction patterns
  - `NEUROSYM.scm` - Neurosymbolic config

### Changed
- Eliminated C dependency in favor of Zig-only ABI (Form.Bridge)
- Consolidated FQLdt specification into single comprehensive document
- Clarified that GQL = Lith Query Language (not "forms" query language)

### Security
- Fixed workflow security issues (ERR-WF-008, ERR-WF-009)
- Updated actions/cache SHA from v2 to v4

---

## [0.0.1] - 2026-01-03

Initial release: **Repository Initialization**

### Added

#### Repository Structure
- Initial repository setup following RSR (Rhodium Standard Repositories) pattern
- Standard hyperpolymath/mustfile structure
- RSR enforcement workflows

#### Documentation Framework
- README.adoc with project overview
- Core thesis: "Schemas, constraints, migrations, blocks, and journals are narrative artefacts"
- Primary values table (Auditability > Performance, Meaning > Features, etc.)
- Target domains: investigative journalism, governance, agentic ecosystems, archives
- Layer architecture diagram

#### Licensing
- MPL-2.0 base license
- Palimpsest philosophy notice (ethical open source)

#### CI/CD
- GitHub Actions workflows for quality enforcement
- Casket-SSG GitHub Pages workflow
- Security scanning workflows

---

## Version History Summary

| Version | Date | Milestone | Key Features |
|---------|------|-----------|--------------|
| 2.0.0 | 2026-01-12 | **Feature-Complete** | All 18 milestones, distributed + analytics |
| 1.2.0 | 2026-01-12 | M18 Complete | Aggregations, time series, window functions, exports |
| 1.1.0 | 2026-01-12 | M17 Complete | Cluster, consensus, sharding, replication |
| 1.0.0 | 2026-01-12 | **Production** | First stable release, all M1-M16 complete |
| 0.0.10 | 2026-01-12 | M16 Complete | Config validation, health checks, graceful shutdown, readiness |
| 0.0.9 | 2026-01-12 | M15 Complete | Query cache, connection pool, batch ops, metrics |
| 0.0.8 | 2026-01-12 | M14 Complete | Property tests, fuzz testing, integration tests, E2E tests |
| 0.0.7 | 2026-01-12 | M13 Complete | Strapi, Directus, Ghost, Payload CMS integrations |
| 0.0.6 | 2026-01-12 | M12 Complete | ReScript client, PHP client, SDK generator |
| 0.0.5 | 2026-01-12 | M11 Complete | Multi-protocol API server, WebSocket subscriptions |
| 0.0.4 | 2026-01-12 | M8-M10 Complete | Query engine, normalizer, production hardening |
| 0.0.3 | 2026-01-12 | M7 Complete | Complete documentation suite, PMPL-1.0 license |
| 0.0.2 | 2026-01-11 | M1-M6 Complete | Full specs, Forth PoC, documentation |
| 0.0.1 | 2026-01-03 | Repository Init | Structure, licensing, CI/CD |

## Upgrade Notes

### Upgrading to 0.0.3

No breaking changes from 0.0.2. This release adds comprehensive documentation and changes the license to PMPL-1.0.

### Upgrading to 0.0.2

No breaking changes from 0.0.1. This release adds specifications and implementation.

### Pre-1.0 Warning

Lith is in pre-1.0 development. APIs, formats, and interfaces may change without deprecation warnings. See [VERSIONING.adoc](VERSIONING.adoc) for stability guarantees.

---

## Links

[Unreleased]: https://github.com/hyperpolymath/lithoglyph/compare/v2.0.0...HEAD
[2.0.0]: https://github.com/hyperpolymath/lithoglyph/compare/v1.2.0...v2.0.0
[1.2.0]: https://github.com/hyperpolymath/lithoglyph/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/hyperpolymath/lithoglyph/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/hyperpolymath/lithoglyph/compare/v0.0.10...v1.0.0
[0.0.10]: https://github.com/hyperpolymath/lithoglyph/compare/v0.0.9...v0.0.10
[0.0.9]: https://github.com/hyperpolymath/lithoglyph/compare/v0.0.8...v0.0.9
[0.0.8]: https://github.com/hyperpolymath/lithoglyph/compare/v0.0.7...v0.0.8
[0.0.7]: https://github.com/hyperpolymath/lithoglyph/compare/v0.0.6...v0.0.7
[0.0.6]: https://github.com/hyperpolymath/lithoglyph/compare/v0.0.5...v0.0.6
[0.0.5]: https://github.com/hyperpolymath/lithoglyph/compare/v0.0.4...v0.0.5
[0.0.4]: https://github.com/hyperpolymath/lithoglyph/compare/v0.0.3...v0.0.4
[0.0.3]: https://github.com/hyperpolymath/lithoglyph/compare/v0.0.2...v0.0.3
[0.0.2]: https://github.com/hyperpolymath/lithoglyph/compare/v0.0.1...v0.0.2
[0.0.1]: https://github.com/hyperpolymath/lithoglyph/releases/tag/v0.0.1

## Related Documentation

- [VERSIONING.adoc](VERSIONING.adoc) - Stability policy and version guarantees
- [ROADMAP.adoc](ROADMAP.adoc) - Planned features and milestones
- [QUICKSTART.adoc](QUICKSTART.adoc) - Getting started guide
- [ARCHITECTURE.adoc](ARCHITECTURE.adoc) - Technical architecture

## Changelog Conventions

This changelog follows these conventions:

- **Added** - New features
- **Changed** - Changes to existing functionality
- **Deprecated** - Features that will be removed in future versions
- **Removed** - Features that have been removed
- **Fixed** - Bug fixes
- **Security** - Security-related changes

Each release includes:
- Summary of the milestone achieved
- Detailed list of changes by category
- Breaking changes highlighted (when applicable)
- Upgrade notes (when applicable)
