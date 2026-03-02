// SPDX-License-Identifier: PMPL-1.0-or-later
//
// Fuzz target for the VQL parser.
// Run with: cargo +nightly fuzz run fuzz_vql_parser
//
// This fuzzer feeds arbitrary byte strings to the VQL parser to find
// panics, hangs, or memory safety issues. The parser should gracefully
// reject invalid input without crashing.

#![no_main]

use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &[u8]| {
    // Only attempt to parse valid UTF-8 strings — the VQL parser
    // operates on &str, not raw bytes.
    if let Ok(input) = std::str::from_utf8(data) {
        // Limit input size to prevent timeouts on extremely long strings
        if input.len() <= 4096 {
            // The parser should never panic on any valid UTF-8 input.
            // We don't care about the result — only that it doesn't crash.
            let _ = verisim_api::vql::parse(input);
        }
    }
});
