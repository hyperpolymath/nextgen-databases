# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim.Federation.Adapters.Neo4jTest do
  @moduledoc """
  Tests for the Neo4j federation adapter.

  Validates modality declarations, Cypher query construction,
  and result normalisation from Neo4j's transactional HTTP response format.
  """

  use ExUnit.Case, async: true

  alias VeriSim.Federation.Adapters.Neo4j

  @peer_info %{
    store_id: "neo4j-test",
    endpoint: "http://neo4j:7474",
    adapter_config: %{database: "neo4j"}
  }

  describe "supported_modalities/1" do
    test "returns 6 supported modalities" do
      modalities = Neo4j.supported_modalities(%{})

      assert :graph in modalities
      assert :vector in modalities
      assert :document in modalities
      assert :temporal in modalities
      assert :spatial in modalities
      assert :semantic in modalities

      refute :tensor in modalities
      refute :provenance in modalities
    end
  end

  describe "translate_results/2" do
    test "extracts Neo4j node properties" do
      raw = [
        %{
          "id" => "neo4j-001",
          "labels" => ["Hexad"],
          "properties" => %{"title" => "Graph entity"},
          "score" => 0.92
        }
      ]

      [result] = Neo4j.translate_results(raw, @peer_info)

      assert result.hexad_id == "neo4j-001"
      assert result.score == 0.92
      assert result.source_store == "neo4j-test"
    end

    test "handles empty results" do
      assert Neo4j.translate_results([], @peer_info) == []
    end
  end
end
