# This Repository Has Moved

**GQLdt is now part of the [Lithoglyph monorepo](https://github.com/hyperpolymath/lith).**

## New Location

- **Monorepo:** https://github.com/hyperpolymath/lith
- **Query Language:** https://github.com/hyperpolymath/lith/tree/main/query

## Why the Move?

GQLdt (Lithoglyph Query Language with dependent types) is the query interface for Lithoglyph. To improve discoverability and maintenance, we've consolidated the Lithoglyph ecosystem into a single monorepo:

```
lith/
├── query/          # GQLdt (this repo)
├── database/       # Form.Model + Form.Blocks (Forth core)
├── bridge/         # Zig FFI bridge
├── studio/         # Web-based GUI
└── debugger/       # Proof-carrying debugger
```

## Benefits of the Monorepo

- **Single source of truth** for all Lithoglyph components
- **Coordinated versioning** across query language, database, and tools
- **Unified documentation** and examples
- **Shared CI/CD** and dependency management
- **Easier cross-component refactoring**

## Migration Guide

### For Users

Update your imports/dependencies:

**Before:**
```bash
git clone https://github.com/hyperpolymath/gql-dt
```

**After:**
```bash
git clone https://github.com/hyperpolymath/lith
cd lith/query
```

### For Contributors

Submit PRs to the [lith monorepo](https://github.com/hyperpolymath/lith) instead.

## This Repository's Future

This repository (`gql-dt`) will be archived and remain as a historical reference. All active development happens in the monorepo.

---

**See you at [github.com/hyperpolymath/lith](https://github.com/hyperpolymath/lith)!** 🚀
