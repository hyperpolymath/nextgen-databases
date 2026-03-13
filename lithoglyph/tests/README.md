# Lith Test Suite

Comprehensive testing framework for Lith including property-based tests, fuzz testing, integration tests, and end-to-end tests.

## Test Categories

| Category | Directory | Purpose |
|----------|-----------|---------|
| Property | `tests/property/` | Property-based tests for GQL |
| Fuzz | `tests/fuzz/` | Fuzz testing for parser robustness |
| Integration | `tests/integration/` | CMS plugin integration tests |
| E2E | `tests/e2e/` | End-to-end API and sync tests |

## Quick Start

### Run All Tests

```bash
# Build all test suites
cd tests/property && npm run build
cd tests/fuzz && npm run build
cd tests/integration && npm run build
cd tests/e2e && npm run build

# Run all tests
deno task test:all
```

### Run Individual Suites

```bash
# Property-based tests
cd tests/property && deno task test

# Fuzz testing
cd tests/fuzz && deno task fuzz

# Integration tests
cd tests/integration && deno task test

# E2E tests (requires Lith server)
cd tests/e2e && deno task test
```

## Property-Based Tests

Property-based tests verify invariants that should hold for all inputs.

### Features

- Random GQL statement generation
- Structural property verification
- Configurable iteration count
- Seed-based reproducibility

### Running

```bash
cd tests/property
npm run build
deno task test
```

### Properties Tested

- SELECT statements have FROM clause
- INSERT statements have INTO and document
- UPDATE statements have SET and WHERE
- DELETE statements have WHERE clause
- All statements are non-empty
- Braces and quotes are balanced

## Fuzz Testing

Fuzz testing discovers edge cases and potential crashes through random input mutation.

### Features

- Multiple mutation strategies (bit flip, byte insert, dictionary, etc.)
- Corpus-based fuzzing with seed inputs
- Crash detection and interesting input collection
- Configurable duration and iterations

### Running

```bash
cd tests/fuzz
npm run build
deno task fuzz          # Standard run (10K iterations)
deno task fuzz:quick    # Quick run (1K iterations)
deno task fuzz:long     # Long run (100K iterations)
```

### Mutation Strategies

| Strategy | Description |
|----------|-------------|
| BitFlip | Flip random bits |
| ByteFlip | Flip random bytes |
| ByteInsert | Insert random bytes |
| ByteDelete | Delete random bytes |
| ByteReplace | Replace random bytes |
| TokenSplice | Splice tokens from corpus |
| Arithmetic | Add/subtract from bytes |
| Dictionary | Insert GQL keywords |

## Integration Tests

Integration tests verify CMS plugin functionality with mock servers.

### CMS Plugins Tested

- **Strapi** - Lifecycle hooks and sync
- **Directus** - Hook extension actions
- **Ghost** - Webhook events
- **Payload CMS** - Collection hooks

### Running

```bash
cd tests/integration
npm run build
deno task test

# Individual CMS tests
deno task test:strapi
deno task test:directus
deno task test:ghost
deno task test:payload
```

### Test Coverage

- Plugin initialization
- Create/Update/Delete sync
- Field exclusion
- Sync mode filtering
- API key authentication
- Provenance metadata
- Error handling

## End-to-End Tests

E2E tests verify complete workflows against a running Lith server.

### Prerequisites

```bash
# Start Lith server
cd /path/to/lith && ./lith serve

# Or use Docker
docker run -p 8080:8080 lith/lith
```

### Running

```bash
cd tests/e2e
npm run build

# All E2E tests
deno task test

# Individual suites
deno task test:api       # API tests
deno task test:sync      # Sync tests
deno task test:migration # Migration tests
```

### Test Suites

**API Suite:**
- Health check
- Collection CRUD
- Document CRUD
- Query with WHERE
- EXPLAIN query
- INTROSPECT schema

**Sync Suite:**
- Sync create/update/delete
- Provenance tracking
- Bidirectional sync
- Conflict resolution
- Batch sync

## Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `LITH_URL` | Lith server URL | `http://localhost:8080` |
| `LITH_API_KEY` | API key for authentication | None |
| `TEST_ITERATIONS` | Property test iterations | `100` |
| `FUZZ_ITERATIONS` | Fuzz test iterations | `10000` |
| `TEST_VERBOSE` | Enable verbose output | `false` |

### Test Configuration

```typescript
// Property test config
const config = {
  iterations: 100,
  seed: 12345,      // Optional for reproducibility
  maxShrinks: 100,
  verbose: true,
};

// Fuzz test config
const fuzzConfig = {
  iterations: 10000,
  maxInputLength: 1024,
  saveCorpus: true,
  corpusDir: "./corpus",
};

// E2E test config
const e2eConfig = {
  lithUrl: "http://localhost:8080",
  apiKey: "test-key",
  testPrefix: "e2e_test_",
};
```

## Writing New Tests

### Property Test

```rescript
let prop_myProperty = (input: string): bool => {
  // Return true if property holds
  String.length(input) > 0
}

let test_myProperty = () =>
  runProperty(
    ~config=defaultConfig,
    ~name="My property",
    ~generator=myGenerator,
    ~toString=s => s,
    ~property=prop_myProperty,
  )
```

### Integration Test

```rescript
let test_myIntegration = async (): testResult => {
  let client = makeMockLithClient()
  addResponse(client, { status: 200, body: ..., headers: ... })

  let response = await mockFetch(client, url, options)

  assertEqual(response.status, 200, "Should succeed")
}
```

### E2E Test

```rescript
let test_myE2E = async (env: testEnvironment): e2eResult => {
  let startTime = Js.Date.now()

  try {
    let client = makeHttpClient(env)
    let response = await client.post("/v1/query", body)

    assertE2E(response.success, "Should succeed", startTime)
  } catch {
  | _ => Failed({message: "Request failed", duration: ...})
  }
}
```

## CI Integration

### GitHub Actions

```yaml
name: Tests
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: denoland/setup-deno@v1
      - uses: actions/setup-node@v4

      - name: Build tests
        run: |
          cd tests/property && npm run build
          cd ../fuzz && npm run build
          cd ../integration && npm run build
          cd ../e2e && npm run build

      - name: Run property tests
        run: cd tests/property && deno task test

      - name: Run fuzz tests (quick)
        run: cd tests/fuzz && deno task fuzz:quick

      - name: Run integration tests
        run: cd tests/integration && deno task test
```

## Architecture

```
tests/
├── README.md              # This file
├── property/              # Property-based tests
│   ├── rescript.json
│   ├── deno.json
│   └── src/
│       ├── Lith_Property_Types.res
│       ├── Lith_Property_Generators.res
│       ├── Lith_Property_Runner.res
│       └── Lith_Property_GQL.res
├── fuzz/                  # Fuzz testing
│   ├── rescript.json
│   ├── deno.json
│   └── src/
│       ├── Lith_Fuzz_Types.res
│       ├── Lith_Fuzz_Mutators.res
│       ├── Lith_Fuzz_Runner.res
│       └── Lith_Fuzz_GQL.res
├── integration/           # Integration tests
│   ├── rescript.json
│   ├── deno.json
│   └── src/
│       ├── Lith_Integration_Types.res
│       ├── Lith_Integration_Mock.res
│       ├── Lith_Integration_Strapi.res
│       ├── Lith_Integration_Directus.res
│       ├── Lith_Integration_Ghost.res
│       └── Lith_Integration_Payload.res
└── e2e/                   # End-to-end tests
    ├── rescript.json
    ├── deno.json
    └── src/
        ├── Lith_E2E_Types.res
        ├── Lith_E2E_API.res
        └── Lith_E2E_Sync.res
```

## License

PMPL-1.0-or-later
