# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim.Federation.Adapters.InfluxDBTest do
  @moduledoc """
  Tests for the InfluxDB federation adapter.

  Validates modality declarations (time-series specialist),
  Flux query construction, and result normalisation from
  InfluxDB's annotated CSV or JSON response format.
  """

  use ExUnit.Case, async: true

  alias VeriSim.Federation.Adapters.InfluxDB

  @peer_info %{
    store_id: "influx-test",
    endpoint: "http://influxdb:8086",
    adapter_config: %{org: "verisim", bucket: "hexads", token: "test-token"}
  }

  describe "supported_modalities/1" do
    test "returns 2 supported modalities" do
      modalities = InfluxDB.supported_modalities(%{})

      assert :temporal in modalities
      assert :semantic in modalities

      refute :graph in modalities
      refute :vector in modalities
      refute :tensor in modalities
      refute :document in modalities
      refute :provenance in modalities
      refute :spatial in modalities
    end
  end

  describe "translate_results/2" do
    test "normalises InfluxDB time-series records" do
      raw = [
        %{
          "_measurement" => "hexad_events",
          "_time" => "2026-02-28T12:00:00Z",
          "_value" => 42.5,
          "entity_id" => "influx-001"
        }
      ]

      [result] = InfluxDB.translate_results(raw, @peer_info)

      assert result.hexad_id == "hexad_events:influx-001:2026-02-28T12:00:00Z"
      assert result.source_store == "influx-test"
    end

    test "handles empty results" do
      assert InfluxDB.translate_results([], @peer_info) == []
    end
  end
end
