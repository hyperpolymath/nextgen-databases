# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim.DriftMonitor do
  @moduledoc """
  Drift Monitor - Coordinates drift detection across entities.

  This GenServer monitors the overall drift state of the system and
  coordinates normalization when drift exceeds thresholds.

  ## Drift Types

  - `:semantic_vector` - Embedding diverged from semantic content
  - `:graph_document` - Graph structure doesn't match document
  - `:temporal_consistency` - Version history inconsistencies
  - `:tensor` - Tensor representation diverged
  - `:schema` - Schema violations detected
  - `:quality` - Overall data quality issues

  ## Thresholds

  | Drift Type | Warning | Critical |
  |------------|---------|----------|
  | semantic_vector | 0.3 | 0.7 |
  | graph_document | 0.4 | 0.8 |
  | temporal | 0.2 | 0.6 |
  | tensor | 0.35 | 0.75 |
  | schema | 0.1 | 0.5 |
  | quality | 0.25 | 0.65 |
  """

  use GenServer
  require Logger

  alias VeriSim.{EntityServer, RustClient, Telemetry}

  # State structure
  defstruct [
    :drift_scores,
    :entity_drift,
    :last_sweep,
    :pending_normalizations,
    :config
  ]

  # Default configuration
  @default_config %{
    sweep_interval_ms: 60_000,
    max_concurrent_normalizations: 10,
    thresholds: %{
      semantic_vector: %{warning: 0.3, critical: 0.7},
      graph_document: %{warning: 0.4, critical: 0.8},
      temporal_consistency: %{warning: 0.2, critical: 0.6},
      tensor: %{warning: 0.35, critical: 0.75},
      schema: %{warning: 0.1, critical: 0.5},
      quality: %{warning: 0.25, critical: 0.65}
    }
  }

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Report a drift event for an entity.
  """
  def report_drift(entity_id, score, drift_type \\ :quality) do
    GenServer.cast(__MODULE__, {:report_drift, entity_id, score, drift_type})
  end

  @doc """
  Notify that an entity has changed.
  """
  def entity_changed(entity_id) do
    GenServer.cast(__MODULE__, {:entity_changed, entity_id})
  end

  @doc """
  Get the current drift status.
  """
  def status do
    GenServer.call(__MODULE__, :status)
  end

  @doc """
  Get drift history for an entity.
  """
  def entity_history(entity_id) do
    GenServer.call(__MODULE__, {:entity_history, entity_id})
  end

  @doc """
  Trigger a manual drift sweep.
  """
  def sweep do
    GenServer.cast(__MODULE__, :sweep)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    config = Keyword.get(opts, :config, @default_config)

    state = %__MODULE__{
      drift_scores: %{},
      entity_drift: %{},
      last_sweep: DateTime.utc_now(),
      pending_normalizations: MapSet.new(),
      config: config
    }

    schedule_sweep(config.sweep_interval_ms)

    Logger.info("DriftMonitor started with config: #{inspect(config)}")
    {:ok, state}
  end

  @impl true
  def handle_cast({:report_drift, entity_id, score, drift_type}, state) do
    Logger.debug("Drift reported for #{entity_id}: #{drift_type} = #{score}")

    # Emit telemetry event (aggregate counter only — no entity data captured).
    Telemetry.emit_drift_detected(drift_type)

    new_entity_drift =
      Map.update(
        state.entity_drift,
        entity_id,
        %{drift_type => score},
        &Map.put(&1, drift_type, score)
      )

    new_drift_scores =
      Map.update(state.drift_scores, drift_type, [score], &[score | Enum.take(&1, 99)])

    new_state = %{state |
      entity_drift: new_entity_drift,
      drift_scores: new_drift_scores
    }

    # Check if normalization is needed
    new_state = maybe_trigger_normalization(new_state, entity_id, score, drift_type)

    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:entity_changed, entity_id}, state) do
    # Mark entity for drift check on next sweep
    Logger.debug("Entity #{entity_id} changed, marking for drift check")
    {:noreply, state}
  end

  @impl true
  def handle_cast(:sweep, state) do
    new_state = perform_sweep(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    status = %{
      overall_health: calculate_overall_health(state),
      drift_by_type: summarize_drift_by_type(state),
      entities_with_drift: map_size(state.entity_drift),
      pending_normalizations: MapSet.size(state.pending_normalizations),
      last_sweep: state.last_sweep
    }
    {:reply, status, state}
  end

  @impl true
  def handle_call({:entity_history, entity_id}, _from, state) do
    history = Map.get(state.entity_drift, entity_id, %{})
    {:reply, history, state}
  end

  @impl true
  def handle_info(:sweep, state) do
    new_state = perform_sweep(state)
    schedule_sweep(state.config.sweep_interval_ms)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:normalization_complete, entity_id, result}, state) do
    Logger.info("Normalization complete for #{entity_id}: #{result}")

    new_pending = MapSet.delete(state.pending_normalizations, entity_id)

    new_entity_drift =
      if result == :success do
        Map.delete(state.entity_drift, entity_id)
      else
        state.entity_drift
      end

    {:noreply, %{state |
      pending_normalizations: new_pending,
      entity_drift: new_entity_drift
    }}
  end

  # Private Functions

  defp schedule_sweep(interval_ms) do
    Process.send_after(self(), :sweep, interval_ms)
  end

  defp perform_sweep(state) do
    Logger.debug("Performing drift sweep across #{map_size(state.entity_drift)} entities")

    # Check each entity that has reported drift
    new_state = state.entity_drift
      |> Enum.reduce(state, fn {entity_id, drift_scores}, acc ->
        # Check each drift type for this entity
        Enum.reduce(drift_scores, acc, fn {drift_type, score}, inner_acc ->
          # Re-evaluate thresholds (scores may have changed since last check)
          maybe_trigger_normalization(inner_acc, entity_id, score, drift_type)
        end)
      end)

    # Pull aggregate drift metrics from Rust core
    new_state =
      case RustClient.drift_status() do
        {:ok, rust_metrics} when is_list(rust_metrics) ->
          updated_scores =
            Enum.reduce(rust_metrics, new_state.drift_scores, fn metric, acc ->
              drift_type =
                case metric["drift_type"] do
                  "SemanticVectorDrift" -> :semantic_vector
                  "GraphDocumentDrift" -> :graph_document
                  "TemporalConsistencyDrift" -> :temporal_consistency
                  "TensorDrift" -> :tensor
                  "SchemaDrift" -> :schema
                  "QualityDrift" -> :quality
                  other ->
                    Logger.debug("Unknown drift type from Rust core: #{inspect(other)}")
                    nil
                end

              if drift_type do
                score = metric["current_score"] || 0.0
                Map.update(acc, drift_type, [score], &[score | Enum.take(&1, 99)])
              else
                acc
              end
            end)

          %{new_state | drift_scores: updated_scores}

        {:ok, _unexpected} ->
          # Non-list response (e.g. HTML from wrong server on port 8080)
          Logger.debug("DriftMonitor: Rust core returned unexpected response, skipping")
          new_state

        {:error, reason} ->
          Logger.warning("DriftMonitor: failed to fetch Rust core drift status: #{inspect(reason)}")
          new_state
      end

    %{new_state | last_sweep: DateTime.utc_now()}
  end

  defp maybe_trigger_normalization(state, entity_id, score, drift_type) do
    thresholds = state.config.thresholds[drift_type] || %{warning: 0.5, critical: 0.8}

    cond do
      score >= thresholds.critical and entity_id not in state.pending_normalizations ->
        Logger.warning("Critical drift for #{entity_id}, triggering normalization")
        trigger_normalization(state, entity_id)

      score >= thresholds.warning ->
        Logger.info("Warning drift for #{entity_id}: #{score}")
        state

      true ->
        state
    end
  end

  defp trigger_normalization(state, entity_id) do
    if MapSet.size(state.pending_normalizations) < state.config.max_concurrent_normalizations do
      # Start async normalization
      Task.start(fn ->
        result = case EntityServer.normalize(entity_id) do
          :ok -> :success
          _ -> :failure
        end
        send(__MODULE__, {:normalization_complete, entity_id, result})
      end)

      %{state | pending_normalizations: MapSet.put(state.pending_normalizations, entity_id)}
    else
      Logger.warning("Max concurrent normalizations reached, deferring #{entity_id}")
      state
    end
  end

  defp calculate_overall_health(state) do
    if map_size(state.entity_drift) == 0 do
      :healthy
    else
      max_score =
        state.entity_drift
        |> Map.values()
        |> Enum.flat_map(&Map.values/1)
        |> Enum.max(fn -> 0.0 end)

      cond do
        max_score >= 0.8 -> :critical
        max_score >= 0.5 -> :degraded
        max_score >= 0.3 -> :warning
        true -> :healthy
      end
    end
  end

  defp summarize_drift_by_type(state) do
    state.drift_scores
    |> Enum.map(fn {type, scores} ->
      avg = if length(scores) > 0, do: Enum.sum(scores) / length(scores), else: 0.0
      {type, %{average: avg, max: Enum.max(scores, fn -> 0.0 end), count: length(scores)}}
    end)
    |> Map.new()
  end
end
