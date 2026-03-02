# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim.HealthChecker do
  @moduledoc """
  Periodic health checker for VeriSimDB orchestration layer.

  Probes the Rust core reachability, GenServer liveness, and ETS cache health.
  Reports status via telemetry events.
  """

  use GenServer
  require Logger

  alias VeriSim.RustClient

  @check_interval 30_000

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Get the latest health check result."
  def status do
    GenServer.call(__MODULE__, :status)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    state = %{
      rust_core: :unknown,
      entity_registry: :unknown,
      ets_cache: :unknown,
      last_checked: nil,
      check_count: 0
    }

    schedule_check()
    {:ok, state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, {:ok, state}, state}
  end

  @impl true
  def handle_info(:check, state) do
    rust_status = check_rust_core()
    registry_status = check_entity_registry()
    ets_status = check_ets_cache()

    new_state = %{state |
      rust_core: rust_status,
      entity_registry: registry_status,
      ets_cache: ets_status,
      last_checked: DateTime.utc_now(),
      check_count: state.check_count + 1
    }

    # Emit telemetry events
    :telemetry.execute(
      [:verisim, :health_check],
      %{duration: 0},
      %{
        rust_core: rust_status,
        entity_registry: registry_status,
        ets_cache: ets_status
      }
    )

    # Log warnings for unhealthy components
    if rust_status != :healthy do
      Logger.warning("Health check: Rust core is #{rust_status}")
    end

    if registry_status != :healthy do
      Logger.warning("Health check: Entity registry is #{registry_status}")
    end

    if ets_status != :healthy do
      Logger.warning("Health check: ETS cache is #{ets_status}")
    end

    schedule_check()
    {:noreply, new_state}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  # Private

  defp check_rust_core do
    case RustClient.get("/health", []) do
      {:ok, %{"status" => status}} when status in ["healthy", "degraded"] -> :healthy
      {:ok, _} -> :degraded
      {:error, _} -> :unreachable
    end
  rescue
    _ -> :unreachable
  end

  defp check_entity_registry do
    case Registry.count(VeriSim.EntityRegistry) do
      count when is_integer(count) -> :healthy
      _ -> :degraded
    end
  rescue
    _ -> :unavailable
  end

  defp check_ets_cache do
    case :ets.info(:verisim_rust_client_cache) do
      :undefined -> :unavailable
      info when is_list(info) -> :healthy
      _ -> :degraded
    end
  rescue
    _ -> :unavailable
  end

  defp schedule_check do
    Process.send_after(self(), :check, @check_interval)
  end
end
