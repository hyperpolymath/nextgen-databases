// SPDX-License-Identifier: CC-BY-SA-4.0
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
= Lithoglyph — extraction PARTIALLY DONE

The Lithoglyph database stack still lives *here*, in `nextgen-databases/lithoglyph/`.
Treat this directory as canonical for everything not listed as extracted below.

== Extracted

* Query language: `lithoglyph/gql-dt/` -> https://github.com/hyperpolymath/gnpl
  (squash-import `102c79e`, PR #4). *The copy here is no longer canonical.*

== Not extracted (still canonical here)

* Database core -> https://github.com/hyperpolymath/lithoglyphdb (reserved 2026-06-22;
  migration pending)
* Airtable-mode delivery -> https://github.com/hyperpolymath/glyphbase (reserved
  2026-06-22; migration pending)

== `core-factor/gql/` — superseded, will NOT be migrated

`RESITE-DATABASES-TO-OWN-REPOS.adoc` originally specified `gnpl` as `gql-dt/` *plus*
`core-factor/gql/` (5 Factor files: `gql.factor`, `lexer-tests.factor`,
`seam-tests.factor`, `storage-backend.factor`, `benchmarks.factor`). Only the first
path was ever moved — `gnpl` contains zero `.factor` files.

That is now the settled position, not an omission. `core-factor/gql/` was the
runtime/dynamic counterpart to GQL-dt's compile-time proofs. GNPL has since been
re-scoped as a *narration/projection* language that lowers to GQL-dt, which supersedes
the Factor implementation rather than migrating it. The Factor sources stay here as
legacy.

CAUTION: an earlier version of this file claimed the code had moved to a `lith`
monorepo. That was INCORRECT — no such consolidation was authorised and no `lith`
repo exists.
