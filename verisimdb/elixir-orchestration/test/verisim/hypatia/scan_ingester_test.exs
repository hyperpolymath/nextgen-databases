# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim.Hypatia.ScanIngesterTest do
  @moduledoc """
  Tests for the Hypatia scan ingestion module.

  Verifies that the ingester correctly:
  1. Parses panic-attack JSON scan results
  2. Builds octad hexad entities with all modalities
  3. Handles various input formats and edge cases
  4. Ingests from files and directories
  5. Stores data locally when Rust core is unavailable
  """

  use ExUnit.Case, async: false

  alias VeriSim.Hypatia.ScanIngester

  setup do
    # Clean up ETS table between tests
    case :ets.info(:hypatia_scans) do
      :undefined -> :ok
      _ -> :ets.delete_all_objects(:hypatia_scans)
    end

    :ok
  end

  # ===========================================================================
  # Sample Data
  # ===========================================================================

  defp sample_scan do
    %{
      "assail_report" => %{
        "program_path" => "/var/mnt/eclipse/repos/protocol-squisher",
        "language" => "rust",
        "frameworks" => ["WebServer"],
        "weak_points" => [
          %{
            "category" => "PanicPath",
            "location" => "src/main.rs",
            "severity" => "Medium",
            "description" => "11 unwrap/expect calls in src/main.rs",
            "recommended_attack" => ["memory", "disk"]
          },
          %{
            "category" => "UnsafeCode",
            "location" => "src/ffi.rs",
            "severity" => "High",
            "description" => "unsafe block without SAFETY comment",
            "recommended_attack" => ["memory"]
          }
        ]
      }
    }
  end

  defp sample_scan_flat do
    %{
      "program_path" => "/repos/my-app",
      "language" => "elixir",
      "frameworks" => ["Phoenix"],
      "weak_points" => [
        %{
          "category" => "HotCodeReload",
          "location" => "lib/my_app/worker.ex",
          "severity" => "Low",
          "description" => "Hot code reload in production"
        }
      ]
    }
  end

  # ===========================================================================
  # ingest_scan/1
  # ===========================================================================

  describe "ingest_scan/1" do
    test "ingests standard panic-attack scan result" do
      assert {:ok, hexad_id} = ScanIngester.ingest_scan(sample_scan())
      assert String.starts_with?(hexad_id, "scan:protocol-squisher:")
    end

    test "ingests flat scan format (without assail_report wrapper)" do
      assert {:ok, hexad_id} = ScanIngester.ingest_scan(sample_scan_flat())
      assert String.starts_with?(hexad_id, "scan:my-app:")
    end

    test "builds hexad with correct metadata" do
      {:ok, hexad_id} = ScanIngester.ingest_scan(sample_scan())

      scans = ScanIngester.list_scans()
      scan = Enum.find(scans, &(&1.hexad_id == hexad_id))

      assert scan.metadata.repo_name == "protocol-squisher"
      assert scan.metadata.language == "rust"
      assert scan.metadata.frameworks == ["WebServer"]
      assert scan.metadata.weak_point_count == 2
      assert scan.metadata.severity_counts == %{"Medium" => 1, "High" => 1}
    end

    test "builds document modality with searchable text" do
      {:ok, hexad_id} = ScanIngester.ingest_scan(sample_scan())

      scans = ScanIngester.list_scans()
      scan = Enum.find(scans, &(&1.hexad_id == hexad_id))

      assert scan.document.title =~ "protocol-squisher"
      assert scan.document.body =~ "PanicPath"
      assert scan.document.body =~ "UnsafeCode"
      assert scan.document.body =~ "src/main.rs"
    end

    test "builds graph triples" do
      {:ok, hexad_id} = ScanIngester.ingest_scan(sample_scan())

      scans = ScanIngester.list_scans()
      scan = Enum.find(scans, &(&1.hexad_id == hexad_id))

      triples = scan.graph.triples
      assert length(triples) > 0

      # Should have repo → has_scan triple
      assert Enum.any?(triples, fn [s, p, _o] ->
               s == "repo:protocol-squisher" and p == "has_scan"
             end)

      # Should have weakness → in_file triples
      assert Enum.any?(triples, fn [_s, p, _o] -> p == "in_file" end)
    end

    test "builds semantic modality with categories" do
      {:ok, hexad_id} = ScanIngester.ingest_scan(sample_scan())

      scans = ScanIngester.list_scans()
      scan = Enum.find(scans, &(&1.hexad_id == hexad_id))

      assert "PanicPath" in scan.semantic.tags
      assert "UnsafeCode" in scan.semantic.tags
      assert "scan_result" in scan.semantic.types
    end

    test "builds provenance modality" do
      {:ok, hexad_id} = ScanIngester.ingest_scan(sample_scan())

      scans = ScanIngester.list_scans()
      scan = Enum.find(scans, &(&1.hexad_id == hexad_id))

      assert scan.provenance.source == "panic-attack"
      assert scan.provenance.operation == "assail"
    end

    test "rejects non-map input" do
      assert {:error, :invalid_scan_format} = ScanIngester.ingest_scan("not a map")
      assert {:error, :invalid_scan_format} = ScanIngester.ingest_scan(42)
    end
  end

  # ===========================================================================
  # ingest_file/1
  # ===========================================================================

  describe "ingest_file/1" do
    setup do
      dir = Path.join(System.tmp_dir!(), "hypatia_test_#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)
      {:ok, dir: dir}
    end

    test "ingests from a JSON file", %{dir: dir} do
      path = Path.join(dir, "test-scan.json")
      File.write!(path, Jason.encode!(sample_scan()))

      assert {:ok, hexad_id} = ScanIngester.ingest_file(path)
      assert String.starts_with?(hexad_id, "scan:")
    end

    test "returns error for non-existent file" do
      assert {:error, {:file_read_error, _}} = ScanIngester.ingest_file("/nonexistent/path.json")
    end

    test "returns error for invalid JSON", %{dir: dir} do
      path = Path.join(dir, "bad.json")
      File.write!(path, "not valid json {{{")

      assert {:error, {:json_parse_error, _}} = ScanIngester.ingest_file(path)
    end
  end

  # ===========================================================================
  # ingest_directory/1
  # ===========================================================================

  describe "ingest_directory/1" do
    setup do
      dir = Path.join(System.tmp_dir!(), "hypatia_dir_#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)
      {:ok, dir: dir}
    end

    test "ingests all JSON files from directory", %{dir: dir} do
      for i <- 1..3 do
        scan = put_in(sample_scan(), ["assail_report", "program_path"], "/repos/repo-#{i}")
        File.write!(Path.join(dir, "repo-#{i}.json"), Jason.encode!(scan))
      end

      assert {:ok, results} = ScanIngester.ingest_directory(dir)
      assert length(results) == 3
      assert Enum.all?(results, fn {_f, result} -> match?({:ok, _}, result) end)
    end

    test "skips non-JSON files", %{dir: dir} do
      File.write!(Path.join(dir, "readme.txt"), "ignore me")
      File.write!(Path.join(dir, "scan.json"), Jason.encode!(sample_scan()))

      assert {:ok, results} = ScanIngester.ingest_directory(dir)
      assert length(results) == 1
    end

    test "returns error for non-existent directory" do
      assert {:error, {:dir_read_error, _}} = ScanIngester.ingest_directory("/nonexistent/dir")
    end
  end

  # ===========================================================================
  # list_scans/0 and get_scan/1
  # ===========================================================================

  describe "list_scans/0" do
    test "returns empty list when no scans ingested" do
      assert ScanIngester.list_scans() == []
    end

    test "returns all ingested scans" do
      ScanIngester.ingest_scan(sample_scan())
      ScanIngester.ingest_scan(sample_scan_flat())

      scans = ScanIngester.list_scans()
      assert length(scans) == 2
    end
  end

  describe "get_scan/1" do
    test "finds scan by repo name" do
      ScanIngester.ingest_scan(sample_scan())

      assert {:ok, scan} = ScanIngester.get_scan("protocol-squisher")
      assert scan.metadata.language == "rust"
    end

    test "returns error for unknown repo" do
      assert {:error, :not_found} = ScanIngester.get_scan("nonexistent-repo")
    end
  end
end
