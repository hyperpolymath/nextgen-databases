# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim.Telemetry.Reporter do
  @moduledoc """
  Telemetry reporter — aggregates raw collector metrics into structured
  product development insights and exports them as JSON.

  ## Insight categories

  1. **Modality Heatmap** — which of the 8 octad modalities see real usage
  2. **Query Pattern Distribution** — read vs. write vs. drift vs. proof queries
  3. **Performance Summary** — query latency percentiles (from distribution)
  4. **Drift Report** — frequency, modality breakdown, normalisation success rate
  5. **Federation Health** — peer error rates
  6. **VQL-DT Adoption** — proof type usage distribution

  ## Privacy guarantees

  All data returned by this module is aggregate-only. No query content, entity
  data, or personally identifiable information is ever included. The reporter
  reads from the collector's ETS table, which itself only stores counters and
  distribution summaries.

  ## Usage

      # Full report as map
      VeriSim.Telemetry.Reporter.report()

      # JSON string for HTTP endpoint or PanLL
      VeriSim.Telemetry.Reporter.report_json()

      # Individual insight
      VeriSim.Telemetry.Reporter.modality_heatmap()
  """

  alias VeriSim.Telemetry.Collector

  @modalities ~w(graph vector tensor semantic document temporal provenance spatial)a

  @doc """
  Generate a full product insights report as a structured map.

  Returns a map with keys: `:meta`, `:modality_heatmap`, `:query_patterns`,
  `:performance`, `:drift`, `:federation`, `:proof_types`.
  """
  def report do
    snapshot = Collector.snapshot()
    started_at = safe_collection_start()

    %{
      meta: %{
        generated_at: DateTime.utc_now() |> DateTime.to_iso8601(),
        collection_started: started_at |> DateTime.to_iso8601(),
        telemetry_enabled: Collector.enabled?(),
        privacy_notice:
          "This report contains aggregate metrics only. " <>
          "No query content, entity data, or PII is included."
      },
      modality_heatmap: modality_heatmap(snapshot),
      query_patterns: query_patterns(snapshot),
      performance: performance_summary(snapshot),
      drift: drift_report(snapshot),
      federation: federation_health(snapshot),
      proof_types: proof_type_usage(snapshot),
      entities: entity_summary(snapshot),
      health: health_report(snapshot),
      error_budget: error_budget_report(snapshot)
    }
  end

  @doc "Generate the full report as a JSON string."
  def report_json do
    report() |> Jason.encode!(pretty: true)
  end

  @doc """
  Modality heatmap — shows how much each of the 8 octad modalities is used
  in queries. Helps identify which modalities are core to users vs. underused.
  """
  def modality_heatmap(snapshot \\ nil) do
    snapshot = snapshot || Collector.snapshot()

    usage_map =
      @modalities
      |> Enum.map(fn modality ->
        count = Map.get(snapshot, {:modality_usage, modality}, 0)
        {modality, count}
      end)
      |> Enum.into(%{})

    total = Enum.sum(Map.values(usage_map))

    percentages =
      if total > 0 do
        usage_map
        |> Enum.map(fn {mod, count} ->
          {mod, Float.round(count / total * 100, 1)}
        end)
        |> Enum.into(%{})
      else
        usage_map |> Enum.map(fn {mod, _} -> {mod, 0.0} end) |> Enum.into(%{})
      end

    %{
      counts: usage_map,
      percentages: percentages,
      total_modality_queries: total,
      most_used: most_used_modality(usage_map),
      least_used: least_used_modality(usage_map)
    }
  end

  @doc """
  Query pattern distribution — what kinds of queries are being run.
  Helps understand read-heavy vs. write-heavy vs. analytics workloads.
  """
  def query_patterns(snapshot \\ nil) do
    snapshot = snapshot || Collector.snapshot()

    patterns =
      snapshot
      |> Enum.filter(fn
        {{:query_pattern, _}, _} -> true
        _ -> false
      end)
      |> Enum.map(fn {{:query_pattern, pattern}, count} -> {pattern, count} end)
      |> Enum.into(%{})

    total = Map.get(snapshot, :query_count, 0)
    errors = Map.get(snapshot, :query_error_count, 0)

    %{
      total_queries: total,
      error_count: errors,
      error_rate: if(total > 0, do: Float.round(errors / total * 100, 2), else: 0.0),
      by_type: patterns
    }
  end

  @doc """
  Performance summary — query latency statistics derived from the
  distribution tracker in the collector. Shows count, average, min, max.
  """
  def performance_summary(snapshot \\ nil) do
    snapshot = snapshot || Collector.snapshot()

    count = Map.get(snapshot, {:query_duration, :count}, 0)
    sum_millis = Map.get(snapshot, {:query_duration, :sum}, 0) / 1000
    min_millis = Map.get(snapshot, {:query_duration, :min}, 0) / 1000
    max_millis = Map.get(snapshot, {:query_duration, :max}, 0) / 1000

    avg = if count > 0, do: Float.round(sum_millis / count, 2), else: 0.0

    %{
      query_count: count,
      avg_duration_ms: avg,
      min_duration_ms: Float.round(min_millis, 2),
      max_duration_ms: Float.round(max_millis, 2),
      total_duration_ms: Float.round(sum_millis, 2)
    }
  end

  @doc """
  Drift report — how often drift is detected, which modalities drift most,
  and how successful normalisation is at repairing it.
  """
  def drift_report(snapshot \\ nil) do
    snapshot = snapshot || Collector.snapshot()

    detected = Map.get(snapshot, :drift_detected_count, 0)
    normalised = Map.get(snapshot, :normalise_count, 0)
    normalise_success = Map.get(snapshot, :normalise_success_count, 0)

    modality_breakdown =
      snapshot
      |> Enum.filter(fn
        {{:drift_modality_breakdown, _}, _} -> true
        _ -> false
      end)
      |> Enum.map(fn {{:drift_modality_breakdown, mod}, count} -> {mod, count} end)
      |> Enum.into(%{})

    success_rate =
      if normalised > 0, do: Float.round(normalise_success / normalised * 100, 1), else: 0.0

    %{
      drift_detected_count: detected,
      normalise_attempts: normalised,
      normalise_success_count: normalise_success,
      normalise_success_rate: success_rate,
      modality_breakdown: modality_breakdown,
      most_drifted: most_drifted_modality(modality_breakdown)
    }
  end

  @doc """
  Federation health — tracks errors per federated peer to identify
  unreliable backends.
  """
  def federation_health(snapshot \\ nil) do
    snapshot = snapshot || Collector.snapshot()

    total = Map.get(snapshot, :federation_query_count, 0)

    peer_errors =
      snapshot
      |> Enum.filter(fn
        {{:federation_peer_errors, _}, _} -> true
        _ -> false
      end)
      |> Enum.map(fn {{:federation_peer_errors, peer}, count} -> {peer, count} end)
      |> Enum.into(%{})

    %{
      total_federation_queries: total,
      peer_errors: peer_errors
    }
  end

  @doc """
  Proof type usage — which VQL-DT proof types are used. Tracks adoption
  of dependent type features.
  """
  def proof_type_usage(snapshot \\ nil) do
    snapshot = snapshot || Collector.snapshot()

    types =
      snapshot
      |> Enum.filter(fn
        {{:proof_type_usage, _}, _} -> true
        _ -> false
      end)
      |> Enum.map(fn {{:proof_type_usage, proof_type}, count} -> {proof_type, count} end)
      |> Enum.into(%{})

    total = Enum.sum(Map.values(types))

    %{
      total_proofs: total,
      by_type: types,
      vql_dt_active: total > 0
    }
  end

  @doc "Entity creation/deletion summary."
  def entity_summary(snapshot \\ nil) do
    snapshot = snapshot || Collector.snapshot()

    %{
      created: Map.get(snapshot, :entity_created_count, 0),
      deleted: Map.get(snapshot, :entity_deleted_count, 0)
    }
  end

  @doc """
  Health report — system resource usage and uptime. Uses data from the
  periodic health snapshot (captured every 10 seconds by the collector).

  All values are aggregate system metrics — no PII, no query content.
  """
  def health_report(snapshot \\ nil) do
    snapshot = snapshot || Collector.snapshot()

    %{
      memory: %{
        total_bytes: Map.get(snapshot, :health_memory_total_bytes, 0),
        processes_bytes: Map.get(snapshot, :health_memory_processes_bytes, 0),
        ets_bytes: Map.get(snapshot, :health_memory_ets_bytes, 0),
        binary_bytes: Map.get(snapshot, :health_memory_binary_bytes, 0),
        total_mb: Float.round(Map.get(snapshot, :health_memory_total_bytes, 0) / 1_048_576, 1)
      },
      process_count: Map.get(snapshot, :health_process_count, 0),
      uptime_seconds: Map.get(snapshot, :health_uptime_seconds, 0),
      scheduler_count: Map.get(snapshot, :health_scheduler_count, 0),
      last_checked: Map.get(snapshot, :health_last_checked, nil)
    }
  end

  @doc """
  Error budget report — tracks error counts by type within a rolling
  1-hour window. Resets hourly. Used for reliability monitoring and SLO
  tracking.

  Error types: timeout, connection_error, parse_error, proof_failure,
  federation_error, internal_error.
  """
  def error_budget_report(snapshot \\ nil) do
    snapshot = snapshot || Collector.snapshot()

    total_errors = Map.get(snapshot, :error_budget_total, 0)
    total_queries = Map.get(snapshot, :query_count, 0)

    by_type =
      snapshot
      |> Enum.filter(fn
        {{:error_budget_by_type, _}, _} -> true
        _ -> false
      end)
      |> Enum.map(fn {{:error_budget_by_type, error_type}, count} -> {error_type, count} end)
      |> Enum.into(%{})

    error_rate =
      if total_queries > 0 do
        Float.round(total_errors / total_queries * 100, 3)
      else
        0.0
      end

    %{
      total_errors: total_errors,
      error_rate_percent: error_rate,
      by_type: by_type,
      budget_window: "1 hour (rolling)"
    }
  end

  # ── Private helpers ─────────────────────────────────────────────────────

  defp most_used_modality(usage_map) do
    case Enum.max_by(usage_map, fn {_, count} -> count end, fn -> {nil, 0} end) do
      {nil, _} -> nil
      {mod, 0} -> if Enum.all?(usage_map, fn {_, c} -> c == 0 end), do: nil, else: mod
      {mod, _} -> mod
    end
  end

  defp least_used_modality(usage_map) do
    nonzero = Enum.filter(usage_map, fn {_, count} -> count > 0 end)

    case nonzero do
      [] -> nil
      list -> list |> Enum.min_by(fn {_, count} -> count end) |> elem(0)
    end
  end

  defp most_drifted_modality(breakdown) do
    case Enum.max_by(breakdown, fn {_, count} -> count end, fn -> {nil, 0} end) do
      {nil, _} -> nil
      {mod, _} -> mod
    end
  end

  defp safe_collection_start do
    try do
      Collector.collection_start()
    catch
      :exit, _ -> DateTime.utc_now()
    end
  end
end
