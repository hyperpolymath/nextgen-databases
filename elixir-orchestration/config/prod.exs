# SPDX-License-Identifier: MPL-2.0

import Config

# Production configuration
config :verisim,
  rust_core_url: System.get_env("VERISIM_RUST_CORE_URL") || "https://verisim-core:8080/api/v1",
  rust_core_timeout: 60_000

config :logger, :console,
  level: :info
