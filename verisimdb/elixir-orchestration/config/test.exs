# SPDX-License-Identifier: PMPL-1.0-or-later

import Config

# Test configuration
config :verisim,
  rust_core_url: "http://localhost:8081/api/v1",
  rust_core_timeout: 5_000,
  orch_api_port: 0

config :logger, :console,
  level: :warning
