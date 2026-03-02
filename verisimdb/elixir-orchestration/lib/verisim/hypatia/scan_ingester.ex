# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim.Hypatia.ScanIngester do
  @moduledoc """
  Ingests panic-attack scan results and stores them as VeriSimDB hexad entities.

  Each scan report becomes an octad entity with:
  - **Document**: Full JSON report as searchable text
  - **Graph**: file → weakness → recommendation triples
  - **Temporal**: Scan timestamp (enables drift tracking across cycles)
  - **Vector**: Weakness description embeddings (for similarity search)
  - **Provenance**: Scanner identity, CI run origin, transformation chain
  - **Semantic**: Severity annotations, category tags

  ## Data Flow

      panic-attack assail (JSON)
              │
      ScanIngester.ingest_scan/1
              │
      ┌───────┴───────┐
      │  Octad Entity  │  ← Document, Graph, Temporal, Vector, Provenance, Semantic
      └───────┬───────┘
              │
      VeriSimDB storage
              │
      Hypatia VQL queries

  ## Usage

      # Ingest a single scan result
      {:ok, hexad_id} = ScanIngester.ingest_scan(scan_json)

      # Ingest all scans from verisimdb-data/scans/ directory
      {:ok, results} = ScanIngester.ingest_directory("/path/to/verisimdb-data/scans")

      # Ingest from a panic-attack JSON file
      {:ok, hexad_id} = ScanIngester.ingest_file("/path/to/scan.json")
  """

  require Logger

  alias VeriSim.RustClient

  @type scan_report :: %{
          optional(String.t()) => any()
        }

  @type weak_point :: %{
          optional(String.t()) => any()
        }

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Ingest a panic-attack scan result (decoded JSON map) into VeriSimDB.

  The scan report is expected to have an `assail_report` key containing:
  - `program_path` — path to the scanned repository
  - `language` — detected primary language
  - `frameworks` — detected frameworks
  - `weak_points` — list of weakness findings

  Returns `{:ok, hexad_id}` or `{:error, reason}`.
  """
  def ingest_scan(scan_report) when is_map(scan_report) do
    report = scan_report["assail_report"] || scan_report

    repo_name = extract_repo_name(report["program_path"])
    hexad_id = "scan:#{repo_name}:#{timestamp_id()}"

    hexad_input = build_hexad(hexad_id, repo_name, report)

    case RustClient.create_hexad(hexad_input) do
      {:ok, _result} ->
        Logger.info("Hypatia: ingested scan for #{repo_name} as #{hexad_id}")
        {:ok, hexad_id}

      {:error, reason} ->
        Logger.warning(
          "Hypatia: failed to ingest scan for #{repo_name} via Rust core, " <>
            "storing locally: #{inspect(reason)}"
        )

        # Fallback: store in ETS for local querying
        store_local(hexad_id, hexad_input)
        {:ok, hexad_id}
    end
  end

  def ingest_scan(_), do: {:error, :invalid_scan_format}

  @doc """
  Ingest a scan result from a JSON file on disk.

  Returns `{:ok, hexad_id}` or `{:error, reason}`.
  """
  def ingest_file(path) when is_binary(path) do
    case File.read(path) do
      {:ok, data} ->
        case Jason.decode(data) do
          {:ok, scan} -> ingest_scan(scan)
          {:error, reason} -> {:error, {:json_parse_error, reason}}
        end

      {:error, reason} ->
        {:error, {:file_read_error, reason}}
    end
  end

  @doc """
  Ingest all scan JSON files from a directory.

  Returns `{:ok, results}` where results is a list of
  `{filename, {:ok, hexad_id}}` or `{filename, {:error, reason}}`.
  """
  def ingest_directory(dir_path) when is_binary(dir_path) do
    case File.ls(dir_path) do
      {:ok, files} ->
        results =
          files
          |> Enum.filter(&String.ends_with?(&1, ".json"))
          |> Enum.map(fn file ->
            path = Path.join(dir_path, file)
            {file, ingest_file(path)}
          end)

        successful = Enum.count(results, fn {_, result} -> match?({:ok, _}, result) end)
        Logger.info("Hypatia: ingested #{successful}/#{length(results)} scan files from #{dir_path}")

        {:ok, results}

      {:error, reason} ->
        {:error, {:dir_read_error, reason}}
    end
  end

  @doc """
  Query all ingested scans. Returns locally stored scans when Rust core is unavailable.
  """
  def list_scans do
    ensure_ets_table()

    :ets.tab2list(:hypatia_scans)
    |> Enum.map(fn {id, data} -> Map.put(data, :hexad_id, id) end)
  end

  @doc """
  Get scan data for a specific repo name.
  """
  def get_scan(repo_name) when is_binary(repo_name) do
    ensure_ets_table()

    :ets.tab2list(:hypatia_scans)
    |> Enum.find(fn {_id, data} ->
      get_in(data, [:metadata, :repo_name]) == repo_name
    end)
    |> case do
      {id, data} -> {:ok, Map.put(data, :hexad_id, id)}
      nil -> {:error, :not_found}
    end
  end

  # ---------------------------------------------------------------------------
  # Private: Hexad Construction
  # ---------------------------------------------------------------------------

  defp build_hexad(hexad_id, repo_name, report) do
    weak_points = report["weak_points"] || []
    language = report["language"] || "unknown"
    frameworks = report["frameworks"] || []

    %{
      hexad_id: hexad_id,
      metadata: %{
        repo_name: repo_name,
        language: language,
        frameworks: frameworks,
        scan_timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
        weak_point_count: length(weak_points),
        severity_counts: count_severities(weak_points)
      },

      # Document modality: full report as searchable text
      document: %{
        title: "Panic-attack scan: #{repo_name}",
        body: build_document_body(repo_name, language, weak_points),
        content_type: "application/json"
      },

      # Graph modality: file → weakness → recommendation triples
      graph: %{
        triples: build_graph_triples(hexad_id, repo_name, weak_points)
      },

      # Temporal modality: scan timestamp for drift tracking
      temporal: %{
        timestamp: System.system_time(:millisecond),
        version: "scan-v1",
        event_type: "panic_attack_scan"
      },

      # Provenance modality: scanner and origin tracking
      provenance: %{
        source: "panic-attack",
        actor: "hypatia-scan-workflow",
        operation: "assail",
        input_path: report["program_path"]
      },

      # Semantic modality: type annotations and severity tags
      semantic: %{
        types: ["scan_result", "security_finding", "panic_attack_report"],
        tags: extract_categories(weak_points),
        severity_levels: Enum.map(weak_points, & &1["severity"]) |> Enum.uniq()
      },

      # Vector modality: embedding from weakness descriptions
      vector: %{
        text_for_embedding: build_embedding_text(weak_points),
        dimensions: nil
      }
    }
  end

  defp build_document_body(repo_name, language, weak_points) do
    weakness_text =
      weak_points
      |> Enum.map(fn wp ->
        "#{wp["severity"]} #{wp["category"]} in #{wp["location"]}: #{wp["description"]}"
      end)
      |> Enum.join("\n")

    """
    Repository: #{repo_name}
    Language: #{language}
    Weak Points: #{length(weak_points)}

    #{weakness_text}
    """
  end

  defp build_graph_triples(hexad_id, repo_name, weak_points) do
    repo_node = "repo:#{repo_name}"

    # repo → has_scan → scan (lists for JSON compatibility)
    base = [[repo_node, "has_scan", hexad_id]]

    # For each weak point: scan → has_weakness → weakness, weakness → in_file → file
    weakness_triples =
      weak_points
      |> Enum.with_index()
      |> Enum.flat_map(fn {wp, idx} ->
        weakness_id = "#{hexad_id}:wp:#{idx}"
        file = wp["location"] || "unknown"
        category = wp["category"] || "unknown"

        [
          [hexad_id, "has_weakness", weakness_id],
          [weakness_id, "in_file", "file:#{file}"],
          [weakness_id, "has_category", "category:#{category}"],
          [weakness_id, "has_severity", "severity:#{wp["severity"] || "unknown"}"]
        ]
      end)

    base ++ weakness_triples
  end

  defp build_embedding_text(weak_points) do
    weak_points
    |> Enum.map(fn wp ->
      "#{wp["category"]} #{wp["severity"]} #{wp["description"]}"
    end)
    |> Enum.join(" ")
    |> String.slice(0, 2000)
  end

  defp extract_categories(weak_points) do
    weak_points
    |> Enum.map(& &1["category"])
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp count_severities(weak_points) do
    weak_points
    |> Enum.group_by(& &1["severity"])
    |> Map.new(fn {severity, items} -> {severity, length(items)} end)
  end

  # ---------------------------------------------------------------------------
  # Private: Helpers
  # ---------------------------------------------------------------------------

  defp extract_repo_name(nil), do: "unknown"

  defp extract_repo_name(path) when is_binary(path) do
    path
    |> String.split("/")
    |> List.last()
    |> String.replace(~r/[^a-zA-Z0-9_-]/, "")
  end

  defp timestamp_id do
    DateTime.utc_now()
    |> DateTime.to_iso8601(:basic)
    |> String.replace(~r/[^0-9]/, "")
    |> String.slice(0, 14)
  end

  # ---------------------------------------------------------------------------
  # Private: Local ETS Storage (fallback when Rust core unavailable)
  # ---------------------------------------------------------------------------

  defp ensure_ets_table do
    case :ets.info(:hypatia_scans) do
      :undefined ->
        :ets.new(:hypatia_scans, [:named_table, :set, :public])

      _ ->
        :ok
    end
  end

  defp store_local(hexad_id, hexad_input) do
    ensure_ets_table()
    :ets.insert(:hypatia_scans, {hexad_id, hexad_input})
    :ok
  end
end
