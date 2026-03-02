# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim.QueryPlannerConfig do
  @moduledoc """
  Configuration for query planner tuning.

  Supports three optimization modes:
  - :conservative - Worst-case estimates, prioritize correctness
  - :balanced - Historical averages, good for most workloads
  - :aggressive - Optimistic estimates, prioritize speed

  Can be set globally or per-modality.
  """

  use GenServer

  @type optimization_mode :: :conservative | :balanced | :aggressive

  @type config :: %{
    global_mode: optimization_mode(),
    modality_overrides: %{String.t() => optimization_mode()},
    statistics_weight: float(),  # How much to trust historical data (0.0-1.0)
    enable_adaptive: boolean(),  # Auto-tune based on query patterns
  }

  # Default configuration
  @default_config %{
    global_mode: :balanced,
    modality_overrides: %{
      # Vector searches are predictable → aggressive
      "VECTOR" => :aggressive,
      # Graph traversal is unpredictable → conservative
      "GRAPH" => :conservative,
      # Semantic ZKP verification is expensive → conservative
      "SEMANTIC" => :conservative,
    },
    statistics_weight: 0.7,  # 70% historical, 30% estimates
    enable_adaptive: true,
  }

  # === API ===

  @doc """
  Get optimization mode for a specific modality.
  Falls back to global mode if no override.
  """
  def get_mode_for_modality(modality) do
    config = get_config()
    Map.get(config.modality_overrides, modality, config.global_mode)
  end

  @doc """
  Set global optimization mode.
  """
  def set_global_mode(mode) when mode in [:conservative, :balanced, :aggressive] do
    GenServer.call(__MODULE__, {:set_global_mode, mode})
  end

  @doc """
  Set optimization mode for specific modality.
  """
  def set_modality_mode(modality, mode) when mode in [:conservative, :balanced, :aggressive] do
    GenServer.call(__MODULE__, {:set_modality_mode, modality, mode})
  end

  @doc """
  Enable/disable adaptive tuning.
  When enabled, system auto-adjusts based on query performance.
  """
  def set_adaptive(enabled) when is_boolean(enabled) do
    GenServer.call(__MODULE__, {:set_adaptive, enabled})
  end

  # === Selectivity Multipliers ===

  @doc """
  Get selectivity multiplier based on optimization mode.

  Conservative: Multiply by 2.0 (assume more results)
  Balanced: Multiply by 1.0 (use estimate as-is)
  Aggressive: Multiply by 0.5 (assume fewer results)
  """
  def selectivity_multiplier(mode) do
    case mode do
      :conservative -> 2.0
      :balanced -> 1.0
      :aggressive -> 0.5
    end
  end

  @doc """
  Get cost multiplier based on optimization mode.

  Conservative: Add safety buffer (1.5x)
  Balanced: Use estimate as-is (1.0x)
  Aggressive: Assume best case (0.8x)
  """
  def cost_multiplier(mode) do
    case mode do
      :conservative -> 1.5
      :balanced -> 1.0
      :aggressive -> 0.8
    end
  end

  # === Adaptive Tuning ===

  @doc """
  Record actual query performance for adaptive tuning.
  If estimates were consistently wrong, adjust mode automatically.
  """
  def record_performance(modality, estimated_cost, actual_cost, estimated_selectivity, actual_selectivity) do
    GenServer.cast(__MODULE__, {:record_performance, %{
      modality: modality,
      estimated_cost: estimated_cost,
      actual_cost: actual_cost,
      estimated_selectivity: estimated_selectivity,
      actual_selectivity: actual_selectivity,
      timestamp: DateTime.utc_now(),
    }})
  end

  # === GenServer Implementation ===

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, @default_config, name: __MODULE__)
  end

  @impl true
  def init(config) do
    # Load from persistent storage if available
    config = load_config_from_storage() || config
    {:ok, %{config: config, performance_history: []}}
  end

  @impl true
  def handle_call({:set_global_mode, mode}, _from, state) do
    new_config = %{state.config | global_mode: mode}
    persist_config(new_config)
    {:reply, :ok, %{state | config: new_config}}
  end

  @impl true
  def handle_call({:set_modality_mode, modality, mode}, _from, state) do
    new_overrides = Map.put(state.config.modality_overrides, modality, mode)
    new_config = %{state.config | modality_overrides: new_overrides}
    persist_config(new_config)
    {:reply, :ok, %{state | config: new_config}}
  end

  @impl true
  def handle_call({:set_adaptive, enabled}, _from, state) do
    new_config = %{state.config | enable_adaptive: enabled}
    persist_config(new_config)
    {:reply, :ok, %{state | config: new_config}}
  end

  @impl true
  def handle_call(:get_config, _from, state) do
    {:reply, state.config, state}
  end

  @impl true
  def handle_cast({:record_performance, perf}, state) do
    new_history = [perf | state.performance_history] |> Enum.take(1000)  # Keep last 1000

    # Adaptive tuning: adjust modes if estimates are consistently wrong
    new_state = if state.config.enable_adaptive do
      maybe_auto_tune(%{state | performance_history: new_history})
    else
      %{state | performance_history: new_history}
    end

    {:noreply, new_state}
  end

  # === Private Helpers ===

  defp get_config do
    GenServer.call(__MODULE__, :get_config)
  end

  defp maybe_auto_tune(state) do
    # Analyze last 50 queries for each modality
    recent = Enum.take(state.performance_history, 50)

    state.config.modality_overrides
    |> Enum.reduce(state, fn {modality, current_mode}, acc ->
      modality_perfs = Enum.filter(recent, &(&1.modality == modality))

      if length(modality_perfs) >= 10 do
        # Calculate average error
        avg_cost_error = calculate_average_error(modality_perfs, :cost)
        avg_selectivity_error = calculate_average_error(modality_perfs, :selectivity)

        # Adjust mode based on error patterns
        new_mode = case {avg_cost_error, avg_selectivity_error} do
          # Consistently underestimating → more conservative
          {error, _} when error < -0.3 -> shift_mode(current_mode, :more_conservative)
          # Consistently overestimating → more aggressive
          {error, _} when error > 0.3 -> shift_mode(current_mode, :more_aggressive)
          # Good estimates → keep current
          _ -> current_mode
        end

        if new_mode != current_mode do
          Logger.info("Adaptive tuning: #{modality} mode changed from #{current_mode} to #{new_mode}")
          update_modality_mode(acc, modality, new_mode)
        else
          acc
        end
      else
        acc
      end
    end)
  end

  defp calculate_average_error(performances, :cost) do
    performances
    |> Enum.map(fn p -> (p.estimated_cost - p.actual_cost) / p.actual_cost end)
    |> Enum.sum()
    |> Kernel./(length(performances))
  end

  defp calculate_average_error(performances, :selectivity) do
    performances
    |> Enum.map(fn p -> (p.estimated_selectivity - p.actual_selectivity) / p.actual_selectivity end)
    |> Enum.sum()
    |> Kernel./(length(performances))
  end

  defp shift_mode(:conservative, :more_conservative), do: :conservative
  defp shift_mode(:conservative, :more_aggressive), do: :balanced
  defp shift_mode(:balanced, :more_conservative), do: :conservative
  defp shift_mode(:balanced, :more_aggressive), do: :aggressive
  defp shift_mode(:aggressive, :more_conservative), do: :balanced
  defp shift_mode(:aggressive, :more_aggressive), do: :aggressive

  defp update_modality_mode(state, modality, new_mode) do
    new_overrides = Map.put(state.config.modality_overrides, modality, new_mode)
    new_config = %{state.config | modality_overrides: new_overrides}
    persist_config(new_config)
    %{state | config: new_config}
  end

  defp load_config_from_storage do
    path = config_storage_path()
    case File.read(path) do
      {:ok, content} ->
        try do
          :erlang.binary_to_term(content)
        rescue
          _ -> nil
        end
      {:error, _} -> nil
    end
  end

  defp persist_config(config) do
    path = config_storage_path()
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, :erlang.term_to_binary(config))
    :ok
  rescue
    e ->
      require Logger
      Logger.warning("Failed to persist config: #{inspect(e)}")
      :ok
  end

  defp config_storage_path do
    Path.join([System.tmp_dir!(), "verisimdb", "query_planner_config.bin"])
  end
end
