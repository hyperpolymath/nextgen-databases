# Compilation Warnings Fixed - 2026-02-05

## Summary

Fixed all compilation warnings in Lithoglyph HTTP API application code.
Reduced from **16 warnings** to **0 application warnings**.

Remaining warnings (9) are all expected NIF interface warnings in `lib/lith_nif.ex`:
- These warn about `:lith_nif` module being undefined
- Cannot be fixed without compiling the Rust NIF code
- M10 PoC limitation - will be resolved in M14+

## Warnings Fixed

### 1. Undefined/Private Function Warnings (2 fixed)

**LithHttp.Geo.bbox_intersects?/2 is undefined or private**
- **Location:** `lib/lith_http_web/channels/journal_channel.ex:149`
- **Problem:** Function was private (defp) but called from another module
- **Fix:** Changed `defp` to `def` and added @doc
- **File:** `lib/lith_http/geo.ex:312-323`

**LithHttp.Lithoglyph.get_block/2 is undefined or private**
- **Location:** `lib/lith_http_web/controllers/api_controller.ex:236`
- **Problem:** Function not implemented in M10 PoC Lithoglyph NIF
- **Fix:** Replaced endpoint with NOT_IMPLEMENTED stub
- **File:** `lib/lith_http_web/controllers/api_controller.ex:226-231`

### 2. Unreachable Clause Warnings (14 fixed)

All `{:error, reason}` clauses in M10 PoC code that will never match because
the stub implementations always return `{:ok, ...}`.

**analytics_controller.ex** (4 clauses):
- Line 76: `query/2` - query_timeseries error clause
- Line 104: `aggregate/2` - aggregate error clause
- Line 127: `provenance/2` - get_timeseries_provenance error clause
- Line 157: `latest/2` - query_timeseries error clause

**geo_controller.ex** (3 clauses):
- Line 69: `query_bbox/2` - query_by_bbox error clause
- Line 101: `query_geometry/2` - query_by_geometry error clause
- Line 151: `provenance/2` - get_feature_provenance error clause

**jwt.ex** (1 clause):
- Line 115: `decode_and_verify/3` - Wrong pattern `{:error, _}` instead of `:error`
- **Fix:** Changed to correct pattern for Base.url_decode64/2 return value

**Fix Strategy:**
- Commented out unreachable error clauses with M10 PoC note
- Will be uncommented when Lithoglyph NIF is fully implemented
- Preserves error handling logic for future use

## Files Modified

1. `lib/lith_http/geo.ex` - Made bbox_intersects?/2 public
2. `lib/lith_http_web/controllers/api_controller.ex` - Stubbed get_block endpoint
3. `lib/lith_http_web/controllers/analytics_controller.ex` - Commented 4 error clauses
4. `lib/lith_http_web/controllers/geo_controller.ex` - Commented 3 error clauses
5. `lib/lith_http_web/auth/jwt.ex` - Fixed error pattern match

## Verification

```bash
# Clean build shows 0 application warnings
$ mix clean && mix compile 2>&1 | grep -v "lith_nif" | grep "warning:" | wc -l
0

# Tests still pass
$ mix test
Finished in 0.04 seconds (0.04s async, 0.00s sync)
2 tests, 0 failures
```

## Expected Warnings (M10 PoC Limitation)

The following warnings are **expected** and **cannot be fixed** without compiling Rust NIF:

```
warning: :lith_nif.version/0 is undefined
warning: :lith_nif.db_open/1 is undefined
warning: :lith_nif.db_close/1 is undefined
warning: :lith_nif.txn_begin/2 is undefined
warning: :lith_nif.txn_commit/1 is undefined
warning: :lith_nif.txn_abort/1 is undefined
warning: :lith_nif.apply/2 is undefined
warning: :lith_nif.schema/1 is undefined
warning: :lith_nif.journal/2 is undefined
```

These will be resolved in M14 when the Rust Lithoglyph implementation is integrated.
