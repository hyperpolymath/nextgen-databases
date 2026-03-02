# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim.Federation.Adapters.ClickHouseTest do
  @moduledoc """
  Tests for the ClickHouse federation adapter.

  Validates modality declarations, ClickHouse HTTP protocol integration,
  and result normalisation from ClickHouse JSON output format.
  """

  use ExUnit.Case, async: true

  alias VeriSim.Federation.Adapters.ClickHouse

  @peer_info %{
    store_id: "ch-test",
    endpoint: "http://clickhouse:8123",
    adapter_config: %{database: "verisimdb", table: "hexads"}
  }

  describe "supported_modalities/1" do
    test "returns 5 supported modalities" do
      modalities = ClickHouse.supported_modalities(%{})

      assert :vector in modalities
      assert :document in modalities
      assert :temporal in modalities
      assert :spatial in modalities
      assert :semantic in modalities

      refute :graph in modalities
      refute :tensor in modalities
      refute :provenance in modalities
    end
  end

  describe "translate_results/2" do
    test "normalises ClickHouse JSON row format" do
      raw = [%{"id" => "ch-001", "score" => 0.65, "created_at" => "2026-02-28T12:00:00Z"}]

      [result] = ClickHouse.translate_results(raw, @peer_info)

      assert result.hexad_id == "ch-001"
      assert result.score == 0.65
      assert result.source_store == "ch-test"
    end

    test "handles empty results" do
      assert ClickHouse.translate_results([], @peer_info) == []
    end
  end
end
