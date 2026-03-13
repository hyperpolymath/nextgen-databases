# Lithoglyph Monorepo Structure

This repository now contains multiple Lithoglyph components in a monorepo structure:

## Core Database
- `core-forth/` - Forth storage layer (Form.Blocks, Form.Journal, Form.Model)
- `core-zig/` - Zig FFI bridge (Form.Bridge)
- `core-factor/` - Factor runtime (GQL parser/planner/executor)
- `normalizer/` - Normalization engine with Lean 4 proofs

## Extensions
- `analytics/` - Analytics module (Julia)
- `geo/` - Geospatial extension (Rust + JSON)
- `beam/` - Erlang BEAM integration

## Related Repositories
- [lithoglyph-studio](https://github.com/hyperpolymath/lithoglyph-studio) - GUI + debugger
- [gql-dt](https://github.com/hyperpolymath/gql-dt) - Dependently-typed query language (Lean)
- [formbase](https://github.com/hyperpolymath/formbase) - Airtable alternative using Lithoglyph

## Archived (merged into monorepo)
- lithoglyph-analytics → `analytics/`
- lithoglyph-geo → `geo/`
- lithoglyph-beam → `beam/`
