// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <jonathan.jewell@open.ac.uk>
//
// Build script for the Lithoglyph BEAM NIF (Rust/Rustler).
//
// Configures the linker to find liblith.so (the core Zig FFI bridge).
// The library path can be set via:
//   - LITH_LIB_DIR environment variable
//   - Default: ../../ffi/zig/zig-out/lib (relative to this crate)

fn main() {
    // Allow the user to override the library search path
    let lib_dir = std::env::var("LITH_LIB_DIR").unwrap_or_else(|_| {
        // Default to the Zig FFI output directory (relative to crate root)
        let manifest_dir =
            std::env::var("CARGO_MANIFEST_DIR").expect("CARGO_MANIFEST_DIR not set");
        format!("{}/../../ffi/zig/zig-out/lib", manifest_dir)
    });

    println!("cargo:rustc-link-search=native={}", lib_dir);
    println!("cargo:rustc-link-lib=dylib=lith");

    // Re-run if the bridge header changes
    println!("cargo:rerun-if-changed=../../generated/abi/bridge.h");
    println!("cargo:rerun-if-env-changed=LITH_LIB_DIR");
}
