# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim.Federation.Adapters.ObjectStorageTest do
  @moduledoc """
  Tests for the unified ObjectStorage federation adapter.

  Validates modality declarations for MinIO/S3 backends,
  result normalisation from S3 API response format, and
  metadata-based query patterns.
  """

  use ExUnit.Case, async: true

  alias VeriSim.Federation.Adapters.ObjectStorage

  @peer_info %{
    store_id: "minio-test",
    endpoint: "http://minio:9000",
    adapter_config: %{bucket: "verisim-hexads", backend: :minio}
  }

  describe "supported_modalities/1" do
    test "returns 2 base supported modalities" do
      modalities = ObjectStorage.supported_modalities(%{})

      assert :document in modalities
      assert :semantic in modalities

      refute :temporal in modalities
      refute :provenance in modalities
      refute :graph in modalities
      refute :vector in modalities
      refute :tensor in modalities
      refute :spatial in modalities
    end
  end

  describe "translate_results/2" do
    test "normalises S3 ListObjects results" do
      raw = [
        %{
          "Key" => "hexads/obj-001.json",
          "LastModified" => "2026-02-28T12:00:00Z",
          "Size" => 1024,
          "ETag" => "\"abc123\""
        }
      ]

      [result] = ObjectStorage.translate_results(raw, @peer_info)

      assert result.hexad_id == "obj-001"
      assert result.source_store == "minio-test"
    end

    test "handles empty results" do
      assert ObjectStorage.translate_results([], @peer_info) == []
    end
  end
end
