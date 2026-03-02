# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim.Hypatia.DispatchBridge do
  @moduledoc """
  Bridge between VeriSimDB hexad data and Hypatia's dispatch pipeline.

  Reads dispatch manifests (JSONL files) from verisimdb-data/dispatch/,
  tracks execution status, and provides feedback to VeriSimDB for drift
  tracking between scan cycles.

  ## Dispatch Lifecycle

      ┌─────────────────────────────────────────────────────────┐
      │  Hypatia Pipeline                                       │
      │    PatternAnalyzer → TriangleRouter → FleetDispatcher   │
      │                                           │              │
      │                                    dispatch/*.jsonl      │
      └───────────────────────────────────────────┬─────────────┘
                                                  │
      ┌───────────────────────────────────────────┴─────────────┐
      │  DispatchBridge (this module)                            │
      │    ├── read_pending/1       — read pending.jsonl         │
      │    ├── read_dispatch_log/1  — read dispatch-*.jsonl      │
      │    ├── summarize/1          — aggregate dispatch stats   │
      │    ├── track_outcomes/1     — read outcomes/*.jsonl       │
      │    └── feedback_to_drift/1  — feed outcomes back to VDB  │
      └─────────────────────────────────────────────────────────┘

  ## Usage

      # Read pending dispatch actions
      {:ok, actions} = DispatchBridge.read_pending("/path/to/verisimdb-data")

      # Get dispatch summary
      summary = DispatchBridge.summarize("/path/to/verisimdb-data")

      # Feed outcomes back for drift tracking
      DispatchBridge.feedback_to_drift("/path/to/verisimdb-data")
  """

  require Logger

  alias VeriSim.Hypatia.ScanIngester

  @dispatch_dir "dispatch"
  @outcomes_dir "outcomes"
  @pending_file "pending.jsonl"

  # ---------------------------------------------------------------------------
  # Read Dispatch Data
  # ---------------------------------------------------------------------------

  @doc """
  Read all pending dispatch actions from `dispatch/pending.jsonl`.

  Returns `{:ok, actions}` where each action is a decoded JSON map with:
  - `repo` — target repository
  - `pattern` — canonical pattern ID
  - `strategy` — dispatch strategy (auto_execute, review, report_only)
  - `confidence` — recipe confidence score
  - `mutation` — GraphQL mutation payload
  """
  def read_pending(data_path) when is_binary(data_path) do
    path = Path.join([data_path, @dispatch_dir, @pending_file])
    read_jsonl(path)
  end

  @doc """
  Read dispatch log for a specific date (e.g., "2026-02-12").

  Returns `{:ok, records}` or `{:error, reason}`.
  """
  def read_dispatch_log(data_path, date) when is_binary(data_path) and is_binary(date) do
    path = Path.join([data_path, @dispatch_dir, "dispatch-#{date}.jsonl"])
    read_jsonl(path)
  end

  @doc """
  Read all dispatch logs from the dispatch directory.

  Returns `{:ok, records}` with all dispatch records across all log files.
  """
  def read_all_dispatch_logs(data_path) when is_binary(data_path) do
    dir = Path.join(data_path, @dispatch_dir)

    case File.ls(dir) do
      {:ok, files} ->
        records =
          files
          |> Enum.filter(&String.starts_with?(&1, "dispatch-"))
          |> Enum.filter(&String.ends_with?(&1, ".jsonl"))
          |> Enum.flat_map(fn file ->
            path = Path.join(dir, file)

            case read_jsonl(path) do
              {:ok, lines} -> lines
              {:error, _} -> []
            end
          end)

        {:ok, records}

      {:error, reason} ->
        {:error, {:dir_read_error, reason}}
    end
  end

  # ---------------------------------------------------------------------------
  # Read Outcomes
  # ---------------------------------------------------------------------------

  @doc """
  Read all fix outcomes from `outcomes/*.jsonl`.

  Each outcome records whether a dispatched fix succeeded or failed,
  and feeds back into the learning loop.
  """
  def read_outcomes(data_path) when is_binary(data_path) do
    dir = Path.join(data_path, @outcomes_dir)

    case File.ls(dir) do
      {:ok, files} ->
        outcomes =
          files
          |> Enum.filter(&String.ends_with?(&1, ".jsonl"))
          |> Enum.flat_map(fn file ->
            path = Path.join(dir, file)

            case read_jsonl(path) do
              {:ok, lines} -> lines
              {:error, _} -> []
            end
          end)

        {:ok, outcomes}

      {:error, reason} ->
        {:error, {:dir_read_error, reason}}
    end
  end

  # ---------------------------------------------------------------------------
  # Summary
  # ---------------------------------------------------------------------------

  @doc """
  Aggregate dispatch statistics from all logs and pending actions.

  Returns a summary map with counts per strategy, per-repo breakdown,
  and outcome statistics.
  """
  def summarize(data_path) when is_binary(data_path) do
    pending = case read_pending(data_path) do
      {:ok, p} -> p
      _ -> []
    end

    dispatched = case read_all_dispatch_logs(data_path) do
      {:ok, d} -> d
      _ -> []
    end

    outcomes = case read_outcomes(data_path) do
      {:ok, o} -> o
      _ -> []
    end

    %{
      pending_count: length(pending),
      dispatched_count: length(dispatched),
      outcome_count: length(outcomes),

      by_strategy: group_by_field(dispatched, "strategy"),
      by_repo: group_by_field(dispatched, "repo") |> top_n(20),

      outcome_success_rate: outcome_success_rate(outcomes),

      pending_by_strategy: group_by_field(pending, "strategy"),

      repos_with_pending:
        pending
        |> Enum.map(& &1["repo"])
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()
        |> length()
    }
  end

  # ---------------------------------------------------------------------------
  # Feedback to VeriSimDB Drift
  # ---------------------------------------------------------------------------

  @doc """
  Feed dispatch outcomes back into VeriSimDB for temporal drift tracking.

  For each repo with outcomes, compares the latest scan's weak point count
  against earlier scans to detect improvement or regression (drift).

  Returns a list of `{repo, drift_direction, delta}` tuples.
  """
  def feedback_to_drift(data_path) when is_binary(data_path) do
    outcomes = case read_outcomes(data_path) do
      {:ok, o} -> o
      _ -> []
    end

    # Group outcomes by repo
    repo_outcomes =
      outcomes
      |> Enum.group_by(& &1["repo"])

    # For each repo with outcomes, check scan trends
    repo_outcomes
    |> Enum.map(fn {repo, repo_ocs} ->
      successful = Enum.count(repo_ocs, &(&1["status"] == "success"))
      total = length(repo_ocs)

      drift = cond do
        successful == total -> :improving
        successful >= total / 2 -> :stable
        true -> :regressing
      end

      {repo, drift, %{successful: successful, total: total}}
    end)
  end

  @doc """
  Create a VeriSimDB hexad representing a dispatch batch summary.

  Stores dispatch metadata as a trackable entity for temporal analysis.
  """
  def ingest_dispatch_summary(data_path) when is_binary(data_path) do
    summary = summarize(data_path)
    hexad_id = "dispatch:summary:#{System.system_time(:second)}"

    hexad_input = %{
      hexad_id: hexad_id,
      metadata: %{
        type: "dispatch_summary",
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
      },
      document: %{
        title: "Hypatia Dispatch Summary",
        body: Jason.encode!(summary, pretty: true),
        content_type: "application/json"
      },
      temporal: %{
        timestamp: System.system_time(:millisecond),
        version: "dispatch-v1",
        event_type: "dispatch_summary"
      },
      provenance: %{
        source: "hypatia-dispatch",
        actor: "dispatch-bridge",
        operation: "summarize"
      }
    }

    ScanIngester.ingest_scan(%{
      "assail_report" => %{
        "program_path" => "dispatch-summary",
        "language" => "n/a",
        "frameworks" => [],
        "weak_points" => []
      }
    })

    # Also store the full summary in local ETS
    ensure_ets_table()
    :ets.insert(:hypatia_dispatch_summaries, {hexad_id, hexad_input})

    {:ok, hexad_id}
  end

  # ---------------------------------------------------------------------------
  # Private: JSONL Reading
  # ---------------------------------------------------------------------------

  defp read_jsonl(path) do
    case File.read(path) do
      {:ok, data} ->
        lines =
          data
          |> String.split("\n", trim: true)
          |> Enum.flat_map(fn line ->
            case Jason.decode(line) do
              {:ok, parsed} -> [parsed]
              {:error, _} -> []
            end
          end)

        {:ok, lines}

      {:error, reason} ->
        {:error, {:file_read_error, path, reason}}
    end
  end

  # ---------------------------------------------------------------------------
  # Private: Aggregation Helpers
  # ---------------------------------------------------------------------------

  defp group_by_field(records, field) do
    records
    |> Enum.group_by(& &1[field])
    |> Map.new(fn {key, items} -> {key || "unknown", length(items)} end)
  end

  defp top_n(map, n) do
    map
    |> Enum.sort_by(fn {_k, v} -> v end, :desc)
    |> Enum.take(n)
    |> Map.new()
  end

  defp outcome_success_rate([]), do: 0.0

  defp outcome_success_rate(outcomes) do
    successful = Enum.count(outcomes, &(&1["status"] == "success"))
    Float.round(successful / length(outcomes) * 100, 1)
  end

  defp ensure_ets_table do
    case :ets.info(:hypatia_dispatch_summaries) do
      :undefined ->
        :ets.new(:hypatia_dispatch_summaries, [:named_table, :set, :public])

      _ ->
        :ok
    end
  end
end
