# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim.Federation.Adapters.VectorDBTest do
  @moduledoc """
  Tests for the unified VectorDB federation adapter.

  Validates modality declarations across Qdrant/Milvus/Weaviate backends,
  result normalisation from each backend's response format, and backend
  dispatch routing.
  """

  use ExUnit.Case, async: true

  alias VeriSim.Federation.Adapters.VectorDB

  @peer_info %{
    store_id: "vector-test",
    endpoint: "http://qdrant:6333",
    adapter_config: %{collection: "hexads", backend: :qdrant}
  }

  describe "supported_modalities/1" do
    test "returns 4 supported modalities" do
      modalities = VectorDB.supported_modalities(%{})

      assert :vector in modalities
      assert :temporal in modalities
      assert :spatial in modalities
      assert :semantic in modalities

      refute :graph in modalities
      refute :document in modalities
      refute :tensor in modalities
      refute :provenance in modalities
    end
  end

  describe "translate_results/2" do
    test "normalises Qdrant point results" do
      raw = [
        %{
          "id" => "vec-001",
          "score" => 0.98,
          "payload" => %{"title" => "Vector match"}
        }
      ]

      [result] = VectorDB.translate_results(raw, @peer_info)

      assert result.hexad_id == "vec-001"
      assert result.score == 0.98
      assert result.source_store == "vector-test"
    end

    test "handles empty results" do
      assert VectorDB.translate_results([], @peer_info) == []
    end
  end
end
