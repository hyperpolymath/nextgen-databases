// SPDX-License-Identifier: PMPL-1.0-or-later
// Lith BEAM - Main module

/// Re-export client API
pub fn version() -> #(Int, Int, Int) {
  lith_beam/client.version()
}
