# SPDX-License-Identifier: MPL-2.0

import Config

# Test configuration
config :verisim,
  rust_core_url: "http://localhost:8081/api/v1",
  rust_core_timeout: 5_000,
  orch_api_port: 0

config :logger, :console,
  level: :warning
