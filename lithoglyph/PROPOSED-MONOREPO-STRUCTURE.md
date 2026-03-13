# Proposed Lithoglyph Monorepo Structure

## Current State: 30 top-level directories (too many!)

## Proposed Clean Structure:

```
lithoglyph/
├── core/                          # Core database engine
│   ├── forth/                     # Form.Blocks, Form.Journal, Form.Model
│   ├── zig/                       # Form.Bridge (FFI layer)
│   └── factor/                    # Form.Runtime (GQL parser/executor)
│
├── extensions/                    # Optional extensions
│   ├── analytics/                 # Analytics module (Julia)
│   ├── geo/                       # Geospatial extension (Rust)
│   └── beam/                      # BEAM integration (Erlang)
│
├── normalizer/                    # Self-normalizing engine
│   ├── lean/                      # Lean 4 proofs
│   └── factor/                    # FD discovery algorithms
│
├── api/                           # HTTP/gRPC API servers
│   ├── http/                      # REST API
│   └── grpc/                      # gRPC service
│
├── control-plane/                 # Elixir/OTP control plane (optional)
│
├── clients/                       # Client libraries
│   ├── rust/
│   ├── javascript/
│   └── python/
│
├── integrations/                  # Third-party integrations
│   ├── postgres/
│   ├── kafka/
│   └── elasticsearch/
│
├── tools/                         # CLI tools and utilities
│   ├── cli/                       # Main CLI tool
│   ├── inspector/                 # Database inspector
│   └── migrator/                  # Migration tool
│
├── spec/                          # Specifications
│   ├── blocks.adoc
│   ├── journal.adoc
│   ├── gql.adoc
│   └── self-normalizing.adoc
│
├── docs/                          # Documentation
│   ├── guides/
│   ├── api-reference/
│   └── architecture/
│
├── examples/                      # Example code and demos
│
├── test-vectors/                  # Golden test vectors
│
└── .infrastructure/               # Repo infrastructure
    ├── ai-cli-crash-capture/
    ├── contractiles/
    └── licenses/
```

## Cleanup Actions:

1. **Merge duplicate core directories**:
   - `core-forth/` → `core/forth/`
   - `core-zig/` → `core/zig/`
   - `core-factor/` → `core/factor/`

2. **Delete old artifacts**:
   - `lith/` (old name)
   - `lith/` (old name)
   - `build/` (should be in .gitignore)
   - `ffi/` (duplicate of core/zig?)

3. **Reorganize extensions**:
   - `analytics/`, `geo/`, `beam/` → `extensions/`

4. **Move infrastructure**:
   - `ai-cli-crash-capture/` → `.infrastructure/`
   - `contractiles/` → `.infrastructure/`
   - `licenses/` → `.infrastructure/`

5. **Consolidate distributed**:
   - `distributed/` → `control-plane/distributed/` (if related)
   - OR keep separate if it's a distributed consensus system

## Benefits:

- **Clearer navigation**: 10-12 top-level dirs instead of 30
- **Logical grouping**: Core vs extensions vs tools
- **Easier to find things**: Everything has a clear place
- **Better for newcomers**: Can understand structure at a glance
