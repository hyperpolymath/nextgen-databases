# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim.Hypatia.PatternQuery do
  @moduledoc """
  Cross-repo pattern analytics for the Hypatia pipeline.

  Provides query functions over ingested scan data to identify patterns
  that appear across multiple repositories, track severity distributions,
  and detect temporal trends (scan-to-scan drift).

  ## Query Functions

  - `pipeline_health/0` — Overall pipeline status and metrics
  - `cross_repo_patterns/1` — Patterns appearing in N+ repos
  - `severity_distribution/0` — Severity breakdown across all scans
  - `category_distribution/0` — Category breakdown across all scans
  - `temporal_trends/1` — How a repo's scan results change over time
  - `repos_by_severity/1` — Repos ranked by severity count
  - `weakness_hotspots/0` — Files with highest weakness density
  """

  require Logger

  alias VeriSim.Hypatia.ScanIngester

  # ---------------------------------------------------------------------------
  # Pipeline Health
  # ---------------------------------------------------------------------------

  @doc """
  Returns overall pipeline health metrics.

  Example:
      %{
        total_scans: 289,
        total_weak_points: 3260,
        repos_scanned: 289,
        severity_distribution: %{"High" => 120, "Medium" => 2800, "Low" => 340},
        top_categories: [{"PanicPath", 1200}, {"UnsafeCode", 500}, ...]
      }
  """
  def pipeline_health do
    scans = ScanIngester.list_scans()

    all_weak_points = extract_all_weak_points(scans)

    %{
      total_scans: length(scans),
      total_weak_points: length(all_weak_points),
      repos_scanned: scans |> Enum.map(&get_in(&1, [:metadata, :repo_name])) |> Enum.uniq() |> length(),
      severity_distribution: severity_distribution(all_weak_points),
      top_categories: top_categories(all_weak_points, 10),
      average_weak_points_per_repo: safe_avg(length(all_weak_points), length(scans)),
      last_scan_timestamp: latest_timestamp(scans)
    }
  end

  # ---------------------------------------------------------------------------
  # Cross-Repo Patterns
  # ---------------------------------------------------------------------------

  @doc """
  Finds weakness patterns that appear across `min_repos` or more repositories.

  Returns a list of `{pattern_key, repo_count, repos}` tuples, sorted by
  repo count descending.

  The pattern key is `"category:severity"` (e.g., `"PanicPath:Medium"`).
  """
  def cross_repo_patterns(min_repos \\ 3) do
    scans = ScanIngester.list_scans()

    # Build pattern → [repo_names] map
    pattern_repos =
      scans
      |> Enum.flat_map(fn scan ->
        repo = get_in(scan, [:metadata, :repo_name]) || "unknown"
        weak_points = extract_weak_points(scan)

        weak_points
        |> Enum.map(fn wp ->
          category = wp["category"] || "unknown"
          severity = wp["severity"] || "unknown"
          pattern_key = "#{category}:#{severity}"
          {pattern_key, repo}
        end)
      end)
      |> Enum.group_by(fn {key, _} -> key end, fn {_, repo} -> repo end)
      |> Map.new(fn {key, repos} -> {key, Enum.uniq(repos)} end)

    pattern_repos
    |> Enum.filter(fn {_key, repos} -> length(repos) >= min_repos end)
    |> Enum.map(fn {key, repos} -> {key, length(repos), repos} end)
    |> Enum.sort_by(fn {_key, count, _repos} -> count end, :desc)
  end

  # ---------------------------------------------------------------------------
  # Severity Distribution
  # ---------------------------------------------------------------------------

  @doc """
  Returns a map of severity level → count across all scans.
  """
  def severity_distribution do
    ScanIngester.list_scans()
    |> extract_all_weak_points()
    |> severity_distribution()
  end

  defp severity_distribution(weak_points) do
    weak_points
    |> Enum.group_by(& &1["severity"])
    |> Map.new(fn {severity, items} -> {severity || "unknown", length(items)} end)
  end

  # ---------------------------------------------------------------------------
  # Category Distribution
  # ---------------------------------------------------------------------------

  @doc """
  Returns a map of category → count across all scans, sorted by count descending.
  """
  def category_distribution do
    ScanIngester.list_scans()
    |> extract_all_weak_points()
    |> Enum.group_by(& &1["category"])
    |> Map.new(fn {cat, items} -> {cat || "unknown", length(items)} end)
    |> Enum.sort_by(fn {_cat, count} -> count end, :desc)
  end

  # ---------------------------------------------------------------------------
  # Temporal Trends
  # ---------------------------------------------------------------------------

  @doc """
  Returns scan results for a specific repo over time, enabling drift detection.

  Each entry contains the scan timestamp and weak point count, sorted
  chronologically.
  """
  def temporal_trends(repo_name) when is_binary(repo_name) do
    ScanIngester.list_scans()
    |> Enum.filter(fn scan ->
      get_in(scan, [:metadata, :repo_name]) == repo_name
    end)
    |> Enum.map(fn scan ->
      %{
        hexad_id: scan[:hexad_id],
        timestamp: get_in(scan, [:metadata, :scan_timestamp]),
        weak_point_count: get_in(scan, [:metadata, :weak_point_count]) || 0,
        severity_counts: get_in(scan, [:metadata, :severity_counts]) || %{}
      }
    end)
    |> Enum.sort_by(& &1.timestamp)
  end

  # ---------------------------------------------------------------------------
  # Repos by Severity
  # ---------------------------------------------------------------------------

  @doc """
  Returns repos ranked by total weakness count for a given severity level.

  Useful for identifying which repos need the most attention.
  """
  def repos_by_severity(severity \\ "High") do
    ScanIngester.list_scans()
    |> Enum.map(fn scan ->
      repo = get_in(scan, [:metadata, :repo_name]) || "unknown"
      counts = get_in(scan, [:metadata, :severity_counts]) || %{}
      count = counts[severity] || 0
      {repo, count}
    end)
    |> Enum.filter(fn {_repo, count} -> count > 0 end)
    |> Enum.sort_by(fn {_repo, count} -> count end, :desc)
  end

  # ---------------------------------------------------------------------------
  # Weakness Hotspots
  # ---------------------------------------------------------------------------

  @doc """
  Returns files ranked by weakness density across all repos.

  Identifies the most problematic files in the entire ecosystem.
  """
  def weakness_hotspots do
    ScanIngester.list_scans()
    |> extract_all_weak_points()
    |> Enum.group_by(& &1["location"])
    |> Map.new(fn {location, items} ->
      {location || "unknown", %{count: length(items), categories: Enum.map(items, & &1["category"]) |> Enum.uniq()}}
    end)
    |> Enum.sort_by(fn {_loc, data} -> data.count end, :desc)
    |> Enum.take(50)
  end

  # ---------------------------------------------------------------------------
  # Private Helpers
  # ---------------------------------------------------------------------------

  defp extract_weak_points(scan) do
    # Weak points might be in the document body or the original report
    case scan do
      %{document: %{body: body}} when is_binary(body) ->
        # Parse weak points from the stored JSON report
        case Jason.decode(body) do
          {:ok, %{"assail_report" => %{"weak_points" => wps}}} -> wps
          {:ok, %{"weak_points" => wps}} -> wps
          _ -> []
        end

      _ ->
        []
    end
  end

  defp extract_all_weak_points(scans) do
    Enum.flat_map(scans, &extract_weak_points/1)
  end

  defp top_categories(weak_points, limit) do
    weak_points
    |> Enum.group_by(& &1["category"])
    |> Enum.map(fn {cat, items} -> {cat || "unknown", length(items)} end)
    |> Enum.sort_by(fn {_cat, count} -> count end, :desc)
    |> Enum.take(limit)
  end

  defp safe_avg(_total, 0), do: 0.0
  defp safe_avg(total, count), do: Float.round(total / count, 1)

  defp latest_timestamp(scans) do
    scans
    |> Enum.map(&get_in(&1, [:metadata, :scan_timestamp]))
    |> Enum.reject(&is_nil/1)
    |> Enum.sort(:desc)
    |> List.first()
  end
end
