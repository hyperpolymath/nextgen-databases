# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim.Federation.Adapters.RedisTest do
  @moduledoc """
  Tests for the Redis federation adapter.

  Validates module-dependent modality declarations, result normalisation
  from Redis command responses, and RediSearch/RedisJSON integration.
  """

  use ExUnit.Case, async: true

  alias VeriSim.Federation.Adapters.Redis

  @peer_info %{
    store_id: "redis-test",
    endpoint: "http://redis:6379",
    adapter_config: %{database: 0}
  }

  # ---------------------------------------------------------------------------
  # Supported Modalities
  # ---------------------------------------------------------------------------

  describe "supported_modalities/1" do
    test "with no modules declared returns provenance (Redis Streams built-in)" do
      modalities = Redis.supported_modalities(%{modules: []})
      assert modalities == [:provenance]
    end

    test "with all modules returns full set" do
      config = %{
        modules: [:redisgraph, :redisearch, :redisjson, :redistimeseries]
      }

      modalities = Redis.supported_modalities(config)

      assert :graph in modalities
      assert :document in modalities
      assert :semantic in modalities
      assert :temporal in modalities
      assert :vector in modalities
      assert :provenance in modalities
    end

    test "vector requires redisearch module" do
      modalities = Redis.supported_modalities(%{modules: [:redisjson]})
      refute :vector in modalities
    end

    test "graph requires redisgraph module" do
      modalities = Redis.supported_modalities(%{modules: [:redisearch]})
      refute :graph in modalities
    end
  end

  # ---------------------------------------------------------------------------
  # Result Normalisation
  # ---------------------------------------------------------------------------

  describe "translate_results/2" do
    test "normalises RediSearch results" do
      raw = [%{"id" => "redis:key:1", "score" => 0.8, "payload" => %{"title" => "Test"}}]

      [result] = Redis.translate_results(raw, @peer_info)

      assert result.source_store == "redis-test"
      assert result.hexad_id == "redis:key:1"
      assert result.score == 0.8
    end

    test "handles empty results" do
      assert Redis.translate_results([], @peer_info) == []
    end
  end
end
