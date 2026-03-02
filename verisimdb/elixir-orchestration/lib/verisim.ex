# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim do
  @moduledoc """
  VeriSim Orchestration - Elixir/OTP coordination layer for VeriSimDB.

  This module provides high-level orchestration for the VeriSimDB database,
  coordinating between the Rust core and managing distributed operations.

  ## Architecture

  ```
  ┌─────────────────────────────────────────────────────────────┐
  │  Elixir Orchestration Layer                                 │
  │    ├── VeriSim.EntityServer (GenServer per entity)          │
  │    ├── VeriSim.DriftMonitor (drift detection coordinator)   │
  │    ├── VeriSim.QueryRouter (distributes queries)            │
  │    └── VeriSim.SchemaRegistry (type system coordinator)     │
  │              ↓ HTTP/gRPC                                    │
  ├─────────────────────────────────────────────────────────────┤
  │  Rust Core (verisim-api)                                    │
  │    ├── 6 modality stores                                    │
  │    ├── Hexad management                                     │
  │    └── Normalizer                                           │
  └─────────────────────────────────────────────────────────────┘
  ```

  ## Design Philosophy (Marr's Three Levels)

  - **Computational Level**: What problem are we solving?
    → Maintain cross-modal consistency across 6 representations

  - **Algorithmic Level**: How do we solve it?
    → OTP supervision trees for fault tolerance
    → Process-per-entity for isolation
    → Event-driven drift detection

  - **Implementational Level**: How is it built?
    → Elixir/OTP for coordination
    → Rust for performance-critical operations
    → HTTP API for communication
  """

  @doc """
  Get the current VeriSim version.
  """
  def version, do: "0.1.0"

  @doc """
  Health check - returns system status.
  """
  def health do
    %{
      status: :healthy,
      version: version(),
      rust_core: rust_core_status(),
      uptime_seconds: System.monotonic_time(:second)
    }
  end

  defp rust_core_status do
    case VeriSim.RustClient.health() do
      {:ok, status} -> status
      {:error, _} -> %{status: :unavailable}
    end
  end
end
