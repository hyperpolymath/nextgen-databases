# CLAUDE.md - QuandleDB

## Project Overview

QuandleDB is a knot-theory database application wrapping Skein.jl.

- **Server**: Julia HTTP server (`server/serve.jl`) using HTTP.jl + JSON3.jl
- **Frontend**: ReScript + React SPA (`frontend/src/`)
- **Engine**: Skein.jl (path dependency at `../../Skein.jl`)

## Build Commands

```bash
# Frontend
cd frontend && deno task build

# Server
cd server && julia --project=. -e 'using Pkg; Pkg.instantiate()'
julia --project=server server/serve.jl data/knots.db --port 8080 --static public/
```

## API Endpoints

- `GET /api/knots` — list with filters (crossing_number, writhe, genus, name, limit, offset)
- `GET /api/knots/:name` — single knot detail
- `GET /api/statistics` — database stats and distributions

## Key Conventions

- Server is read-only (database mutations via Skein.jl REPL)
- Frontend uses standard React hooks (useReducer, useEffect), not full TEA
- JSON field names use snake_case (matching Skein.jl schema)
- ReScript files use SPDX headers
- SCM files in `.machine_readable/` ONLY

## Machine-Readable Artefacts

The following files in `.machine_readable/` contain structured project metadata:
- `STATE.scm` - Current project state and progress
- `META.scm` - Architecture decisions
- `ECOSYSTEM.scm` - Relationship to Skein.jl and ecosystem
