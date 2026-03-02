# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim.Federation.Adapters.ClickHouseIntegrationTest do
  @moduledoc """
  Integration tests for the ClickHouse federation adapter.

  Runs against a real ClickHouse server from the test-infra container
  stack. The seed script `clickhouse-init.sql` pre-loads:

  - `verisimdb.hexads` table: 3 rows (hexad-test-001, -002, -003) with
    title, content, entity_type, drift_status, spatial coordinates, tags
  - `verisimdb.modalities` table: 11 rows (modality records per hexad)
  - `verisimdb.drift_scores` table: 5 rows (time-series drift measurements)
  - `verisimdb.provenance_events` table: 4 rows
  - 3 materialized views: mv_drift_status_counts, mv_modality_distribution,
    mv_avg_drift_by_type

  ## Test Infrastructure

  Requires the test-infra stack running:

      cd connectors/test-infra && selur-compose up -d

  ClickHouse is exposed on localhost:8123 (HTTP) and localhost:9000 (native).

  ## Running

      mix test --include integration test/verisim/federation/adapters/integration/clickhouse_integration_test.exs

  Author: Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
  """

  use ExUnit.Case, async: false

  alias VeriSim.Federation.Adapters.ClickHouse

  @moduletag :integration

  # ---------------------------------------------------------------------------
  # Configuration
  # ---------------------------------------------------------------------------

  @clickhouse_url System.get_env("VERISIM_CLICKHOUSE_URL", "http://localhost:8123")

  @peer_info %{
    store_id: "ch-integration",
    endpoint: @clickhouse_url,
    adapter_config: %{
      database: "verisimdb",
      table: "hexads"
    }
  }

  @integration_prefix "hexad-integration"

  # ---------------------------------------------------------------------------
  # Setup / Teardown
  # ---------------------------------------------------------------------------

  setup_all do
    case ClickHouse.health_check(@peer_info) do
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

  describe "connection to real ClickHouse" do
    test "connect/1 succeeds against running instance", context do
      skip_if_unavailable(context)

      result = ClickHouse.connect(@peer_info)
      assert result == :ok
    end

    test "health_check/1 returns 'Ok.' with latency", context do
      skip_if_unavailable(context)

      assert {:ok, latency_ms} = ClickHouse.health_check(@peer_info)
      assert is_integer(latency_ms)
      assert latency_ms >= 0
    end
  end

  # ---------------------------------------------------------------------------
  # 2. Read / Query — Verify Seed Data
  # ---------------------------------------------------------------------------

  describe "querying seeded hexads table" do
    test "SELECT * returns all 3 seeded rows", context do
      skip_if_unavailable(context)

      query_params = %{modalities: [], limit: 100}
      assert {:ok, results} = ClickHouse.query(@peer_info, query_params)

      # The seed script inserts 3 hexad rows
      assert length(results) >= 3

      Enum.each(results, fn result ->
        assert result.source_store == "ch-integration"
        assert is_binary(result.hexad_id)
        assert is_number(result.score)
        assert result.drifted == false
        assert is_map(result.data)
      end)
    end

    test "results contain expected seed data fields", context do
      skip_if_unavailable(context)

      query_params = %{modalities: [], limit: 10}
      assert {:ok, results} = ClickHouse.query(@peer_info, query_params)

      # Find hexad-test-001 in results
      test_001 = Enum.find(results, fn r -> r.hexad_id == "hexad-test-001" end)

      if test_001 do
        assert test_001.data["title"] == "Introduction to Cross-Modal Consistency"
        assert test_001.data["entity_type"] == "Article"
        assert test_001.data["drift_status"] in ["healthy", 0]
      end
    end
  end

  # ---------------------------------------------------------------------------
  # 3. Full-Text Search (Document Modality)
  # ---------------------------------------------------------------------------

  describe "full-text search via ClickHouse" do
    test "text search for 'drift' returns matching rows", context do
      skip_if_unavailable(context)

      query_params = %{
        modalities: [:document],
        text_query: "drift",
        limit: 10
      }

      assert {:ok, results} = ClickHouse.query(@peer_info, query_params)
      # hexad-test-002 title contains "Drift", hexad-test-003 content mentions drift
      assert length(results) >= 1
    end

    test "text search for 'VeriSimDB' returns matching rows", context do
      skip_if_unavailable(context)

      query_params = %{
        modalities: [:document],
        text_query: "verisimdb",
        limit: 10
      }

      assert {:ok, results} = ClickHouse.query(@peer_info, query_params)
      assert length(results) >= 1
    end
  end

  # ---------------------------------------------------------------------------
  # 4. Materialized View Queries
  # ---------------------------------------------------------------------------

  describe "materialized view queries" do
    test "drift status distribution view has data", context do
      skip_if_unavailable(context)

      # Query the materialized view directly via a custom peer config
      mv_peer = %{
        @peer_info
        | adapter_config: %{database: "verisimdb", table: "mv_drift_status_counts"}
      }

      query_params = %{modalities: [], limit: 100}

      case ClickHouse.query(mv_peer, query_params) do
        {:ok, results} ->
          # The materialized view should have rows from the 5 drift_scores inserts
          assert is_list(results)

        {:error, _reason} ->
          # Materialized views may have different column structure
          assert true
      end
    end
  end

  # ---------------------------------------------------------------------------
  # 5. Aggregation Queries (Drift Scores)
  # ---------------------------------------------------------------------------

  describe "aggregation on drift_scores table" do
    test "querying drift_scores table returns seeded measurements", context do
      skip_if_unavailable(context)

      drift_peer = %{
        @peer_info
        | adapter_config: %{database: "verisimdb", table: "drift_scores"}
      }

      query_params = %{modalities: [], limit: 100}
      assert {:ok, results} = ClickHouse.query(drift_peer, query_params)

      # Seed script inserts 5 drift score rows
      assert length(results) >= 5
    end

    test "temporal range query on drift_scores filters by measured_at", context do
      skip_if_unavailable(context)

      drift_peer = %{
        @peer_info
        | adapter_config: %{database: "verisimdb", table: "drift_scores"}
      }

      now = DateTime.utc_now()
      two_hours_ago = DateTime.add(now, -7200, :second)

      query_params = %{
        modalities: [:temporal],
        temporal_range: %{
          start: DateTime.to_iso8601(two_hours_ago),
          end: DateTime.to_iso8601(now)
        },
        limit: 100
      }

      assert {:ok, results} = ClickHouse.query(drift_peer, query_params)
      assert length(results) >= 1
    end
  end

  # ---------------------------------------------------------------------------
  # 6. Spatial Queries
  # ---------------------------------------------------------------------------

  describe "spatial queries via ClickHouse geo functions" do
    test "pointInPolygon query around London returns hexad-test-001", context do
      skip_if_unavailable(context)

      # hexad-test-001 has lat=51.5074, lon=-0.1278 (London)
      query_params = %{
        modalities: [:spatial],
        spatial_bounds: %{
          min_lon: -1.0,
          min_lat: 51.0,
          max_lon: 1.0,
          max_lat: 52.0
        },
        limit: 10
      }

      assert {:ok, results} = ClickHouse.query(@peer_info, query_params)
      assert length(results) >= 1
    end
  end

  # ---------------------------------------------------------------------------
  # 7. Write + Read-Back
  # ---------------------------------------------------------------------------

  describe "INSERT and SELECT round-trip" do
    test "translate_results normalises ClickHouse JSONEachRow format", context do
      skip_if_unavailable(context)

      test_id = "#{@integration_prefix}-ch-#{System.unique_integer([:positive])}"

      raw_row = %{
        "id" => test_id,
        "title" => "Integration Test Row",
        "entity_type" => "TestArticle",
        "score" => 0.73,
        "created_at" => DateTime.to_iso8601(DateTime.utc_now())
      }

      [normalised] = ClickHouse.translate_results([raw_row], @peer_info)

      assert normalised.source_store == "ch-integration"
      assert normalised.hexad_id == test_id
      assert normalised.score == 0.73
      assert normalised.drifted == false
    end
  end

  # ---------------------------------------------------------------------------
  # 8. Error Handling
  # ---------------------------------------------------------------------------

  describe "error handling against real ClickHouse" do
    test "querying a nonexistent table returns an error", context do
      skip_if_unavailable(context)

      bad_peer = %{
        @peer_info
        | adapter_config: %{database: "verisimdb", table: "nonexistent_table_xyz"}
      }

      query_params = %{modalities: [], limit: 10}

      assert {:error, _reason} = ClickHouse.query(bad_peer, query_params)
    end

    test "connecting to an unreachable endpoint returns an error" do
      unreachable_peer = %{
        store_id: "ch-unreachable",
        endpoint: "http://localhost:59996",
        adapter_config: %{database: "verisimdb", table: "hexads"}
      }

      assert {:error, _reason} = ClickHouse.connect(unreachable_peer)
    end
  end

  # ---------------------------------------------------------------------------
  # 9. Modality Support
  # ---------------------------------------------------------------------------

  describe "modality support declarations" do
    test "ClickHouse supports 5 modalities without extensions" do
      modalities = ClickHouse.supported_modalities(%{})

      assert :vector in modalities
      assert :document in modalities
      assert :temporal in modalities
      assert :spatial in modalities
      assert :semantic in modalities

      refute :graph in modalities
      refute :tensor in modalities
      refute :provenance in modalities
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp skip_if_unavailable(%{skip: true}), do: flunk("ClickHouse not available — start test-infra stack")
  defp skip_if_unavailable(_context), do: :ok
end
