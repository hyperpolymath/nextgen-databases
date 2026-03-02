# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim.Federation.Adapters.SQLiteTest do
  @moduledoc """
  Tests for the SQLite federation adapter.

  Validates extension-dependent modality declarations, FTS5 query
  construction, and result normalisation from SQLite row format.
  """

  use ExUnit.Case, async: true

  alias VeriSim.Federation.Adapters.SQLite

  @peer_info %{
    store_id: "sqlite-test",
    endpoint: "http://sqlite-proxy:8080",
    adapter_config: %{path: "/data/verisim.db", table: "hexads"}
  }

  describe "supported_modalities/1" do
    test "base modalities without extensions" do
      modalities = SQLite.supported_modalities(%{extensions: []})

      assert :graph in modalities
      assert :temporal in modalities
      assert :semantic in modalities
      refute :document in modalities
      refute :vector in modalities
    end

    test "with sqlite-vss adds vector modality" do
      modalities = SQLite.supported_modalities(%{extensions: [:vss]})
      assert :vector in modalities
    end

    test "FTS5 adds document modality when enabled" do
      modalities = SQLite.supported_modalities(%{extensions: [:fts5]})
      assert :document in modalities
    end
  end

  describe "translate_results/2" do
    test "normalises SQLite row results" do
      raw = [%{"id" => "sqlite-001", "score" => 0.72, "title" => "Embedded"}]

      [result] = SQLite.translate_results(raw, @peer_info)

      assert result.hexad_id == "sqlite-001"
      assert result.score == 0.72
      assert result.source_store == "sqlite-test"
    end

    test "handles empty results" do
      assert SQLite.translate_results([], @peer_info) == []
    end
  end
end
