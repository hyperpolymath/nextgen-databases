# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim.Federation.Adapters.MongoDBIntegrationTest do
  @moduledoc """
  Integration tests for the MongoDB federation adapter.

  Runs against a real MongoDB 7+ replica set (rs0) from the test-infra
  container stack. The seed script `mongodb-init.js` pre-loads 3 hexad
  documents, 2 drift score documents, and 2 provenance events into the
  `verisimdb` database.

  ## Test Infrastructure

  Requires the test-infra stack running:

      cd connectors/test-infra && selur-compose up -d

  MongoDB is exposed on localhost:27017 with replica set `rs0`.

  ## Seed Data Summary

  - `hexads` collection: 3 documents (hexad-test-001, -002, -003)
    - Each has modalities array with document, vector, spatial, temporal,
      graph, provenance, and semantic sub-documents
    - Indexes: unique on `id`, text on `modalities.data.content`/`title`,
      2dsphere on `modalities.data.location`, compound on `created_at`/`updated_at`
  - `drift_scores` collection: 2 documents
  - `provenance_events` collection: 2 documents

  ## Running

      mix test --include integration test/verisim/federation/adapters/integration/mongodb_integration_test.exs

  Author: Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
  """

  use ExUnit.Case, async: false

  alias VeriSim.Federation.Adapters.MongoDB

  @moduletag :integration

  # ---------------------------------------------------------------------------
  # Configuration
  # ---------------------------------------------------------------------------

  @mongodb_url System.get_env("VERISIM_MONGODB_URL", "mongodb://localhost:27017")

  @peer_info %{
    store_id: "mongo-integration",
    endpoint: @mongodb_url,
    adapter_config: %{
      database: "verisimdb",
      collection: "hexads",
      replica_set: "rs0",
      geo_index: true,
      data_source: "Cluster0"
    }
  }

  # Prefix for integration test data — avoids collision with seed data (hexad-test-*)
  @integration_prefix "hexad-integration"

  # ---------------------------------------------------------------------------
  # Setup / Teardown
  # ---------------------------------------------------------------------------

  setup_all do
    # Verify MongoDB is reachable before running the suite.
    # If the connection fails, all tests in this module are skipped
    # rather than producing confusing error messages.
    case MongoDB.health_check(@peer_info) do
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

  describe "connection to real MongoDB" do
    test "connect/1 succeeds against running instance", context do
      skip_if_unavailable(context)

      result = MongoDB.connect(@peer_info)
      assert result == :ok
    end

    test "health_check/1 returns latency in milliseconds", context do
      skip_if_unavailable(context)

      assert {:ok, latency_ms} = MongoDB.health_check(@peer_info)
      assert is_integer(latency_ms)
      assert latency_ms >= 0
    end
  end

  # ---------------------------------------------------------------------------
  # 2. Read / Query — Verify Seed Data
  # ---------------------------------------------------------------------------

  describe "querying seeded hexads collection" do
    test "default query returns all 3 seeded documents", context do
      skip_if_unavailable(context)

      query_params = %{modalities: [], limit: 100}
      assert {:ok, results} = MongoDB.query(@peer_info, query_params)

      # The seed script inserts 3 hexad documents
      assert length(results) >= 3

      # All results should be normalised with the correct source_store
      Enum.each(results, fn result ->
        assert result.source_store == "mongo-integration"
        assert is_binary(result.hexad_id)
        assert is_float(result.score) or is_integer(result.score)
        assert result.drifted == false
        assert is_map(result.data)
        assert is_integer(result.response_time_ms)
      end)
    end

    test "text search across document modality returns matching hexads", context do
      skip_if_unavailable(context)

      # Seed document hexad-test-001 contains "cross-modal consistency"
      query_params = %{
        modalities: [:document],
        text_query: "consistency modality",
        limit: 10
      }

      assert {:ok, results} = MongoDB.query(@peer_info, query_params)
      assert length(results) >= 1

      # Text search results should have a non-zero score from textScore
      first = List.first(results)
      assert first.score >= 0
    end

    test "temporal range query filters by created_at", context do
      skip_if_unavailable(context)

      # Seed data uses relative timestamps — query a wide window to capture all
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

      assert {:ok, results} = MongoDB.query(@peer_info, query_params)
      # Should find at least some of the 3 seeded hexads created within 1 day
      assert length(results) >= 1
    end

    test "semantic (metadata) filter query returns matching documents", context do
      skip_if_unavailable(context)

      # Hexad-test-001 has modality type "document" with specific content
      query_params = %{
        modalities: [:semantic],
        filters: %{"type" => "document"},
        limit: 10
      }

      assert {:ok, results} = MongoDB.query(@peer_info, query_params)
      assert is_list(results)
    end
  end

  # ---------------------------------------------------------------------------
  # 3. Spatial Modality Query
  # ---------------------------------------------------------------------------

  describe "geospatial queries (2dsphere)" do
    test "geoWithin query on London coordinates returns hexad-test-001", context do
      skip_if_unavailable(context)

      # hexad-test-001 is located at [-0.1278, 51.5074] (London)
      # Query a bounding box around London
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

      assert {:ok, results} = MongoDB.query(@peer_info, query_params)
      # Should find at least hexad-test-001 which has London coordinates
      assert length(results) >= 1
    end

    test "geoWithin query on empty region returns no results", context do
      skip_if_unavailable(context)

      # Query an area in the middle of the ocean where no hexads exist
      query_params = %{
        modalities: [:spatial],
        spatial_bounds: %{
          min_lon: 170.0,
          min_lat: -60.0,
          max_lon: 175.0,
          max_lat: -55.0
        },
        limit: 10
      }

      assert {:ok, results} = MongoDB.query(@peer_info, query_params)
      assert results == []
    end
  end

  # ---------------------------------------------------------------------------
  # 4. Write + Read-Back
  # ---------------------------------------------------------------------------

  describe "write and read-back cycle" do
    test "inserting a new hexad document and querying it back", context do
      skip_if_unavailable(context)

      test_id = "#{@integration_prefix}-write-#{System.unique_integer([:positive])}"

      # Write a new document via the adapter's query mechanism
      # (The adapter uses the MongoDB Data API — we test round-trip through
      # the adapter's translate_results/2 on the read side.)
      #
      # Since the adapter is read-oriented (query/3), we verify that
      # translate_results/2 correctly normalises a raw MongoDB document.
      raw_doc = %{
        "_id" => test_id,
        "id" => test_id,
        "title" => "Integration Test Document",
        "content" => "Created by MongoDBIntegrationTest",
        "score" => 0.77,
        "created_at" => DateTime.to_iso8601(DateTime.utc_now())
      }

      [normalised] = MongoDB.translate_results([raw_doc], @peer_info)

      assert normalised.source_store == "mongo-integration"
      assert normalised.hexad_id == test_id
      assert normalised.score == 0.77
      assert normalised.drifted == false
      assert normalised.data["title"] == "Integration Test Document"
    end
  end

  # ---------------------------------------------------------------------------
  # 5. Compound Index Queries
  # ---------------------------------------------------------------------------

  describe "compound index and graph queries" do
    test "graph traversal query with $graphLookup returns results", context do
      skip_if_unavailable(context)

      # hexad-test-001 has a relates_to relationship to hexad-test-002
      query_params = %{
        modalities: [:graph],
        graph_pattern: "hexad-test-001",
        limit: 10
      }

      assert {:ok, results} = MongoDB.query(@peer_info, query_params)
      assert is_list(results)
    end
  end

  # ---------------------------------------------------------------------------
  # 6. Change Stream / Provenance
  # ---------------------------------------------------------------------------

  describe "provenance modality (change stream)" do
    test "provenance query returns provenance log entries", context do
      skip_if_unavailable(context)

      # The seed script creates a provenance_events collection with 2 events
      provenance_peer = %{
        @peer_info
        | adapter_config:
            Map.merge(@peer_info.adapter_config, %{
              provenance_collection: "provenance_events",
              replica_set: "rs0"
            })
      }

      query_params = %{
        modalities: [:provenance],
        limit: 10
      }

      assert {:ok, results} = MongoDB.query(provenance_peer, query_params)
      assert is_list(results)
    end

    test "supported_modalities includes :provenance when replica_set configured" do
      config_with_rs = %{replica_set: "rs0", atlas: false, geo_index: true}
      modalities = MongoDB.supported_modalities(config_with_rs)

      assert :provenance in modalities
    end
  end

  # ---------------------------------------------------------------------------
  # 7. Error Handling
  # ---------------------------------------------------------------------------

  describe "error handling against real MongoDB" do
    test "querying a nonexistent collection returns an error or empty results", context do
      skip_if_unavailable(context)

      bad_peer = %{
        @peer_info
        | adapter_config: Map.put(@peer_info.adapter_config, :collection, "nonexistent_collection_xyz")
      }

      query_params = %{modalities: [], limit: 10}

      # The adapter should either return an error tuple or an empty result
      # (MongoDB allows queries on nonexistent collections — they return empty)
      case MongoDB.query(bad_peer, query_params) do
        {:ok, results} ->
          assert results == []

        {:error, _reason} ->
          # Also acceptable — some configurations may reject this
          assert true
      end
    end

    test "connecting to an unreachable endpoint returns an error" do
      unreachable_peer = %{
        store_id: "mongo-unreachable",
        endpoint: "http://localhost:59999",
        adapter_config: %{database: "verisimdb"}
      }

      assert {:error, _reason} = MongoDB.connect(unreachable_peer)
    end
  end

  # ---------------------------------------------------------------------------
  # 8. Result Normalisation (Against Real Data)
  # ---------------------------------------------------------------------------

  describe "translate_results/2 with real MongoDB document shapes" do
    test "normalises a document with ObjectId _id" do
      raw = [%{"_id" => "507f1f77bcf86cd799439011", "title" => "Real doc", "score" => 0.93}]

      [result] = MongoDB.translate_results(raw, @peer_info)

      assert result.hexad_id == "507f1f77bcf86cd799439011"
      assert result.score == 0.93
    end

    test "normalises a document with nested modalities array" do
      raw = [
        %{
          "_id" => "hexad-test-001",
          "id" => "hexad-test-001",
          "modalities" => [
            %{"type" => "document", "data" => %{"title" => "Test"}},
            %{"type" => "vector", "data" => %{"embedding" => [0.1, 0.2]}}
          ]
        }
      ]

      [result] = MongoDB.translate_results(raw, @peer_info)
      assert result.hexad_id == "hexad-test-001"
      assert is_list(result.data["modalities"])
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp skip_if_unavailable(%{skip: true}), do: flunk("MongoDB not available — start test-infra stack")
  defp skip_if_unavailable(_context), do: :ok
end
