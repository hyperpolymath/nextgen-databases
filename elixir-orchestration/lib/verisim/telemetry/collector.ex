# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim.Telemetry.Collector do
  @moduledoc """
  ETS-backed telemetry event collector.

  Listens to `:telemetry` events emitted throughout VeriSimDB and aggregates
  them into counters, distributions, and rate metrics stored in ETS. This
  data powers the product insights reporter and the PanLL telemetry dashboard.

  ## Privacy guarantees

  - **Opt-in only**: telemetry collection must be explicitly enabled via
    `VERISIM_TELEMETRY=true` or application config `telemetry_enabled: true`
  - **No PII**: never captures query content, entity data, or user identifiers
  - **Aggregate only**: stores counts, sums, min/max — never individual records
  - **Local first**: all data stays on the machine until explicitly exported

  ## Collected metrics

  | Metric | Type | Source |
  |--------|------|--------|
  | query_count | counter | VQL executor |
  | query_duration_sum | sum | VQL executor |
  | query_duration_min/max | gauge | VQL executor |
  | modality_usage | counter map | VQL executor / query router |
  | query_pattern | counter map | VQL executor (SELECT/INSERT/DELETE/SEARCH/SHOW) |
  | drift_detected_count | counter | drift monitor |
  | drift_modality_breakdown | counter map | drift monitor |
  | normalise_count | counter | normaliser |
  | normalise_success_count | counter | normaliser |
  | federation_query_count | counter | federation resolver |
  | federation_peer_errors | counter map | federation resolver |
  | proof_type_usage | counter map | VQL-DT executor |
  | entity_created_count | counter | entity server |
  | entity_deleted_count | counter | entity server |
  """

  use GenServer
  require Logger

  @table :verisim_telemetry
  @reset_interval :timer.hours(24)
  @health_snapshot_interval :timer.seconds(10)
  @error_budget_reset_interval :timer.hours(1)

  # ── Public API ──────────────────────────────────────────────────────────

  @doc "Start the collector, optionally linked to a supervisor."
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Check whether telemetry collection is enabled."
  def enabled? do
    Application.get_env(:verisim, :telemetry_enabled, false) ||
      System.get_env("VERISIM_TELEMETRY") == "true"
  end

  @doc "Return a snapshot of all collected metrics as a map."
  def snapshot do
    if :ets.whereis(@table) != :undefined do
      @table
      |> :ets.tab2list()
      |> Enum.into(%{})
    else
      %{}
    end
  end

  @doc "Increment a counter metric by the given amount (default 1)."
  def increment(key, amount \\ 1) do
    if enabled?() and :ets.whereis(@table) != :undefined do
      :ets.update_counter(@table, key, {2, amount}, {key, 0})
    end
  end

  @doc "Record a distribution value (tracks count, sum, min, max)."
  def record_distribution(key, value) when is_number(value) do
    if enabled?() and :ets.whereis(@table) != :undefined do
      GenServer.cast(__MODULE__, {:record_distribution, key, value})
    end
  end

  @doc "Increment a counter within a counter map (e.g., modality usage)."
  def increment_map(map_key, sub_key, amount \\ 1) do
    if enabled?() and :ets.whereis(@table) != :undefined do
      composite_key = {map_key, sub_key}
      :ets.update_counter(@table, composite_key, {2, amount}, {composite_key, 0})
    end
  end

  @doc "Reset all collected metrics. Used for testing or periodic rollover."
  def reset do
    if :ets.whereis(@table) != :undefined do
      :ets.delete_all_objects(@table)
      :ok
    end
  end

  @doc "Return the collection start time (when metrics were last reset)."
  def collection_start do
    GenServer.call(__MODULE__, :collection_start)
  end

  # ── GenServer callbacks ─────────────────────────────────────────────────

  @impl true
  def init(_opts) do
    table = :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])

    if enabled?() do
      attach_handlers()
      Logger.info("[VeriSim.Telemetry.Collector] Telemetry collection ENABLED")
    else
      Logger.debug("[VeriSim.Telemetry.Collector] Telemetry collection disabled (opt-in)")
    end

    # Schedule periodic reset to prevent unbounded growth.
    Process.send_after(self(), :periodic_reset, @reset_interval)

    # Schedule periodic health snapshots (every 10s)
    if enabled?() do
      Process.send_after(self(), :health_snapshot, @health_snapshot_interval)
      Process.send_after(self(), :error_budget_reset, @error_budget_reset_interval)
    end

    {:ok, %{table: table, started_at: DateTime.utc_now()}}
  end

  @impl true
  def handle_cast({:record_distribution, key, value}, state) do
    count_key = {key, :count}
    sum_key = {key, :sum}
    min_key = {key, :min}
    max_key = {key, :max}

    :ets.update_counter(@table, count_key, {2, 1}, {count_key, 0})
    :ets.update_counter(@table, sum_key, {2, trunc(value * 1000)}, {sum_key, 0})

    # Min/max require compare-and-swap
    case :ets.lookup(@table, min_key) do
      [{^min_key, current}] when value < current / 1000 ->
        :ets.insert(@table, {min_key, trunc(value * 1000)})
      [] ->
        :ets.insert(@table, {min_key, trunc(value * 1000)})
      _ -> :ok
    end

    case :ets.lookup(@table, max_key) do
      [{^max_key, current}] when value > current / 1000 ->
        :ets.insert(@table, {max_key, trunc(value * 1000)})
      [] ->
        :ets.insert(@table, {max_key, trunc(value * 1000)})
      _ -> :ok
    end

    {:noreply, state}
  end

  @impl true
  def handle_call(:collection_start, _from, state) do
    {:reply, state.started_at, state}
  end

  @impl true
  def handle_info(:periodic_reset, state) do
    if enabled?() do
      Logger.info("[VeriSim.Telemetry.Collector] Periodic metric reset (24h rollover)")
      :ets.delete_all_objects(@table)
    end

    Process.send_after(self(), :periodic_reset, @reset_interval)
    {:noreply, %{state | started_at: DateTime.utc_now()}}
  end

  def handle_info(:health_snapshot, state) do
    capture_health_snapshot()
    Process.send_after(self(), :health_snapshot, @health_snapshot_interval)
    {:noreply, state}
  end

  def handle_info(:error_budget_reset, state) do
    if enabled?() and :ets.whereis(@table) != :undefined do
      # Reset error budget counters (hourly rolling window)
      :ets.insert(@table, {:error_budget_total, 0})

      @table
      |> :ets.tab2list()
      |> Enum.filter(fn
        {{:error_budget_by_type, _}, _} -> true
        _ -> false
      end)
      |> Enum.each(fn {key, _} -> :ets.insert(@table, {key, 0}) end)
    end

    Process.send_after(self(), :error_budget_reset, @error_budget_reset_interval)
    {:noreply, state}
  end

  # ── Health metrics snapshot ────────────────────────────────────────────

  @doc """
  Capture a point-in-time health snapshot: memory, process count, uptime.

  Called periodically (every 10s) by the collector GenServer to track
  system health without any PII or content data.
  """
  def capture_health_snapshot do
    if enabled?() and :ets.whereis(@table) != :undefined do
      # Memory metrics from :erlang.memory/0 (in bytes)
      memory = :erlang.memory()
      :ets.insert(@table, {:health_memory_total_bytes, memory[:total]})
      :ets.insert(@table, {:health_memory_processes_bytes, memory[:processes]})
      :ets.insert(@table, {:health_memory_ets_bytes, memory[:ets]})
      :ets.insert(@table, {:health_memory_binary_bytes, memory[:binary]})

      # Process count
      :ets.insert(@table, {:health_process_count, length(Process.list())})

      # Uptime in seconds
      {uptime_ms, _} = :erlang.statistics(:wall_clock)
      :ets.insert(@table, {:health_uptime_seconds, div(uptime_ms, 1000)})

      # Scheduler utilisation (1-second sample)
      :ets.insert(@table, {:health_scheduler_count, :erlang.system_info(:schedulers_online)})

      # Timestamp of last health check
      :ets.insert(@table, {:health_last_checked, DateTime.utc_now() |> DateTime.to_iso8601()})
    end
  end

  @doc """
  Record an error by type for error budget tracking.

  Error budget resets hourly. Tracks: timeout, connection_error,
  parse_error, proof_failure, federation_error, internal_error.
  """
  def record_error(error_type) when is_atom(error_type) do
    increment(:error_budget_total)
    increment_map(:error_budget_by_type, error_type)
  end

  # ── Telemetry event handlers ────────────────────────────────────────────

  defp attach_handlers do
    events = [
      # Query events
      {[:verisim, :query, :stop], &__MODULE__.handle_query_stop/4},
      {[:verisim, :query, :exception], &__MODULE__.handle_query_exception/4},

      # Entity events
      {[:verisim, :entity, :create], &__MODULE__.handle_entity_create/4},
      {[:verisim, :entity, :delete], &__MODULE__.handle_entity_delete/4},

      # Drift events
      {[:verisim, :drift, :detected], &__MODULE__.handle_drift_detected/4},
      {[:verisim, :drift, :normalized], &__MODULE__.handle_drift_normalized/4},

      # Federation events
      {[:verisim, :federation, :query], &__MODULE__.handle_federation_query/4},

      # Proof events
      {[:verisim, :proof, :verified], &__MODULE__.handle_proof_verified/4}
    ]

    Enum.each(events, fn {event, handler} ->
      handler_id = "verisim_collector_#{Enum.join(event, "_")}"
      :telemetry.attach(handler_id, event, handler, nil)
    end)
  end

  @doc false
  def handle_query_stop(_event, measurements, metadata, _config) do
    increment(:query_count)

    if duration = Map.get(measurements, :duration) do
      duration_ms = System.convert_time_unit(duration, :native, :millisecond)
      record_distribution(:query_duration, duration_ms)
    end

    if pattern = Map.get(metadata, :statement_type) do
      increment_map(:query_pattern, pattern)
    end

    if modalities = Map.get(metadata, :modalities) do
      Enum.each(List.wrap(modalities), fn modality ->
        increment_map(:modality_usage, modality)
      end)
    end
  end

  @doc false
  def handle_query_exception(_event, _measurements, _metadata, _config) do
    increment(:query_error_count)
  end

  @doc false
  def handle_entity_create(_event, _measurements, _metadata, _config) do
    increment(:entity_created_count)
  end

  @doc false
  def handle_entity_delete(_event, _measurements, _metadata, _config) do
    increment(:entity_deleted_count)
  end

  @doc false
  def handle_drift_detected(_event, _measurements, metadata, _config) do
    increment(:drift_detected_count)

    if modality = Map.get(metadata, :modality) do
      increment_map(:drift_modality_breakdown, modality)
    end
  end

  @doc false
  def handle_drift_normalized(_event, measurements, _metadata, _config) do
    increment(:normalise_count)

    if Map.get(measurements, :success, false) do
      increment(:normalise_success_count)
    end
  end

  @doc false
  def handle_federation_query(_event, _measurements, metadata, _config) do
    increment(:federation_query_count)

    if peer = Map.get(metadata, :peer) do
      if Map.get(metadata, :error) do
        increment_map(:federation_peer_errors, peer)
      end
    end
  end

  @doc false
  def handle_proof_verified(_event, _measurements, metadata, _config) do
    if proof_type = Map.get(metadata, :proof_type) do
      increment_map(:proof_type_usage, proof_type)
    end
  end
end
