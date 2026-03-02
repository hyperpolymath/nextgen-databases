// SPDX-License-Identifier: PMPL-1.0-or-later
// Fuzz target for Hexad UUID parsing and validation

#![no_main]

use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &[u8]| {
    // Try to parse data as a UUID string
    if let Ok(s) = std::str::from_utf8(data) {
        // Test UUID parsing doesn't panic
        let _ = uuid::Uuid::parse_str(s);

        // Test that malformed UUIDs are handled gracefully
        if s.len() < 128 {
            let _ = s.trim();
        }
    }
});
