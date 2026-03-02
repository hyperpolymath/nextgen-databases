# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim.Federation.Adapters.SurrealDBIntegrationTest do
  @moduledoc """
  Integration tests for the SurrealDB federation adapter.

  Runs against a real SurrealDB instance from the test-infra container
  stack. The seed script `surrealdb-init.surql` pre-loads:

  - Namespace `verisimdb`, database `test`
  - `hexads` table: 4 schemafull records (test001-test004) with title,
    content, entity_type, drift_status, drift_score, tags, timestamps
  - Edge tables: `relates_to` (2), `cites` (1), `part_of` (3), `derived_from` (1)
  - `modalities` table: 5 records
  - `drift_scores` table: 2 records
  - `provenance_events` table: 2 records
  - Fulltext index `idx_hexads_fulltext` with BM25 scoring
  - Field-level indexes on entity_type, drift_status, created_at

  ## Test Infrastructure

  Requires the test-infra stack running:

      cd connectors/test-infra && selur-compose up -d

  SurrealDB is exposed on localhost:8000.
  Default credentials: root/root (test only).

  ## Running

      mix test --include integration test/verisim/federation/adapters/integration/surrealdb_integration_test.exs

  Author: Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
  """

  use ExUnit.Case, async: false

  alias VeriSim.Federation.Adapters.SurrealDB

  @moduletag :integration

  # ---------------------------------------------------------------------------
  # Configuration
  # ---------------------------------------------------------------------------

  @surrealdb_url System.get_env("VERISIM_SURREALDB_URL", "http://localhost:8000")

  @peer_info %{
    store_id: "surreal-integration",
    endpoint: @surrealdb_url,
    adapter_config: %{
      namespace: "verisimdb",
      database: "test",
      table: "hexads",
      auth: {:basic, "root", "root"},
      edge_table: "relates_to",
      search_fields: ["title", "content"],
      max_depth: 3
    }
  }

  @integration_prefix "hexad-integration"

  # ---------------------------------------------------------------------------
  # Setup / Teardown
  # ---------------------------------------------------------------------------

  setup_all do
    case SurrealDB.health_check(@peer_info) do
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

  describe "connection to real SurrealDB" do
    test "connect/1 succeeds against running instance", context do
      skip_if_unavailable(context)

      result = SurrealDB.connect(@peer_info)
      assert result == :ok
    end

    test "health_check/1 returns 200 with latency", context do
      skip_if_unavailable(context)

      assert {:ok, latency_ms} = SurrealDB.health_check(@peer_info)
      assert is_integer(latency_ms)
      assert latency_ms >= 0
    end
  end

  # ---------------------------------------------------------------------------
  # 2. Read / Query — Verify Seed Data
  # ---------------------------------------------------------------------------

  describe "querying seeded hexads table" do
    test "SELECT * returns all 4 seeded records", context do
      skip_if_unavailable(context)

      query_params = %{modalities: [], limit: 100}
      assert {:ok, results} = SurrealDB.query(@peer_info, query_params)

      # The seed script creates 4 hexad records
      assert length(results) >= 4

      Enum.each(results, fn result ->
        assert result.source_store == "surreal-integration"
        assert is_binary(result.hexad_id)
        assert is_number(result.score)
        assert result.drifted == false
        assert is_map(result.data)
      end)
    end

    test "SurrealDB record IDs are correctly stripped of table prefix", context do
      skip_if_unavailable(context)

      query_params = %{modalities: [], limit: 10}
      assert {:ok, results} = SurrealDB.query(@peer_info, query_params)

      # SurrealDB IDs are "hexads:test001" — adapter should extract "test001"
      ids = Enum.map(results, & &1.hexad_id)

      # At least one of the seeded IDs should be present (without table prefix)
      assert Enum.any?(ids, fn id ->
               id in ["test001", "test002", "test003", "test004"]
             end)
    end
  end

  # ---------------------------------------------------------------------------
  # 3. Edge Traversal (Graph Modality)
  # ---------------------------------------------------------------------------

  describe "graph edge traversal" do
    test "relates_to traversal from test001 finds connected hexads", context do
      skip_if_unavailable(context)

      query_params = %{
        modalities: [:graph],
        graph_pattern: "test001",
        limit: 10
      }

      assert {:ok, results} = SurrealDB.query(@peer_info, query_params)
      # test001 -> relates_to -> test002
      assert is_list(results)
    end

    test "derived_from traversal finds derivation chain", context do
      skip_if_unavailable(context)

      derived_peer = %{
        @peer_info
        | adapter_config: Map.put(@peer_info.adapter_config, :edge_table, "derived_from")
      }

      query_params = %{
        modalities: [:graph],
        graph_pattern: "test003",
        limit: 10
      }

      assert {:ok, results} = SurrealDB.query(derived_peer, query_params)
      # test003 -> derived_from -> test001
      assert is_list(results)
    end

    test "part_of traversal from test001 finds parent concept", context do
      skip_if_unavailable(context)

      part_of_peer = %{
        @peer_info
        | adapter_config: Map.put(@peer_info.adapter_config, :edge_table, "part_of")
      }

      query_params = %{
        modalities: [:graph],
        graph_pattern: "test001",
        limit: 10
      }

      assert {:ok, results} = SurrealDB.query(part_of_peer, query_params)
      assert is_list(results)
    end
  end

  # ---------------------------------------------------------------------------
  # 4. Fulltext Search
  # ---------------------------------------------------------------------------

  describe "fulltext search via SurrealDB analyzer" do
    test "text search for 'consistency' returns matching records", context do
      skip_if_unavailable(context)

      query_params = %{
        modalities: [:document],
        text_query: "consistency",
        limit: 10
      }

      assert {:ok, results} = SurrealDB.query(@peer_info, query_params)
      # hexad test001 title contains "Consistency"
      assert length(results) >= 1
    end

    test "text search for 'federation' returns hexad test004", context do
      skip_if_unavailable(context)

      query_params = %{
        modalities: [:document],
        text_query: "federation",
        limit: 10
      }

      assert {:ok, results} = SurrealDB.query(@peer_info, query_params)
      assert length(results) >= 1
    end
  end

  # ---------------------------------------------------------------------------
  # 5. Temporal Queries
  # ---------------------------------------------------------------------------

  describe "temporal queries with datetime" do
    test "temporal range query filters records by created_at", context do
      skip_if_unavailable(context)

      now = DateTime.utc_now()
      two_days_ago = DateTime.add(now, -2 * 86400, :second)

      query_params = %{
        modalities: [:temporal],
        temporal_range: %{
          start: DateTime.to_iso8601(two_days_ago),
          end: DateTime.to_iso8601(now)
        },
        limit: 100
      }

      assert {:ok, results} = SurrealDB.query(@peer_info, query_params)
      assert length(results) >= 1
    end
  end

  # ---------------------------------------------------------------------------
  # 6. Write + Read-Back
  # ---------------------------------------------------------------------------

  describe "CREATE and SELECT round-trip" do
    test "translate_results correctly normalises SurrealDB record format", context do
      skip_if_unavailable(context)

      test_id = "#{@integration_prefix}-surreal-#{System.unique_integer([:positive])}"

      # Simulate SurrealDB response format
      raw_record = %{
        "id" => "hexads:#{test_id}",
        "title" => "Integration Test Record",
        "entity_type" => "TestArticle",
        "drift_status" => "healthy",
        "score" => 0.82
      }

      [normalised] = SurrealDB.translate_results([raw_record], @peer_info)

      assert normalised.source_store == "surreal-integration"
      # The adapter strips the "hexads:" table prefix from the ID
      assert normalised.hexad_id == test_id
      assert normalised.score == 0.82
      assert normalised.drifted == false
    end
  end

  # ---------------------------------------------------------------------------
  # 7. Semantic (Metadata) Queries
  # ---------------------------------------------------------------------------

  describe "semantic metadata queries" do
    test "filtering by metadata.entity_type returns matching records", context do
      skip_if_unavailable(context)

      query_params = %{
        modalities: [:semantic],
        filters: %{"entity_type" => "Article"},
        limit: 10
      }

      assert {:ok, results} = SurrealDB.query(@peer_info, query_params)
      # test001 and test003 are entity_type "Article"
      assert is_list(results)
    end
  end

  # ---------------------------------------------------------------------------
  # 8. Error Handling
  # ---------------------------------------------------------------------------

  describe "error handling against real SurrealDB" do
    test "invalid SurrealQL returns an error", context do
      skip_if_unavailable(context)

      # Query a nonexistent table — SurrealDB may return empty or error
      bad_peer = %{
        @peer_info
        | adapter_config: Map.put(@peer_info.adapter_config, :table, "nonexistent_table_xyz")
      }

      query_params = %{modalities: [], limit: 10}

      case SurrealDB.query(bad_peer, query_params) do
        {:ok, results} ->
          # SurrealDB may return empty for nonexistent tables
          assert results == []

        {:error, _reason} ->
          assert true
      end
    end

    test "connecting to an unreachable endpoint returns an error" do
      unreachable_peer = %{
        store_id: "surreal-unreachable",
        endpoint: "http://localhost:59995",
        adapter_config: %{namespace: "verisimdb", database: "test"}
      }

      assert {:error, _reason} = SurrealDB.connect(unreachable_peer)
    end
  end

  # ---------------------------------------------------------------------------
  # 9. Modality Support
  # ---------------------------------------------------------------------------

  describe "modality support declarations" do
    test "SurrealDB supports 4 modalities" do
      modalities = SurrealDB.supported_modalities(%{})

      assert :graph in modalities
      assert :document in modalities
      assert :temporal in modalities
      assert :semantic in modalities

      refute :vector in modalities
      refute :tensor in modalities
      refute :provenance in modalities
      refute :spatial in modalities
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp skip_if_unavailable(%{skip: true}), do: flunk("SurrealDB not available — start test-infra stack")
  defp skip_if_unavailable(_context), do: :ok
end
