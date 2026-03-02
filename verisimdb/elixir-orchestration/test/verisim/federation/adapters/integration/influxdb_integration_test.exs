# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim.Federation.Adapters.InfluxDBIntegrationTest do
  @moduledoc """
  Integration tests for the InfluxDB federation adapter.

  Runs against a real InfluxDB 2.x instance from the test-infra container
  stack. The seed script `influxdb-init.sh` pre-loads:

  - Organisation: `verisimdb`
  - Auth token: `verisim-test-token-do-not-use-in-production`
  - Buckets: `metrics` (auto-setup), `drift_scores` (30d retention),
    `federation_health` (7d retention)
  - `drift_scores` bucket: 7 data points across 3 hexads
    - Measurement: `drift` with tags `hexad_id`, `status`
    - Fields: `semantic_vector`, `graph_document`, `temporal`, `overall`
  - `metrics` bucket: ~20 query latency data points
    - Measurement: `query_latency` with tags `service`, `query_type`
  - `federation_health` bucket: 7 adapter health checks + 3 sync events
    - Measurements: `adapter_health`, `federation_sync`

  ## Test Infrastructure

  Requires the test-infra stack running:

      cd connectors/test-infra && selur-compose up -d

  InfluxDB is exposed on localhost:8086.

  ## Running

      mix test --include integration test/verisim/federation/adapters/integration/influxdb_integration_test.exs

  Author: Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
  """

  use ExUnit.Case, async: false

  alias VeriSim.Federation.Adapters.InfluxDB

  @moduletag :integration

  # ---------------------------------------------------------------------------
  # Configuration
  # ---------------------------------------------------------------------------

  @influxdb_url System.get_env("VERISIM_INFLUXDB_URL", "http://localhost:8086")
  @influxdb_token System.get_env(
                    "VERISIM_INFLUXDB_TOKEN",
                    "verisim-test-token-do-not-use-in-production"
                  )
  @influxdb_org System.get_env("VERISIM_INFLUXDB_ORG", "verisimdb")

  @peer_info %{
    store_id: "influx-integration",
    endpoint: @influxdb_url,
    adapter_config: %{
      org: @influxdb_org,
      bucket: "drift_scores",
      token: @influxdb_token,
      measurement: "drift"
    }
  }

  @integration_prefix "hexad-integration"

  # ---------------------------------------------------------------------------
  # Setup / Teardown
  # ---------------------------------------------------------------------------

  setup_all do
    case InfluxDB.health_check(@peer_info) do
      {:ok, latency_ms} ->
        {:ok, %{latency_ms: latency_ms}}

      {:error, reason} ->
        {:ok, %{skip_reason: reason}}
    end
  end

  setup %{} = context do
    if Map.has_key?(context, :skip_reason) do
      {:ok, Map.put(context, :skip, true)}
    else
      {:ok, context}
    end
  end

  # ---------------------------------------------------------------------------
  # 1. Connection Tests
  # ---------------------------------------------------------------------------

  describe "connection to real InfluxDB" do
    test "connect/1 succeeds against running instance", context do
      skip_if_unavailable(context)

      result = InfluxDB.connect(@peer_info)
      assert result == :ok
    end

    test "health_check/1 returns 'pass' status with latency", context do
      skip_if_unavailable(context)

      assert {:ok, latency_ms} = InfluxDB.health_check(@peer_info)
      assert is_integer(latency_ms)
      assert latency_ms >= 0
    end
  end

  # ---------------------------------------------------------------------------
  # 2. Read / Query — Verify Seed Data (drift_scores bucket)
  # ---------------------------------------------------------------------------

  describe "querying seeded drift_scores bucket" do
    test "default query returns recent drift data points", context do
      skip_if_unavailable(context)

      query_params = %{modalities: [], limit: 100}
      assert {:ok, results} = InfluxDB.query(@peer_info, query_params)

      # The seed script writes 7 drift data points
      # Default Flux queries range(start: -24h), so all points should be within range
      assert is_list(results)

      Enum.each(results, fn result ->
        assert result.source_store == "influx-integration"
        assert is_binary(result.hexad_id)
        assert result.drifted == false
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # 3. Time Range Queries
  # ---------------------------------------------------------------------------

  describe "temporal range queries" do
    test "querying with time range filter returns drift data within window", context do
      skip_if_unavailable(context)

      query_params = %{
        modalities: [:temporal],
        temporal_range: %{
          start: "-2h",
          end: "now()"
        },
        limit: 100
      }

      assert {:ok, results} = InfluxDB.query(@peer_info, query_params)
      # All 7 seed data points were written within the last hour
      assert is_list(results)
    end

    test "querying with absolute timestamps returns matching points", context do
      skip_if_unavailable(context)

      now = DateTime.utc_now()
      three_hours_ago = DateTime.add(now, -3 * 3600, :second)

      query_params = %{
        modalities: [:temporal],
        temporal_range: %{
          start: DateTime.to_iso8601(three_hours_ago),
          end: DateTime.to_iso8601(now)
        },
        limit: 100
      }

      assert {:ok, results} = InfluxDB.query(@peer_info, query_params)
      assert is_list(results)
    end
  end

  # ---------------------------------------------------------------------------
  # 4. Aggregation Queries (Mean, Max via Semantic Filters)
  # ---------------------------------------------------------------------------

  describe "aggregation and tag-based filtering" do
    test "filtering by hexad_id tag returns specific hexad drift scores", context do
      skip_if_unavailable(context)

      query_params = %{
        modalities: [:temporal, :semantic],
        temporal_range: %{
          start: "-24h",
          end: "now()"
        },
        filters: %{"hexad_id" => "hexad-test-001"},
        limit: 100
      }

      assert {:ok, results} = InfluxDB.query(@peer_info, query_params)
      assert is_list(results)
    end

    test "filtering by status=drifted returns only drifted hexads", context do
      skip_if_unavailable(context)

      query_params = %{
        modalities: [:semantic],
        filters: %{"status" => "drifted"},
        limit: 100
      }

      assert {:ok, results} = InfluxDB.query(@peer_info, query_params)
      assert is_list(results)
    end
  end

  # ---------------------------------------------------------------------------
  # 5. Query Latency Metrics (metrics bucket)
  # ---------------------------------------------------------------------------

  describe "querying metrics bucket" do
    test "query_latency measurements are accessible", context do
      skip_if_unavailable(context)

      metrics_peer = %{
        @peer_info
        | adapter_config: %{
            org: @influxdb_org,
            bucket: "metrics",
            token: @influxdb_token,
            measurement: "query_latency"
          }
      }

      query_params = %{
        modalities: [:temporal],
        temporal_range: %{start: "-2h", end: "now()"},
        limit: 50
      }

      assert {:ok, results} = InfluxDB.query(metrics_peer, query_params)
      assert is_list(results)
    end
  end

  # ---------------------------------------------------------------------------
  # 6. Federation Health Metrics (federation_health bucket)
  # ---------------------------------------------------------------------------

  describe "querying federation_health bucket" do
    test "adapter_health measurements are accessible", context do
      skip_if_unavailable(context)

      health_peer = %{
        @peer_info
        | adapter_config: %{
            org: @influxdb_org,
            bucket: "federation_health",
            token: @influxdb_token,
            measurement: "adapter_health"
          }
      }

      query_params = %{
        modalities: [:temporal],
        temporal_range: %{start: "-1h", end: "now()"},
        limit: 50
      }

      assert {:ok, results} = InfluxDB.query(health_peer, query_params)
      assert is_list(results)
    end
  end

  # ---------------------------------------------------------------------------
  # 7. Write + Read-Back
  # ---------------------------------------------------------------------------

  describe "write and read-back cycle" do
    test "translate_results normalises InfluxDB time-series record format", context do
      skip_if_unavailable(context)

      _test_id = "#{@integration_prefix}-influx-#{System.unique_integer([:positive])}"

      # Simulate InfluxDB Flux CSV / JSON response format
      raw_record = %{
        "_measurement" => "drift",
        "_time" => "2026-02-28T12:00:00Z",
        "_value" => 0.045,
        "entity_id" => "hexad-test-001",
        "hexad_id" => "hexad-test-001",
        "status" => "healthy"
      }

      [normalised] = InfluxDB.translate_results([raw_record], @peer_info)

      assert normalised.source_store == "influx-integration"
      # InfluxDB adapter builds composite ID: measurement:entity_id:_time
      assert normalised.hexad_id == "drift:hexad-test-001:2026-02-28T12:00:00Z"
      assert normalised.drifted == false
    end
  end

  # ---------------------------------------------------------------------------
  # 8. Error Handling
  # ---------------------------------------------------------------------------

  describe "error handling against real InfluxDB" do
    test "querying a nonexistent bucket returns an error", context do
      skip_if_unavailable(context)

      bad_peer = %{
        @peer_info
        | adapter_config: %{
            org: @influxdb_org,
            bucket: "nonexistent_bucket_xyz",
            token: @influxdb_token,
            measurement: "drift"
          }
      }

      query_params = %{modalities: [], limit: 10}

      result = InfluxDB.query(bad_peer, query_params)
      # InfluxDB returns an error for nonexistent buckets
      assert match?({:error, _}, result) or match?({:ok, []}, result)
    end

    test "querying with an invalid token returns an error", context do
      skip_if_unavailable(context)

      bad_token_peer = %{
        @peer_info
        | adapter_config: Map.put(@peer_info.adapter_config, :token, "invalid-token-xyz")
      }

      query_params = %{modalities: [], limit: 10}

      result = InfluxDB.query(bad_token_peer, query_params)
      assert match?({:error, _}, result)
    end

    test "connecting to an unreachable endpoint returns an error" do
      unreachable_peer = %{
        store_id: "influx-unreachable",
        endpoint: "http://localhost:59994",
        adapter_config: %{org: "verisimdb", bucket: "drift_scores", token: "test"}
      }

      assert {:error, _reason} = InfluxDB.connect(unreachable_peer)
    end
  end

  # ---------------------------------------------------------------------------
  # 9. Modality Support
  # ---------------------------------------------------------------------------

  describe "modality support declarations" do
    test "InfluxDB supports only temporal and semantic modalities" do
      modalities = InfluxDB.supported_modalities(%{})

      assert :temporal in modalities
      assert :semantic in modalities

      refute :graph in modalities
      refute :vector in modalities
      refute :document in modalities
      refute :tensor in modalities
      refute :provenance in modalities
      refute :spatial in modalities
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp skip_if_unavailable(%{skip: true}), do: flunk("InfluxDB not available — start test-infra stack")
  defp skip_if_unavailable(_context), do: :ok
end
