# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim.Federation.AdapterTest do
  @moduledoc """
  Tests for the heterogeneous federation adapter system.

  Tests adapter behaviour compliance, modality declarations, result
  normalisation, and resolver integration with mixed adapter types.
  """

  use ExUnit.Case, async: false

  alias VeriSim.Federation.Adapter
  alias VeriSim.Federation.Adapters.{ArangoDB, Elasticsearch, PostgreSQL, VeriSimDB}
  alias VeriSim.Federation.Adapters.{MongoDB, Redis, DuckDB, ClickHouse, SurrealDB}
  alias VeriSim.Federation.Adapters.{SQLite, Neo4j, VectorDB, InfluxDB, ObjectStorage}
  alias VeriSim.Federation.Resolver

  # ---------------------------------------------------------------------------
  # Adapter Registry
  # ---------------------------------------------------------------------------

  describe "Adapter.module_for/1" do
    test "resolves all known adapter types" do
      assert {:ok, VeriSimDB} = Adapter.module_for(:verisimdb)
      assert {:ok, ArangoDB} = Adapter.module_for(:arangodb)
      assert {:ok, PostgreSQL} = Adapter.module_for(:postgresql)
      assert {:ok, Elasticsearch} = Adapter.module_for(:elasticsearch)
      assert {:ok, MongoDB} = Adapter.module_for(:mongodb)
      assert {:ok, Redis} = Adapter.module_for(:redis)
      assert {:ok, DuckDB} = Adapter.module_for(:duckdb)
      assert {:ok, ClickHouse} = Adapter.module_for(:clickhouse)
      assert {:ok, SurrealDB} = Adapter.module_for(:surrealdb)
      assert {:ok, SQLite} = Adapter.module_for(:sqlite)
      assert {:ok, Neo4j} = Adapter.module_for(:neo4j)
      assert {:ok, VectorDB} = Adapter.module_for(:vector_db)
      assert {:ok, InfluxDB} = Adapter.module_for(:influxdb)
      assert {:ok, ObjectStorage} = Adapter.module_for(:object_storage)
    end

    test "returns error for unknown adapter type" do
      assert {:error, :unknown_adapter} = Adapter.module_for(:unknown)
      assert {:error, :unknown_adapter} = Adapter.module_for(:cassandra)
    end

    test "adapter_types/0 lists all 14 registered types" do
      types = Adapter.adapter_types()
      assert :verisimdb in types
      assert :arangodb in types
      assert :postgresql in types
      assert :elasticsearch in types
      assert :mongodb in types
      assert :redis in types
      assert :duckdb in types
      assert :clickhouse in types
      assert :surrealdb in types
      assert :sqlite in types
      assert :neo4j in types
      assert :vector_db in types
      assert :influxdb in types
      assert :object_storage in types
      assert length(types) == 14
    end
  end

  # ---------------------------------------------------------------------------
  # Supported Modalities
  # ---------------------------------------------------------------------------

  describe "supported_modalities/1" do
    test "VeriSimDB supports all 8 octad modalities" do
      modalities = VeriSimDB.supported_modalities(%{})

      assert :graph in modalities
      assert :vector in modalities
      assert :tensor in modalities
      assert :semantic in modalities
      assert :document in modalities
      assert :temporal in modalities
      assert :provenance in modalities
      assert :spatial in modalities
      assert length(modalities) == 8
    end

    test "ArangoDB supports graph, document, semantic, temporal, provenance, spatial" do
      modalities = ArangoDB.supported_modalities(%{})

      assert :graph in modalities
      assert :document in modalities
      assert :semantic in modalities
      assert :temporal in modalities
      assert :provenance in modalities
      assert :spatial in modalities

      # ArangoDB does NOT support vector or tensor
      refute :vector in modalities
      refute :tensor in modalities
      assert length(modalities) == 6
    end

    test "PostgreSQL base modalities without extensions" do
      modalities = PostgreSQL.supported_modalities(%{})

      assert :document in modalities
      assert :semantic in modalities
      assert :temporal in modalities
      assert :graph in modalities
      assert :provenance in modalities

      # Without extensions, no vector or spatial
      refute :vector in modalities
      refute :spatial in modalities
      assert length(modalities) == 5
    end

    test "PostgreSQL with pgvector adds vector modality" do
      modalities = PostgreSQL.supported_modalities(%{extensions: [:pgvector]})

      assert :vector in modalities
      assert :document in modalities
      refute :spatial in modalities
      assert length(modalities) == 6
    end

    test "PostgreSQL with PostGIS adds spatial modality" do
      modalities = PostgreSQL.supported_modalities(%{extensions: [:postgis]})

      assert :spatial in modalities
      assert :document in modalities
      refute :vector in modalities
      assert length(modalities) == 6
    end

    test "PostgreSQL with both pgvector and PostGIS" do
      modalities = PostgreSQL.supported_modalities(%{extensions: [:pgvector, :postgis]})

      assert :vector in modalities
      assert :spatial in modalities
      assert length(modalities) == 7
    end

    test "Elasticsearch supports document, vector, semantic, temporal, spatial" do
      modalities = Elasticsearch.supported_modalities(%{})

      assert :document in modalities
      assert :vector in modalities
      assert :semantic in modalities
      assert :temporal in modalities
      assert :spatial in modalities

      # Elasticsearch does NOT support graph, tensor, or provenance
      refute :graph in modalities
      refute :tensor in modalities
      refute :provenance in modalities
      assert length(modalities) == 5
    end
  end

  # ---------------------------------------------------------------------------
  # Result Normalisation
  # ---------------------------------------------------------------------------

  describe "translate_results/2" do
    @peer_info %{store_id: "test-peer", endpoint: "http://test:8080", adapter_config: %{}}

    test "VeriSimDB normalises results with id and score" do
      raw = [%{"id" => "abc-123", "score" => 0.95, "title" => "Test"}]

      [result] = VeriSimDB.translate_results(raw, @peer_info)

      assert result.source_store == "test-peer"
      assert result.hexad_id == "abc-123"
      assert result.score == 0.95
      assert result.drifted == false
      assert result.data == hd(raw)
    end

    test "VeriSimDB handles missing id gracefully" do
      raw = [%{"title" => "No ID"}]

      [result] = VeriSimDB.translate_results(raw, @peer_info)

      assert result.hexad_id == "unknown"
      assert result.score == 0.0
    end

    test "ArangoDB extracts _key from ArangoDB documents" do
      raw = [%{"_key" => "doc-456", "_id" => "hexads/doc-456", "_score" => 1.5}]

      [result] = ArangoDB.translate_results(raw, @peer_info)

      assert result.hexad_id == "doc-456"
      assert result.score == 1.5
      assert result.source_store == "test-peer"
    end

    test "ArangoDB falls back to _id when _key missing" do
      raw = [%{"_id" => "hexads/fallback-789"}]

      [result] = ArangoDB.translate_results(raw, @peer_info)

      assert result.hexad_id == "hexads/fallback-789"
    end

    test "PostgreSQL normalises row results" do
      raw = [%{"id" => "pg-001", "score" => 0.88, "title" => "PostgreSQL doc"}]

      [result] = PostgreSQL.translate_results(raw, @peer_info)

      assert result.hexad_id == "pg-001"
      assert result.score == 0.88
    end

    test "PostgreSQL handles entity_id field" do
      raw = [%{"entity_id" => "pg-alt", "score" => 0.5}]

      [result] = PostgreSQL.translate_results(raw, @peer_info)

      assert result.hexad_id == "pg-alt"
    end

    test "Elasticsearch extracts from _source and _id" do
      raw = [
        %{
          "_id" => "es-doc-1",
          "_score" => 2.3,
          "_source" => %{"title" => "ES document", "body" => "Content"}
        }
      ]

      [result] = Elasticsearch.translate_results(raw, @peer_info)

      assert result.hexad_id == "es-doc-1"
      assert result.score == 2.3
      assert result.data == %{"title" => "ES document", "body" => "Content"}
    end

    test "Elasticsearch handles null _score" do
      raw = [%{"_id" => "es-null-score", "_score" => nil, "_source" => %{}}]

      [result] = Elasticsearch.translate_results(raw, @peer_info)

      assert result.score == 0.0
    end

    test "all adapters handle empty result lists" do
      assert VeriSimDB.translate_results([], @peer_info) == []
      assert ArangoDB.translate_results([], @peer_info) == []
      assert PostgreSQL.translate_results([], @peer_info) == []
      assert Elasticsearch.translate_results([], @peer_info) == []
    end
  end

  # ---------------------------------------------------------------------------
  # Resolver Integration — Mixed Adapter Types
  # ---------------------------------------------------------------------------

  describe "resolver with heterogeneous peers" do
    setup do
      # Clear any peers from previous tests
      for peer <- Resolver.list_peers() do
        Resolver.deregister_peer(peer.store_id)
      end

      :ok
    end

    test "register VeriSimDB peer via 3-arity (backward-compatible)" do
      :ok = Resolver.register_peer("verisim-1", "http://v1:8080", ["graph", "vector"])

      [peer] = Resolver.list_peers()
      assert peer.store_id == "verisim-1"
      assert peer.adapter_type == :verisimdb
      assert "graph" in peer.modalities
      assert "vector" in peer.modalities
    end

    test "register ArangoDB peer via 2-arity map" do
      :ok =
        Resolver.register_peer("arango-1", %{
          endpoint: "http://arango:8529",
          adapter_type: :arangodb,
          adapter_config: %{database: "_system", collection: "entities"},
          modalities: ["graph", "document", "semantic"]
        })

      [peer] = Resolver.list_peers()
      assert peer.store_id == "arango-1"
      assert peer.adapter_type == :arangodb
      assert "graph" in peer.modalities
      assert "document" in peer.modalities
      assert "semantic" in peer.modalities
    end

    test "register PostgreSQL peer with extension-based modality validation" do
      :ok =
        Resolver.register_peer("pg-1", %{
          endpoint: "http://pg-proxy:3000",
          adapter_type: :postgresql,
          adapter_config: %{
            database: "verisimdb",
            table: "hexads",
            extensions: [:pgvector, :postgis]
          },
          modalities: ["document", "vector", "spatial", "tensor"]
        })

      [peer] = Resolver.list_peers()
      assert peer.store_id == "pg-1"
      assert peer.adapter_type == :postgresql

      # tensor is NOT supported by PostgreSQL — should be filtered out
      refute "tensor" in peer.modalities
      assert "document" in peer.modalities
      assert "vector" in peer.modalities
      assert "spatial" in peer.modalities
    end

    test "register Elasticsearch peer" do
      :ok =
        Resolver.register_peer("es-1", %{
          endpoint: "http://elastic:9200",
          adapter_type: :elasticsearch,
          adapter_config: %{index: "hexads", version: 8},
          modalities: ["document", "vector"]
        })

      [peer] = Resolver.list_peers()
      assert peer.store_id == "es-1"
      assert peer.adapter_type == :elasticsearch
      assert "document" in peer.modalities
      assert "vector" in peer.modalities
    end

    test "reject unknown adapter type" do
      result =
        Resolver.register_peer("bad-adapter", %{
          endpoint: "http://mystery:1234",
          adapter_type: :cassandra,
          modalities: ["document"]
        })

      assert {:error, {:unknown_adapter, :cassandra}} = result
      assert Resolver.list_peers() == []
    end

    test "mixed adapter types in federation query" do
      # Register a VeriSimDB peer and an ArangoDB peer
      :ok = Resolver.register_peer("verisim-peer", "http://v:8080", ["document"])

      :ok =
        Resolver.register_peer("arango-peer", %{
          endpoint: "http://a:8529",
          adapter_type: :arangodb,
          adapter_config: %{database: "_system"},
          modalities: ["document", "graph"]
        })

      # Query for document modality — both peers should match
      {:ok, response} = Resolver.query("*", ["document"], timeout: 2_000)

      assert length(response.stores_queried) == 2
      assert "verisim-peer" in response.stores_queried
      assert "arango-peer" in response.stores_queried
    end

    test "modality filtering across heterogeneous peers" do
      :ok =
        Resolver.register_peer("es-peer", %{
          endpoint: "http://es:9200",
          adapter_type: :elasticsearch,
          adapter_config: %{index: "data"},
          modalities: ["document", "vector"]
        })

      :ok =
        Resolver.register_peer("arango-peer", %{
          endpoint: "http://arango:8529",
          adapter_type: :arangodb,
          adapter_config: %{database: "_system"},
          modalities: ["graph", "document"]
        })

      # Query for vector — only ES supports it
      {:ok, response} = Resolver.query("*", ["vector"], timeout: 2_000)

      assert length(response.stores_queried) == 1
      assert "es-peer" in response.stores_queried
    end

    test "deregister heterogeneous peer" do
      :ok =
        Resolver.register_peer("to-remove", %{
          endpoint: "http://arango:8529",
          adapter_type: :arangodb,
          adapter_config: %{},
          modalities: ["document"]
        })

      assert length(Resolver.list_peers()) == 1

      :ok = Resolver.deregister_peer("to-remove")
      assert Resolver.list_peers() == []
    end

    test "deregister non-existent peer returns error" do
      result = Resolver.deregister_peer("ghost-peer")
      assert {:error, :not_found} = result
    end

    test "peer with no declared modalities gets adapter defaults" do
      :ok =
        Resolver.register_peer("default-mods", %{
          endpoint: "http://arango:8529",
          adapter_type: :arangodb,
          adapter_config: %{},
          modalities: []
        })

      [peer] = Resolver.list_peers()

      # ArangoDB defaults: graph, document, semantic, temporal, provenance, spatial
      assert length(peer.modalities) == 6
      assert "graph" in peer.modalities
      assert "document" in peer.modalities
    end
  end
end
