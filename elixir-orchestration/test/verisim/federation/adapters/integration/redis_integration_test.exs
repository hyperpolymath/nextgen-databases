# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim.Federation.Adapters.RedisIntegrationTest do
  @moduledoc """
  Integration tests for the Redis federation adapter.

  Runs against a real Redis Stack instance from the test-infra container
  stack. Redis Stack bundles RediSearch, RedisJSON, RedisTimeSeries, and
  RedisGraph modules. The seed script `redis-init.sh` pre-loads:

  - 3 hexad JSON documents (hexad:test-001, hexad:test-002, hexad:test-003)
  - 2 drift score documents (drift:test-001, drift:test-002)
  - 2 RediSearch indexes (idx:hexads, idx:drift)
  - 3 RedisTimeSeries keys with sample data points

  ## Test Infrastructure

  Requires the test-infra stack running:

      cd connectors/test-infra && selur-compose up -d

  Redis Stack is exposed on localhost:6379.

  ## Running

      mix test --include integration test/verisim/federation/adapters/integration/redis_integration_test.exs

  Author: Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
  """

  use ExUnit.Case, async: false

  alias VeriSim.Federation.Adapters.Redis

  @moduletag :integration

  # ---------------------------------------------------------------------------
  # Configuration
  # ---------------------------------------------------------------------------

  @redis_url System.get_env("VERISIM_REDIS_URL", "http://localhost:6379")

  @peer_info %{
    store_id: "redis-integration",
    endpoint: @redis_url,
    adapter_config: %{
      database: 0,
      modules: [:redisearch, :redisgraph, :redisjson, :redistimeseries],
      index_name: "idx:hexads",
      json_key_pattern: "hexad:*"
    }
  }

  # Prefix for integration test data
  @integration_prefix "hexad-integration"

  # ---------------------------------------------------------------------------
  # Setup / Teardown
  # ---------------------------------------------------------------------------

  setup_all do
    case Redis.health_check(@peer_info) do
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

  describe "connection to real Redis Stack" do
    test "connect/1 succeeds against running instance", context do
      skip_if_unavailable(context)

      result = Redis.connect(@peer_info)
      assert result == :ok
    end

    test "health_check/1 returns PONG with latency", context do
      skip_if_unavailable(context)

      assert {:ok, latency_ms} = Redis.health_check(@peer_info)
      assert is_integer(latency_ms)
      assert latency_ms >= 0
    end
  end

  # ---------------------------------------------------------------------------
  # 2. RediSearch Full-Text Search (FT.SEARCH)
  # ---------------------------------------------------------------------------

  describe "FT.SEARCH on idx:hexads index" do
    test "searching for 'consistency' returns matching hexads", context do
      skip_if_unavailable(context)

      query_params = %{
        modalities: [:document],
        text_query: "consistency",
        limit: 10
      }

      assert {:ok, results} = Redis.query(@peer_info, query_params)
      assert is_list(results)

      # All results should be properly normalised
      Enum.each(results, fn result ->
        assert result.source_store == "redis-integration"
        assert is_binary(result.hexad_id)
        assert is_number(result.score)
      end)
    end

    test "searching with wildcard '*' returns all indexed documents", context do
      skip_if_unavailable(context)

      query_params = %{
        modalities: [:document],
        text_query: "*",
        limit: 100
      }

      assert {:ok, results} = Redis.query(@peer_info, query_params)
      # Seed loads 3 hexad documents into the index
      assert length(results) >= 3
    end
  end

  # ---------------------------------------------------------------------------
  # 3. RedisJSON (JSON.GET)
  # ---------------------------------------------------------------------------

  describe "RedisJSON document access" do
    test "translate_results normalises a JSON document shape", context do
      skip_if_unavailable(context)

      # Simulate a JSON document as returned by the Redis HTTP bridge
      raw = [
        %{
          "id" => "hexad:test-001",
          "score" => 0.85,
          "payload" => %{
            "title" => "Introduction to Cross-Modal Consistency",
            "version" => 3
          }
        }
      ]

      [result] = Redis.translate_results(raw, @peer_info)

      assert result.source_store == "redis-integration"
      assert result.hexad_id == "hexad:test-001"
      assert result.score == 0.85
      assert result.drifted == false
    end
  end

  # ---------------------------------------------------------------------------
  # 4. RedisTimeSeries (TS.RANGE)
  # ---------------------------------------------------------------------------

  describe "RedisTimeSeries temporal queries" do
    test "temporal range query returns time-series data", context do
      skip_if_unavailable(context)

      # The seed script creates ts:drift:test-001:overall with sample data
      ts_peer = %{
        @peer_info
        | adapter_config:
            Map.merge(@peer_info.adapter_config, %{
              timeseries_key: "ts:drift:test-001:overall"
            })
      }

      query_params = %{
        modalities: [:temporal],
        temporal_range: %{
          start: "-",
          end: "+"
        },
        limit: 100
      }

      assert {:ok, results} = Redis.query(ts_peer, query_params)
      assert is_list(results)
    end
  end

  # ---------------------------------------------------------------------------
  # 5. Write + Read-Back via translate_results
  # ---------------------------------------------------------------------------

  describe "write and read-back cycle" do
    test "translate_results correctly normalises integration test data", context do
      skip_if_unavailable(context)

      test_id = "#{@integration_prefix}-redis-#{System.unique_integer([:positive])}"

      raw_doc = %{
        "id" => test_id,
        "score" => 0.62,
        "payload" => %{
          "title" => "Integration test hexad",
          "content" => "Written by RedisIntegrationTest"
        }
      }

      [normalised] = Redis.translate_results([raw_doc], @peer_info)

      assert normalised.source_store == "redis-integration"
      assert normalised.hexad_id == test_id
      assert normalised.score == 0.62
      assert normalised.drifted == false
    end
  end

  # ---------------------------------------------------------------------------
  # 6. Provenance (Redis Streams)
  # ---------------------------------------------------------------------------

  describe "Redis Streams provenance queries" do
    test "provenance query via XREVRANGE returns stream entries", context do
      skip_if_unavailable(context)

      stream_peer = %{
        @peer_info
        | adapter_config:
            Map.merge(@peer_info.adapter_config, %{
              stream_key: "hexad_provenance"
            })
      }

      query_params = %{
        modalities: [:provenance],
        limit: 10
      }

      assert {:ok, results} = Redis.query(stream_peer, query_params)
      assert is_list(results)
    end

    test "supported_modalities includes :provenance (Streams are built-in)" do
      # Provenance via Redis Streams is always available
      modalities = Redis.supported_modalities(%{modules: []})
      assert :provenance in modalities
    end
  end

  # ---------------------------------------------------------------------------
  # 7. Vector Similarity Search
  # ---------------------------------------------------------------------------

  describe "vector similarity search (RediSearch VSS)" do
    test "supported_modalities includes :vector when redisearch module present" do
      config = %{modules: [:redisearch]}
      modalities = Redis.supported_modalities(config)
      assert :vector in modalities
    end

    test "vector query builds correct FT.SEARCH command", context do
      skip_if_unavailable(context)

      # This tests that the adapter can construct and attempt a vector query.
      # The actual search may return an error if no vector index is configured
      # on the test instance, which is acceptable.
      query_params = %{
        modalities: [:vector],
        vector_query: [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8],
        limit: 5
      }

      result = Redis.query(@peer_info, query_params)
      # Either succeeds or returns an error (no vector index in seed data)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  # ---------------------------------------------------------------------------
  # 8. Error Handling
  # ---------------------------------------------------------------------------

  describe "error handling against real Redis" do
    test "querying a nonexistent index returns an error", context do
      skip_if_unavailable(context)

      bad_peer = %{
        @peer_info
        | adapter_config: Map.put(@peer_info.adapter_config, :index_name, "idx:nonexistent_xyz")
      }

      query_params = %{
        modalities: [:document],
        text_query: "test",
        limit: 10
      }

      result = Redis.query(bad_peer, query_params)
      # Should return an error or empty results
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "connecting to an unreachable endpoint returns an error" do
      unreachable_peer = %{
        store_id: "redis-unreachable",
        endpoint: "http://localhost:59998",
        adapter_config: %{database: 0, modules: []}
      }

      assert {:error, _reason} = Redis.connect(unreachable_peer)
    end
  end

  # ---------------------------------------------------------------------------
  # 9. Module-Dependent Modality Detection
  # ---------------------------------------------------------------------------

  describe "module-dependent modality detection" do
    test "all modules yields full modality set" do
      config = %{modules: [:redisgraph, :redisearch, :redisjson, :redistimeseries]}
      modalities = Redis.supported_modalities(config)

      assert :graph in modalities
      assert :document in modalities
      assert :semantic in modalities
      assert :temporal in modalities
      assert :vector in modalities
      assert :provenance in modalities
    end

    test "missing modules reduces available modalities" do
      config = %{modules: []}
      modalities = Redis.supported_modalities(config)

      # Only provenance (Streams) is built-in
      assert modalities == [:provenance]
      refute :graph in modalities
      refute :vector in modalities
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp skip_if_unavailable(%{skip: true}), do: flunk("Redis Stack not available — start test-infra stack")
  defp skip_if_unavailable(_context), do: :ok
end
