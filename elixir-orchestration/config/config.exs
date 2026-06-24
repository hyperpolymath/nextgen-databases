# SPDX-License-Identifier: MPL-2.0

import Config

# VeriSim configuration
config :verisim,
  rust_core_url: "http://localhost:8080/api/v1",
  rust_core_timeout: 30_000

# Logger configuration
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :entity_id]

# Import environment-specific config
import_config "#{config_env()}.exs"
