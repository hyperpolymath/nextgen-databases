# Lithoglyph Studio - GUI + Debugger

This repository combines the Lithoglyph GUI and debugger tools:

## Components
- `studio/` - Main GUI application (zero-friction interface)
- `debugger/` - Proof-carrying database debugger (Lean 4 + Idris 2)

## Architecture
The debugger is integrated into the studio as a component, providing:
- Visual proof exploration
- Step-by-step query debugging
- Schema evolution verification
- Constraint explanation

## Related Repositories
- [lithoglyph](https://github.com/hyperpolymath/lithoglyph) - Core database (monorepo)
- [gql-dt](https://github.com/hyperpolymath/gql-dt) - Dependently-typed query language
- [formbase](https://github.com/hyperpolymath/formbase) - Airtable alternative

## Archived (merged into studio)
- lithoglyph-debugger → `debugger/`
