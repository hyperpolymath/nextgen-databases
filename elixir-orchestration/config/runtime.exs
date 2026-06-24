# SPDX-License-Identifier: MPL-2.0

import Config

# Runtime configuration loaded at application start
# Read from env in all environments (dev, test, prod)
config :verisim,
  rust_core_url: System.get_env("VERISIM_RUST_CORE_URL") || "http://[::1]:8080/api/v1",
  rust_core_timeout: String.to_integer(System.get_env("VERISIM_RUST_CORE_TIMEOUT") || "30000")
