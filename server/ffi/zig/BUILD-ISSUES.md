# Build Issues (Zig 0.15.2)

## Current Blockers

### 1. Erlang NIF Headers Not Found
```
error: 'erl_nif.h' file not found
```

**Solution**: Install Erlang development package:
```bash
# Fedora
sudo dnf install erlang-devel

# Ubuntu
sudo apt-get install erlang-dev

# Or set ERTS_INCLUDE_DIR
export ERTS_INCLUDE_DIR=/usr/lib/erlang/erts-*/include
```

### 2. Lithoglyph Functions Not Public
```
error: 'lith_db_open' is not marked 'pub'
```

The `export` functions in Lithoglyph bridge.zig are C-exported but not Zig-public.

**Solution**: Either:
- Use C FFI to call them (via `@extern`)
- Add `pub` before `export` in Lithoglyph bridge.zig
- Link against compiled Lithoglyph library instead of importing source

### 3. Calling Convention API Change
```
error: union 'builtin.CallingConvention' has no member named 'C'
```

Zig 0.15.2 changed calling convention naming.

**Solution**: Check Lithoglyph compatibility with Zig 0.15.2.

## Workaround: Use C FFI

Instead of importing Lithoglyph as a module, we can link against it as a C library:

```zig
// Declare C functions
extern fn lith_db_open(
    path_ptr: [*]const u8,
    path_len: usize,
    opts_ptr: ?[*]const u8,
    opts_len: usize,
    out_db: *?*LithDb,
    out_err: *LithBlob,
) LithStatus;

// Use them directly
const status = lith_db_open(path.ptr, path.len, null, 0, &out_db, &out_err);
```

Then link:
```zig
lib.linkSystemLibrary("lith");
lib.addLibraryPath(.{ .cwd_relative = lithoglyph_path ++ "/zig-out/lib" });
```

## Status

- ✅ Idris2 ABI complete (formal proofs)
- ✅ Zig FFI structure complete (all 9 functions)
- ✅ Lithoglyph integration code written
- ❌ Build blocked by environment/API issues
- ⏸️ Paused pending resolution

## Next Steps

1. Install Erlang dev headers
2. Either fix Lithoglyph pub exports or use C FFI approach
3. Test Lithoglyph compatibility with Zig 0.15.2
4. Complete build and integration tests
