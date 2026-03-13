# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# bofig_ingest.exs — Elixir batch ingest for Docudactyl → Lithoglyph bridge
#
# Alternative to bofig-ingest.sh for environments with Elixir/BEAM available.
# Reads Docudactyl JSON output (pre-converted from Cap'n Proto via the Zig
# adapter) and POSTs to Lithoglyph's REST API with provenance tracking.
#
# Usage:
#   elixir bofig_ingest.exs <json_dir> --investigation <id> [options]
#
# Options:
#   --url URL              Lithoglyph API URL (default: https://localhost:8080)
#   --investigation ID     Investigation ID (required)
#   --run-id ID            Pipeline run ID (default: auto-generated)
#   --dry-run              Print records without POSTing
#   --concurrency N        Concurrent HTTP requests (default: 4)
#
# Prerequisites:
#   - Elixir 1.16+ with Mix
#   - JSON files produced by lith_adapter (or manually)

Mix.install([
  {:jason, "~> 1.4"},
  {:req, "~> 0.5"}
])

defmodule BofigIngest do
  @moduledoc """
  Batch ingest Docudactyl evidence records into Lithoglyph.

  Reads JSON evidence files (converted from Cap'n Proto StageResults by the
  Zig lith_adapter), deduplicates by SHA-256 hash, and POSTs to Lithoglyph's
  FDQL query endpoint with provenance metadata.
  """

  require Logger

  defstruct [
    :url,
    :investigation_id,
    :run_id,
    :json_dir,
    dry_run: false,
    concurrency: 4,
    # Counters
    total: 0,
    inserted: 0,
    deduplicated: 0,
    failed: 0
  ]

  # ── Entry Point ──────────────────────────────────────────────────────

  @doc "Parse CLI arguments and run the ingest pipeline."
  def main(args) do
    config = parse_args(args)
    validate_config!(config)

    Logger.info("Starting bofig ingest")
    Logger.info("  JSON directory:   #{config.json_dir}")
    Logger.info("  Investigation:    #{config.investigation_id}")
    Logger.info("  Run ID:           #{config.run_id}")
    Logger.info("  Lithoglyph URL:   #{config.url}")
    Logger.info("  Dry run:          #{config.dry_run}")
    Logger.info("  Concurrency:      #{config.concurrency}")

    json_files =
      config.json_dir
      |> Path.join("**/*.json")
      |> Path.wildcard()
      |> Enum.sort()

    total = length(json_files)
    Logger.info("Found #{total} JSON files")

    if total == 0 do
      Logger.info("Nothing to ingest.")
      System.halt(0)
    end

    # Process files with bounded concurrency.
    results =
      json_files
      |> Task.async_stream(
        fn file -> process_file(file, config) end,
        max_concurrency: config.concurrency,
        timeout: 30_000
      )
      |> Enum.reduce(
        %{total: total, inserted: 0, deduplicated: 0, failed: 0},
        fn
          {:ok, :inserted}, acc -> %{acc | inserted: acc.inserted + 1}
          {:ok, :deduplicated}, acc -> %{acc | deduplicated: acc.deduplicated + 1}
          {:ok, :dry_run}, acc -> %{acc | inserted: acc.inserted + 1}
          {:ok, {:failed, reason}}, acc ->
            Logger.warning("Ingest failed: #{reason}")
            %{acc | failed: acc.failed + 1}
          {:exit, reason}, acc ->
            Logger.error("Task crashed: #{inspect(reason)}")
            %{acc | failed: acc.failed + 1}
        end
      )

    # Print summary.
    Logger.info("─── Ingest Summary ───")
    Logger.info("  Total files:    #{results.total}")
    Logger.info("  Inserted:       #{results.inserted}")
    Logger.info("  Deduplicated:   #{results.deduplicated}")
    Logger.info("  Failed:         #{results.failed}")
    Logger.info("  Run ID:         #{config.run_id}")

    if results.failed > 0 do
      System.halt(1)
    end
  end

  # ── File Processing ──────────────────────────────────────────────────

  defp process_file(file, config) do
    case File.read(file) do
      {:ok, contents} ->
        case Jason.decode(contents) do
          {:ok, record} ->
            process_record(record, file, config)

          {:error, reason} ->
            {:failed, "JSON parse error in #{file}: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:failed, "Cannot read #{file}: #{inspect(reason)}"}
    end
  end

  defp process_record(record, file, config) do
    sha256 = Map.get(record, "sha256_hash", "")

    if config.dry_run do
      title = Map.get(record, "title", Path.basename(file, ".json"))
      IO.puts("--- #{title} ---")
      IO.puts(Jason.encode!(record, pretty: true))
      IO.puts("")
      :dry_run
    else
      # Deduplication check.
      case check_dedup(sha256, config) do
        :exists ->
          Logger.debug("DEDUP: #{sha256} already exists")
          :deduplicated

        :new ->
          insert_record(record, config)

        {:error, _reason} ->
          # Dedup check failed — proceed with insert (let the DB reject
          # if truly duplicate via unique constraint).
          insert_record(record, config)
      end
    end
  end

  # ── Deduplication ────────────────────────────────────────────────────

  defp check_dedup("", _config), do: :new
  defp check_dedup(nil, _config), do: :new

  defp check_dedup(sha256, config) do
    query = "SELECT sha256_hash FROM bofig_evidence WHERE sha256_hash = '#{escape_fdql(sha256)}' LIMIT 1"

    body = %{
      "fdql" => query
    }

    case Req.post("#{config.url}/query",
           json: body,
           connect_options: [timeout: 5_000],
           receive_timeout: 10_000
         ) do
      {:ok, %{status: 200, body: resp_body}} ->
        # Check if any rows were returned.
        rows = get_in(resp_body, ["data", "rows"]) || []

        if length(rows) > 0, do: :exists, else: :new

      {:ok, %{status: status}} ->
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  # ── Insertion ────────────────────────────────────────────────────────

  defp insert_record(record, config) do
    json_str = Jason.encode!(record)
    run_id = escape_fdql(config.run_id)

    fdql = """
    INSERT INTO bofig_evidence #{json_str}
    WITH PROVENANCE {
      actor: "docudactyl-pipeline",
      rationale: "Batch extraction run #{run_id}"
    }
    """

    body = %{
      "fdql" => fdql,
      "provenance" => %{
        "actor" => "docudactyl-pipeline",
        "rationale" => "Batch extraction run #{config.run_id}"
      }
    }

    case Req.post("#{config.url}/query",
           json: body,
           connect_options: [timeout: 5_000],
           receive_timeout: 15_000
         ) do
      {:ok, %{status: status}} when status in [200, 201] ->
        :inserted

      {:ok, %{status: status, body: resp_body}} ->
        error_msg = get_in(resp_body, ["error", "message"]) || "HTTP #{status}"
        {:failed, error_msg}

      {:error, reason} ->
        {:failed, inspect(reason)}
    end
  end

  # ── Helpers ──────────────────────────────────────────────────────────

  defp escape_fdql(str) when is_binary(str) do
    str
    |> String.replace("\\", "\\\\")
    |> String.replace("'", "\\'")
    |> String.replace("\"", "\\\"")
  end

  defp escape_fdql(_), do: ""

  # ── Argument Parsing ─────────────────────────────────────────────────

  defp parse_args(args) do
    {opts, positional} = parse_args_loop(args, [], [])

    json_dir = List.first(positional) || ""

    run_id =
      Keyword.get(opts, :run_id) ||
        "docudactyl-#{DateTime.utc_now() |> DateTime.to_iso8601(:basic) |> String.slice(0, 15)}-#{System.pid()}"

    %BofigIngest{
      url: Keyword.get(opts, :url, "https://localhost:8080"),
      investigation_id: Keyword.get(opts, :investigation, ""),
      run_id: run_id,
      json_dir: json_dir,
      dry_run: Keyword.get(opts, :dry_run, false),
      concurrency: Keyword.get(opts, :concurrency, 4)
    }
  end

  defp parse_args_loop([], opts, pos), do: {Enum.reverse(opts), Enum.reverse(pos)}

  defp parse_args_loop(["--url", val | rest], opts, pos),
    do: parse_args_loop(rest, [{:url, val} | opts], pos)

  defp parse_args_loop(["--investigation", val | rest], opts, pos),
    do: parse_args_loop(rest, [{:investigation, val} | opts], pos)

  defp parse_args_loop(["--run-id", val | rest], opts, pos),
    do: parse_args_loop(rest, [{:run_id, val} | opts], pos)

  defp parse_args_loop(["--concurrency", val | rest], opts, pos),
    do: parse_args_loop(rest, [{:concurrency, String.to_integer(val)} | opts], pos)

  defp parse_args_loop(["--dry-run" | rest], opts, pos),
    do: parse_args_loop(rest, [{:dry_run, true} | opts], pos)

  defp parse_args_loop(["--help" | _rest], _opts, _pos) do
    IO.puts("""
    bofig_ingest.exs — Elixir batch ingest for Docudactyl → Lithoglyph

    Usage:
      elixir bofig_ingest.exs <json_dir> --investigation <id> [options]

    Options:
      --url URL              Lithoglyph API URL (default: https://localhost:8080)
      --investigation ID     Investigation ID (required)
      --run-id ID            Pipeline run ID (default: auto-generated)
      --dry-run              Print records without POSTing
      --concurrency N        Concurrent HTTP requests (default: 4)
    """)

    System.halt(0)
  end

  defp parse_args_loop([arg | rest], opts, pos) do
    if String.starts_with?(arg, "-") do
      IO.puts(:stderr, "Unknown option: #{arg}")
      System.halt(1)
    else
      parse_args_loop(rest, opts, [arg | pos])
    end
  end

  defp validate_config!(%BofigIngest{json_dir: ""}) do
    IO.puts(:stderr, "ERROR: JSON directory required")
    System.halt(1)
  end

  defp validate_config!(%BofigIngest{investigation_id: ""}) do
    IO.puts(:stderr, "ERROR: Investigation ID required (--investigation)")
    System.halt(1)
  end

  defp validate_config!(%BofigIngest{json_dir: dir} = config) do
    unless File.dir?(dir) do
      IO.puts(:stderr, "ERROR: JSON directory not found: #{dir}")
      System.halt(1)
    end

    config
  end
end

# ── Run ────────────────────────────────────────────────────────────────

BofigIngest.main(System.argv())
