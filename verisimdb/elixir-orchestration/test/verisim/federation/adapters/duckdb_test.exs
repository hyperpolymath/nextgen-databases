# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim.Federation.Adapters.DuckDBTest do
  @moduledoc """
  Tests for the DuckDB federation adapter.

  Validates extension-dependent modality declarations, SQL query
  construction for DuckDB-specific syntax, and result normalisation.
  """

  use ExUnit.Case, async: true

  alias VeriSim.Federation.Adapters.DuckDB

  @peer_info %{
    store_id: "duckdb-test",
    endpoint: "http://duckdb:8080",
    adapter_config: %{path: ":memory:", table: "hexads"}
  }

  describe "supported_modalities/1" do
    test "base modalities without extensions" do
      modalities = DuckDB.supported_modalities(%{extensions: []})

      assert :graph in modalities
      assert :temporal in modalities
      assert :semantic in modalities
      assert :tensor in modalities
      refute :document in modalities
      refute :vector in modalities
      refute :spatial in modalities
    end

    test "with all extensions" do
      modalities = DuckDB.supported_modalities(%{extensions: [:hnsw, :fts, :spatial]})

      assert :vector in modalities
      assert :spatial in modalities
      assert length(modalities) == 7
    end
  end

  describe "translate_results/2" do
    test "normalises SQL row results" do
      raw = [%{"id" => "duck-001", "score" => 0.77, "title" => "Analytics"}]

      [result] = DuckDB.translate_results(raw, @peer_info)

      assert result.hexad_id == "duck-001"
      assert result.score == 0.77
      assert result.source_store == "duckdb-test"
    end

    test "handles empty results" do
      assert DuckDB.translate_results([], @peer_info) == []
    end
  end
end
