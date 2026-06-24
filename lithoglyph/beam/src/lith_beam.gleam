// SPDX-License-Identifier: MPL-2.0
// Lith BEAM - Main module

/// Re-export client API
pub fn version() -> #(Int, Int, Int) {
  lith_beam/client.version()
}
