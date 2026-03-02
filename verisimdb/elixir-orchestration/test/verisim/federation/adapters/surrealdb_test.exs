# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim.Federation.Adapters.SurrealDBTest do
  @moduledoc """
  Tests for the SurrealDB federation adapter.

  Validates modality declarations, SurrealQL query construction,
  and result normalisation from SurrealDB's multi-model response format.
  """

  use ExUnit.Case, async: true

  alias VeriSim.Federation.Adapters.SurrealDB

  @peer_info %{
    store_id: "surreal-test",
    endpoint: "http://surrealdb:8000",
    adapter_config: %{namespace: "verisim", database: "main"}
  }

  describe "supported_modalities/1" do
    test "returns 4 supported modalities" do
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

  describe "translate_results/2" do
    test "extracts SurrealDB record ID" do
      raw = [%{"id" => "hexads:abc123", "title" => "Test", "score" => 0.88}]

      [result] = SurrealDB.translate_results(raw, @peer_info)

      assert result.hexad_id == "abc123"
      assert result.score == 0.88
      assert result.source_store == "surreal-test"
    end

    test "handles empty results" do
      assert SurrealDB.translate_results([], @peer_info) == []
    end
  end
end
