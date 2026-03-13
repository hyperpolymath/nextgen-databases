# Lith SDK Generator

Code generator for Lith client SDKs.

## Overview

This tool generates type-safe client libraries from the Lith API specification. It supports multiple target languages and produces idiomatic code for each.

## Supported Languages

| Language | Status | Output |
|----------|--------|--------|
| ReScript | Complete | ES6 modules for Deno |
| PHP | Complete | PSR-18 compatible |

## Usage

```bash
# Build the generator
deno task build

# Generate ReScript SDK
deno task gen:rescript

# Generate PHP SDK
deno task gen:php

# Custom output directory
deno run --allow-read --allow-write src/Main.res.js rescript ./my-output
```

## Generated Code

### ReScript

- `Lith_Types.res` - Type definitions (enums, records)
- `Lith.res` - Client with all API methods

### PHP

- `Types.php` - Type definitions (enums, classes)
- `LithClient.php` - Client skeleton

## Architecture

```
src/
├── ApiSpec.res      # API specification (source of truth)
├── Generator.res    # Generator interface and helpers
├── ReScriptGen.res  # ReScript code generator
├── PhpGen.res       # PHP code generator
└── Main.res         # CLI entry point
```

## Adding a New Language

1. Create `<Language>Gen.res` implementing the generator
2. Add case to `Main.res` switch statement
3. Add task to `deno.json`

## Hand-Crafted vs Generated

The SDK generator produces basic clients. The hand-crafted clients in `clients/` include:

- Fluent query builders
- Better error handling
- Framework integrations (Laravel, Symfony, etc.)
- Comprehensive documentation

Use the generator for:
- Quick prototyping
- Keeping types in sync
- Starting point for new language support

## License

PMPL-1.0-or-later
