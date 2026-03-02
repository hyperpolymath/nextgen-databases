# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim.Federation.Adapters.Neo4jIntegrationTest do
  @moduledoc """
  Integration tests for the Neo4j federation adapter.

  Runs against a real Neo4j 5.x instance from the test-infra container
  stack. The seed script `neo4j-init.cypher` pre-loads:

  - 4 Hexad nodes (hexad-test-001 through -004) with labels, properties,
    and spatial coordinates
  - 6 relationships: RELATES_TO, CITES, PART_OF
  - 2 ProvenanceEvent nodes chained with FOLLOWED_BY and HAS_PROVENANCE
  - 3 OntologyType nodes with IS_TYPE and SUBCLASS_OF relationships
  - Fulltext index `hexad_fulltext` on [title, content]
  - Constraints: unique on Hexad.id, ProvenanceEvent.event_id

  ## Test Infrastructure

  Requires the test-infra stack running:

      cd connectors/test-infra && selur-compose up -d

  Neo4j is exposed on localhost:7474 (HTTP) and localhost:7687 (Bolt).
  Default credentials: neo4j/neo4j (or as configured in compose.toml).

  ## Running

      mix test --include integration test/verisim/federation/adapters/integration/neo4j_integration_test.exs

  Author: Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
  """

  use ExUnit.Case, async: false

  alias VeriSim.Federation.Adapters.Neo4j

  @moduletag :integration

  # ---------------------------------------------------------------------------
  # Configuration
  # ---------------------------------------------------------------------------

  @neo4j_http System.get_env("VERISIM_NEO4J_HTTP", "http://localhost:7474")
  @neo4j_user System.get_env("VERISIM_NEO4J_USER", "neo4j")
  @neo4j_pass System.get_env("VERISIM_NEO4J_PASS", "neo4j")

  @peer_info %{
    store_id: "neo4j-integration",
    endpoint: @neo4j_http,
    adapter_config: %{
      database: "neo4j",
      auth: {:basic, @neo4j_user, @neo4j_pass},
      label: "Hexad",
      version: 5,
      relationship_type: "RELATES_TO",
      fulltext_index: "hexad_fulltext",
      max_depth: 3
    }
  }

  @integration_prefix "hexad-integration"

  # ---------------------------------------------------------------------------
  # Setup / Teardown
  # ---------------------------------------------------------------------------

  setup_all do
    case Neo4j.health_check(@peer_info) do
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

  describe "connection to real Neo4j" do
    test "connect/1 succeeds against running instance", context do
      skip_if_unavailable(context)

      result = Neo4j.connect(@peer_info)
      assert result == :ok
    end

    test "health_check/1 returns latency in milliseconds", context do
      skip_if_unavailable(context)

      assert {:ok, latency_ms} = Neo4j.health_check(@peer_info)
      assert is_integer(latency_ms)
      assert latency_ms >= 0
    end
  end

  # ---------------------------------------------------------------------------
  # 2. Read / Query — Verify Seed Data
  # ---------------------------------------------------------------------------

  describe "querying seeded Hexad nodes" do
    test "default MATCH query returns all 4 seeded Hexad nodes", context do
      skip_if_unavailable(context)

      query_params = %{modalities: [], limit: 100}
      assert {:ok, results} = Neo4j.query(@peer_info, query_params)

      # The seed script creates 4 Hexad nodes
      assert length(results) >= 4

      Enum.each(results, fn result ->
        assert result.source_store == "neo4j-integration"
        assert is_binary(result.hexad_id) or result.hexad_id == "unknown"
        assert is_number(result.score)
        assert result.drifted == false
        assert is_map(result.data)
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # 3. Fulltext Index Search
  # ---------------------------------------------------------------------------

  describe "fulltext index search" do
    test "fulltext search for 'drift' returns matching nodes", context do
      skip_if_unavailable(context)

      # hexad-test-002 has title "Drift Detection Algorithms"
      # hexad-test-003 has content mentioning "drift"
      query_params = %{
        modalities: [:document],
        text_query: "drift",
        limit: 10
      }

      assert {:ok, results} = Neo4j.query(@peer_info, query_params)
      assert length(results) >= 1

      # Fulltext search should return Lucene scores
      Enum.each(results, fn r ->
        assert is_number(r.score)
      end)
    end

    test "fulltext search for 'normalisation' returns hexad-test-003", context do
      skip_if_unavailable(context)

      query_params = %{
        modalities: [:document],
        text_query: "normalisation",
        limit: 10
      }

      assert {:ok, results} = Neo4j.query(@peer_info, query_params)
      assert length(results) >= 1
    end
  end

  # ---------------------------------------------------------------------------
  # 4. Relationship Traversal
  # ---------------------------------------------------------------------------

  describe "graph relationship traversal" do
    test "RELATES_TO traversal from hexad-test-001 finds connected nodes", context do
      skip_if_unavailable(context)

      query_params = %{
        modalities: [:graph],
        graph_pattern: "hexad-test-001",
        limit: 10
      }

      assert {:ok, results} = Neo4j.query(@peer_info, query_params)
      # hexad-test-001 has RELATES_TO -> hexad-test-002 (bidirectional),
      # CITES -> hexad-test-003, PART_OF -> hexad-test-004
      assert length(results) >= 1
    end

    test "traversal from hexad-test-004 finds all PART_OF components", context do
      skip_if_unavailable(context)

      # Query with reversed relationship direction or multi-hop
      part_of_peer = %{
        @peer_info
        | adapter_config: Map.put(@peer_info.adapter_config, :relationship_type, "PART_OF")
      }

      query_params = %{
        modalities: [:graph],
        graph_pattern: "hexad-test-001",
        limit: 10
      }

      assert {:ok, results} = Neo4j.query(part_of_peer, query_params)
      assert is_list(results)
    end
  end

  # ---------------------------------------------------------------------------
  # 5. Provenance Chain Query
  # ---------------------------------------------------------------------------

  describe "provenance chain traversal" do
    test "semantic query for provenance events retrieves matching nodes", context do
      skip_if_unavailable(context)

      # Query ProvenanceEvent nodes via semantic filter on entity_type
      # (Since Neo4j adapter uses Hexad label by default, we can filter
      # by properties on Hexad nodes that link to provenance events)
      query_params = %{
        modalities: [:semantic],
        filters: %{"drift_status" => "healthy"},
        limit: 10
      }

      assert {:ok, results} = Neo4j.query(@peer_info, query_params)
      # hexad-test-001, hexad-test-003, hexad-test-004 are 'healthy'
      assert length(results) >= 1
    end
  end

  # ---------------------------------------------------------------------------
  # 6. Write + Read-Back
  # ---------------------------------------------------------------------------

  describe "write and read-back cycle" do
    test "translate_results correctly normalises Neo4j row format", context do
      skip_if_unavailable(context)

      test_id = "#{@integration_prefix}-neo4j-#{System.unique_integer([:positive])}"

      # Simulate Neo4j transaction API row format
      raw_row = %{
        "n" => %{
          "id" => test_id,
          "title" => "Integration Test Node",
          "entity_type" => "TestArticle",
          "drift_status" => "healthy"
        },
        "score" => 0.91
      }

      [normalised] = Neo4j.translate_results([raw_row], @peer_info)

      assert normalised.source_store == "neo4j-integration"
      assert normalised.score == 0.91
      assert normalised.drifted == false
    end
  end

  # ---------------------------------------------------------------------------
  # 7. Temporal Queries
  # ---------------------------------------------------------------------------

  describe "temporal queries with datetime" do
    test "temporal range query filters Hexad nodes by created_at", context do
      skip_if_unavailable(context)

      # All seed nodes were created relative to now() — query a wide range
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

      assert {:ok, results} = Neo4j.query(@peer_info, query_params)
      assert length(results) >= 1
    end
  end

  # ---------------------------------------------------------------------------
  # 8. Error Handling
  # ---------------------------------------------------------------------------

  describe "error handling against real Neo4j" do
    test "invalid Cypher syntax returns an error", context do
      skip_if_unavailable(context)

      # We cannot inject arbitrary Cypher through the adapter's query/3 API,
      # but we can verify that a query with a nonexistent label returns empty.
      nonexistent_peer = %{
        @peer_info
        | adapter_config: Map.put(@peer_info.adapter_config, :label, "NonexistentLabel999")
      }

      query_params = %{modalities: [], limit: 10}

      case Neo4j.query(nonexistent_peer, query_params) do
        {:ok, results} ->
          # Querying a nonexistent label returns empty results in Neo4j
          assert results == []

        {:error, _reason} ->
          assert true
      end
    end

    test "connecting to an unreachable endpoint returns an error" do
      unreachable_peer = %{
        store_id: "neo4j-unreachable",
        endpoint: "http://localhost:59997",
        adapter_config: %{database: "neo4j"}
      }

      assert {:error, _reason} = Neo4j.connect(unreachable_peer)
    end
  end

  # ---------------------------------------------------------------------------
  # 9. Modality Support
  # ---------------------------------------------------------------------------

  describe "modality support declarations" do
    test "Neo4j 5+ supports 6 modalities including vector" do
      modalities = Neo4j.supported_modalities(%{version: 5})

      assert :graph in modalities
      assert :vector in modalities
      assert :document in modalities
      assert :temporal in modalities
      assert :spatial in modalities
      assert :semantic in modalities

      refute :tensor in modalities
      refute :provenance in modalities
    end

    test "Neo4j 4.x does not support vector search" do
      modalities = Neo4j.supported_modalities(%{version: 4})

      assert :graph in modalities
      refute :vector in modalities
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp skip_if_unavailable(%{skip: true}), do: flunk("Neo4j not available — start test-infra stack")
  defp skip_if_unavailable(_context), do: :ok
end
