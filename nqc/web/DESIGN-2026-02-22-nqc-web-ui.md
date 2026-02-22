# NQC Web UI — Design Document

**Date:** 2026-02-22
**Repo:** `nextgen-databases/nqc/`
**Author:** Claude (with Jonathan D.A. Jewell)
**Status:** COMPLETE — 48 modules, 0 errors, 0 warnings. All features implemented.

---

## Overview

A companion web UI for the NQC (NextGen Query Client) Gleam REPL.
Built with **rescript-tea** (TEA architecture) and **cadre-router** (URL routing).
The Gleam REPL at `src/` is UNCHANGED — this is a standalone addition in `web/`.

## Architecture

```
web/
├── rescript.json          # ReScript 12 config, references local tea + cadre-router
├── deno.json              # Deno deps + tasks (npm specifiers for react, rescript)
├── setup.sh               # Creates symlinks for local ReScript packages
├── index.html             # HTML shell + all CSS (dark terminal theme)
├── serve.js               # DONE — Deno static file server (SPA fallback)
├── src/
│   ├── Database.res       # DONE — Profile type + VQL/GQL/KQL builtins (mirrors Gleam)
│   ├── Route.res          # DONE — Route type + URL parser (cadre-router)
│   ├── Msg.res            # DONE — Message variants + outputFormat/connectionState types
│   ├── Model.res          # DONE — Application state + init function
│   ├── Api.res            # DONE — HTTP commands (query, health) via CORS proxy
│   ├── Update.res         # DONE — Pure update function (all state transitions)
│   ├── Subs.res           # DONE — Subscriptions (currently none, placeholder)
│   ├── View.res           # DONE Top-level view dispatch by route
│   ├── App.res            # DONE TEA app wiring (MakeWithDispatch functor)
│   ├── Index.res          # DONE ReactDOM.render entry point
│   ├── Pages/
│   │   ├── Picker.res     # DONE Database picker — card grid with health dots
│   │   └── Query.res      # DONE Query interface — editor + results + format switch
│   └── Components/
│       ├── Header.res     # DONE — Nav bar with db badge, DT toggle, format tabs
│       ├── Editor.res     # DONE — Query textarea with Ctrl+Enter and history
│       ├── Results.res    # DONE — Table/JSON/CSV result renderer
│       └── Status.res     # DONE — Connection health dot indicator
├── proxy/
│   └── server.js          # DONE Deno CORS proxy (forwards to db ports)
```

## Key Decisions

### 1. MakeWithDispatch, not MakeSimple
`rescript-tea`'s `Tea_Html` module has NO element constructors (no `div`, `span`, etc.).
It expects JSX usage. Since JSX needs a `dispatch` function for event handlers,
we use `Tea_App.MakeWithDispatch` which passes `(model, dispatch)` to the view.

### 2. URL routing via init command
`cadre-router`'s `Tea_Router.listen` is set up once in the app's init command
via `Tea_Cmd.effect`. It fires `UrlChanged` messages on browser back/forward.
Programmatic navigation uses `Tea_Navigation.execute(Push(...))` directly.

### 3. CORS proxy pattern
Browser → localhost:4000 (Deno proxy) → localhost:808x (database engines).
The proxy maps `/api/:dbId/*` to the correct port based on database profiles.

### 4. Raw JSON responses
Database engines return heterogeneous JSON. We decode as `JSON.t` (raw)
and render client-side based on the format selector (Table/JSON/CSV).
The `Results.res` component auto-detects columns from the first row.

## Dependency Chain

```
nqc-web
  ├── rescript-tea (local: ../../developer-ecosystem/rescript-ecosystem/packages/web/tea)
  │   ├── @rescript/react (npm)
  │   ├── @rescript/core (npm)
  │   └── @proven/rescript-bindings (STUB — created by setup.sh)
  ├── @anthropics/cadre-router (local: ../../developer-ecosystem/rescript-ecosystem/cadre-router)
  │   ├── @rescript/react (npm)
  │   ├── @rescript/core (npm)
  │   └── rescript-wasm-runtime (STUB — created by setup.sh)
  ├── @rescript/core (npm via deno.json)
  └── @rescript/react (npm via deno.json)
```

`setup.sh` creates symlinks for local packages and stub rescript.json for transitive deps.

## API Contracts

### Query execution
```
POST /api/{dbId}{executePath}
Body: {"query": "SELECT ...", "dt": false}
Response: JSON (shape varies by engine)
```

### Health check
```
GET /api/{dbId}{healthPath}
Response: any 2xx = healthy
```

### Database ports
| DB | Port | Execute Path | Health Path |
|----|------|-------------|-------------|
| VQL (VeriSimDB) | 8080 | /vql/execute | /health |
| GQL (Lithoglyph) | 8081 | /gql/execute | /health |
| KQL (QuandleDB) | 8082 | /kql/execute | /health |

## How to Resume

If this session was interrupted, here's what remains:

### Files still TODO (as of writing):
1. `web/src/View.res` — Route-based view dispatch (calls Picker or Query page)
2. `web/src/App.res` — TEA MakeWithDispatch functor wiring + init command
3. `web/src/Index.res` — ReactDOM entry (render App into #root)
4. `web/src/Pages/Picker.res` — Database card grid (uses Status, fires SelectDatabase)
5. `web/src/Pages/Query.res` — Combines Editor + Results + error banner
6. `web/proxy/server.js` — Deno CORS proxy server
7. `web/serve.js` — Deno static file server for dev

### To implement each:

**View.res**: Simple pattern match on `model.route`:
  - `Picker` → `Picker.make(~model, ~dispatch)`
  - `Query(_)` → `Query.make(~model, ~dispatch)`
  - `NotFound` → 404 page inline

**App.res**: Use `Tea_App.MakeWithDispatch` with:
  - `type flags = unit`, `type model = Model.t`, `type msg = Msg.t`
  - `init` reads current URL via `Tea_Url.current()`, parses route, creates model
  - `init` returns health-check command + URL listener setup command
  - `update = Update.update`, `view = View.make`, `subscriptions = Subs.subscriptions`

**Index.res**: `ReactDOM.Client.createRoot(...)` → `root.render(<App />)`

**Picker.res**: Grid of cards, one per `Database.all`. Each card shows:
  - displayName, languageName badge, description
  - Port number, health status dot (from model.healthMap)
  - onClick dispatches `SelectDatabase(db.id)`

**Query.res**: Vertical layout:
  - Error banner (if model.error is Some)
  - Editor pane (Editor.make)
  - Results pane (Results.make)

**proxy/server.js**: Deno.serve on port 4000. Route `/api/:dbId/*` →
  extract dbId, look up port from hardcoded map, forward request, add CORS headers.

**serve.js**: Deno.serve on port 8000, serves `index.html` + static files.

## Build & Run

```bash
cd nextgen-databases/nqc/web
bash setup.sh          # One-time: install deps + symlink packages
deno task build        # Compile ReScript
deno task proxy &      # Start CORS proxy on :4000
deno task dev          # Serve web UI on :8000
```
