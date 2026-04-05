# QuandleDB NIF Scaffold

Minimal Elixir + Zig NIF package for BEAM integration of QuandleDB semantic APIs.

## What This Scaffold Provides

- Elixir wrapper module: `QuandleDBNif`
- NIF loader module: `QuandleDBNif.Native`
- Zig NIF library: `native/quandle_db_nif.zig`
- Mix aliases: `mix compile` and `mix test` run `nif.build` first

Current NIF functions are intentionally minimal shape-compatible stubs:

- `semantic_lookup/1`
- `semantic_equivalents/1`

These calls are now wired through the semantic FFI boundary and can pull live
data from the QuandleDB API:

- `GET /api/semantic/:name`
- `GET /api/semantic-equivalents/:name`

Runtime environment flags:

- `QDB_API_BASE_URL` (default: `http://127.0.0.1:8080`)
- `QDB_NIF_MODE`:
  - `live` => use live HTTP calls
  - any other value or unset => stub mode (safe default for local tests)

## Build and Test

```bash
cd beam
mix test
```

This compiles the Zig NIF into `priv/quandle_db_nif.so` (or platform equivalent)
and runs Elixir tests.

### Optional Live Integration Tests

Run NIF/API parity checks against a running QuandleDB server:

```bash
cd beam
QDB_LIVE_TEST_BASE_URL=http://127.0.0.1:8080 mix test
```

Optional knot override:

```bash
QDB_LIVE_TEST_BASE_URL=http://127.0.0.1:8080 QDB_LIVE_TEST_KNOT=4_1 mix test
```

When `QDB_LIVE_TEST_BASE_URL` is set, the Mix test alias starts the NIF in
`live` mode automatically.

## Next Wiring Step

Replace the HTTP host implementation in `native/quandle_db_nif.zig` with a
direct call path to a local semantic runtime (if you want to avoid network
round-trips inside the NIF process).
