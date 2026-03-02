# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim.Federation.Adapters.MongoDBTest do
  @moduledoc """
  Tests for the MongoDB federation adapter.

  Validates modality declarations, result normalisation from MongoDB
  document format, and aggregation pipeline construction patterns.
  """

  use ExUnit.Case, async: true

  alias VeriSim.Federation.Adapters.MongoDB

  @peer_info %{
    store_id: "mongo-test",
    endpoint: "http://mongo:27017",
    adapter_config: %{database: "verisimdb", collection: "hexads"}
  }

  # ---------------------------------------------------------------------------
  # Supported Modalities
  # ---------------------------------------------------------------------------

  describe "supported_modalities/1" do
    test "returns 5 base supported modalities (without Atlas or replica set)" do
      modalities = MongoDB.supported_modalities(%{})

      assert :graph in modalities
      assert :document in modalities
      assert :temporal in modalities
      assert :spatial in modalities
      assert :semantic in modalities

      # :vector requires atlas: true, :provenance requires replica_set key
      refute :vector in modalities
      refute :provenance in modalities
      refute :tensor in modalities
    end

    test "vector requires atlas: true" do
      modalities = MongoDB.supported_modalities(%{atlas: false})
      refute :vector in modalities

      modalities_with_atlas = MongoDB.supported_modalities(%{atlas: true})
      assert :vector in modalities_with_atlas
    end
  end

  # ---------------------------------------------------------------------------
  # Result Normalisation
  # ---------------------------------------------------------------------------

  describe "translate_results/2" do
    test "extracts _id from MongoDB documents" do
      raw = [%{"_id" => "64a1b2c3d4e5f67890abcdef", "title" => "Test", "score" => 0.9}]

      [result] = MongoDB.translate_results(raw, @peer_info)

      assert result.source_store == "mongo-test"
      assert result.hexad_id == "64a1b2c3d4e5f67890abcdef"
      assert result.score == 0.9
      assert result.drifted == false
    end

    test "handles missing _id gracefully" do
      raw = [%{"title" => "No ID"}]

      [result] = MongoDB.translate_results(raw, @peer_info)
      assert result.hexad_id == "unknown"
    end

    test "handles empty result list" do
      assert MongoDB.translate_results([], @peer_info) == []
    end

    test "normalises Atlas Vector Search results with score" do
      # The adapter's parse_score/1 checks doc["score"], which is set by the
      # $addFields stage in the vector search pipeline (vectorSearchScore meta).
      # The translated results contain the "score" key, not "searchScore".
      raw = [
        %{
          "_id" => "doc-1",
          "score" => 0.95,
          "title" => "Vector match"
        }
      ]

      [result] = MongoDB.translate_results(raw, @peer_info)
      assert result.score == 0.95
    end
  end
end
