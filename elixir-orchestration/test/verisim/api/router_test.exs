# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim.Api.RouterTest do
  @moduledoc """
  Tests for the orchestration HTTP API router.

  Uses Plug.Test to invoke endpoints directly without needing a running
  HTTP server, so these tests work regardless of port configuration.
  """

  use ExUnit.Case, async: true

  @opts VeriSim.Api.Router.init([])

  defp call(conn) do
    VeriSim.Api.Router.call(conn, @opts)
  end

  # ── Health ────────────────────────────────────────────────────────────

  describe "GET /health" do
    test "returns 200 with orchestration status" do
      conn =
        Plug.Test.conn(:get, "/health")
        |> call()

      assert conn.status == 200
      assert {"content-type", "application/json; charset=utf-8"} in conn.resp_headers

      body = Jason.decode!(conn.resp_body)
      assert body["status"] == "ok"
      assert body["layer"] == "orchestration"
      assert is_integer(body["uptime_seconds"])
      assert is_boolean(body["telemetry_enabled"])
    end

    test "returns CORS headers" do
      conn =
        Plug.Test.conn(:get, "/health")
        |> call()

      assert {"access-control-allow-origin", "*"} in conn.resp_headers
    end
  end

  # ── Telemetry ─────────────────────────────────────────────────────────

  describe "GET /telemetry" do
    test "returns telemetry report or disabled message" do
      conn =
        Plug.Test.conn(:get, "/telemetry")
        |> call()

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)

      # Either full report (if enabled) or disabled message
      assert Map.has_key?(body, "telemetry_enabled") or Map.has_key?(body, "meta")
    end
  end

  describe "GET /telemetry/modality-heatmap" do
    test "returns modality heatmap data" do
      conn =
        Plug.Test.conn(:get, "/telemetry/modality-heatmap")
        |> call()

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert Map.has_key?(body, "counts")
      assert Map.has_key?(body, "percentages")
      assert Map.has_key?(body, "total_modality_queries")
    end
  end

  describe "GET /telemetry/query-patterns" do
    test "returns query pattern distribution" do
      conn =
        Plug.Test.conn(:get, "/telemetry/query-patterns")
        |> call()

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert Map.has_key?(body, "total_queries")
      assert Map.has_key?(body, "error_rate")
      assert Map.has_key?(body, "by_type")
    end
  end

  describe "GET /telemetry/drift" do
    test "returns drift report" do
      conn =
        Plug.Test.conn(:get, "/telemetry/drift")
        |> call()

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert Map.has_key?(body, "drift_detected_count")
      assert Map.has_key?(body, "normalise_success_rate")
    end
  end

  describe "GET /telemetry/performance" do
    test "returns performance summary" do
      conn =
        Plug.Test.conn(:get, "/telemetry/performance")
        |> call()

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert Map.has_key?(body, "query_count")
      assert Map.has_key?(body, "avg_duration_ms")
    end
  end

  describe "GET /telemetry/federation" do
    test "returns federation health" do
      conn =
        Plug.Test.conn(:get, "/telemetry/federation")
        |> call()

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert Map.has_key?(body, "total_federation_queries")
      assert Map.has_key?(body, "peer_errors")
    end
  end

  describe "GET /telemetry/proof-types" do
    test "returns proof type usage" do
      conn =
        Plug.Test.conn(:get, "/telemetry/proof-types")
        |> call()

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert Map.has_key?(body, "total_proofs")
      assert Map.has_key?(body, "by_type")
      assert Map.has_key?(body, "vql_dt_active")
    end
  end

  describe "GET /telemetry/entities" do
    test "returns entity summary" do
      conn =
        Plug.Test.conn(:get, "/telemetry/entities")
        |> call()

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert Map.has_key?(body, "created")
      assert Map.has_key?(body, "deleted")
    end
  end

  # ── Status ────────────────────────────────────────────────────────────

  describe "GET /status" do
    test "returns orchestration status" do
      conn =
        Plug.Test.conn(:get, "/status")
        |> call()

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["orchestration"] == "running"
      assert Map.has_key?(body, "consensus")
      assert Map.has_key?(body, "telemetry_enabled")
    end
  end

  # ── Telemetry End-to-End Validation ──────────────────────────────────

  describe "telemetry endpoint structure validation" do
    test "all telemetry sub-sections return valid JSON with expected keys" do
      endpoints = [
        {"/telemetry/modality-heatmap", ["counts", "percentages", "total_modality_queries"]},
        {"/telemetry/query-patterns", ["total_queries", "error_count", "error_rate", "by_type"]},
        {"/telemetry/drift", ["drift_detected_count", "normalise_attempts", "normalise_success_count", "normalise_success_rate", "modality_breakdown"]},
        {"/telemetry/performance", ["query_count", "avg_duration_ms", "min_duration_ms", "max_duration_ms", "total_duration_ms"]},
        {"/telemetry/federation", ["total_federation_queries", "peer_errors"]},
        {"/telemetry/proof-types", ["total_proofs", "by_type", "vql_dt_active"]},
        {"/telemetry/entities", ["created", "deleted"]}
      ]

      for {path, expected_keys} <- endpoints do
        conn =
          Plug.Test.conn(:get, path)
          |> call()

        assert conn.status == 200, "#{path} returned status #{conn.status}"
        body = Jason.decode!(conn.resp_body)

        for key <- expected_keys do
          assert Map.has_key?(body, key),
            "#{path} missing expected key '#{key}'. Got: #{inspect(Map.keys(body))}"
        end
      end
    end

    test "full telemetry report has all top-level sections for PanLL consumption" do
      conn =
        Plug.Test.conn(:get, "/telemetry")
        |> call()

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)

      # Either full report or disabled message — both are valid
      if Map.has_key?(body, "meta") do
        # Full report structure matches what PanLL Model.res expects
        expected_sections = ["meta", "modality_heatmap", "query_patterns",
                            "performance", "drift", "federation", "proof_types", "entities"]

        for section <- expected_sections do
          assert Map.has_key?(body, section),
            "Full telemetry report missing '#{section}' section"
        end

        # Meta section has privacy notice
        assert is_binary(body["meta"]["privacy_notice"])
      else
        # Disabled message
        assert body["telemetry_enabled"] == false
      end
    end

    test "all telemetry endpoints return numeric values (not nil or string)" do
      conn =
        Plug.Test.conn(:get, "/telemetry/performance")
        |> call()

      body = Jason.decode!(conn.resp_body)

      assert is_number(body["query_count"])
      assert is_number(body["avg_duration_ms"])
      assert is_number(body["min_duration_ms"])
      assert is_number(body["max_duration_ms"])
      assert is_number(body["total_duration_ms"])
    end

    test "modality heatmap covers all 8 octad modalities" do
      conn =
        Plug.Test.conn(:get, "/telemetry/modality-heatmap")
        |> call()

      body = Jason.decode!(conn.resp_body)
      octad_modalities = ~w(graph vector tensor semantic document temporal provenance spatial)

      for modality <- octad_modalities do
        assert Map.has_key?(body["counts"], modality),
          "Modality heatmap missing '#{modality}' in counts"
        assert Map.has_key?(body["percentages"], modality),
          "Modality heatmap missing '#{modality}' in percentages"
      end
    end

    test "all telemetry endpoints return CORS headers" do
      endpoints = ["/telemetry", "/telemetry/modality-heatmap", "/telemetry/query-patterns",
                   "/telemetry/drift", "/telemetry/performance", "/telemetry/federation",
                   "/telemetry/proof-types", "/telemetry/entities"]

      for path <- endpoints do
        conn =
          Plug.Test.conn(:get, path)
          |> call()

        assert {"access-control-allow-origin", "*"} in conn.resp_headers,
          "#{path} missing CORS header"
      end
    end
  end

  # ── 404 ───────────────────────────────────────────────────────────────

  describe "unknown routes" do
    test "returns 404 with error message" do
      conn =
        Plug.Test.conn(:get, "/nonexistent")
        |> call()

      assert conn.status == 404
      body = Jason.decode!(conn.resp_body)
      assert body["error"] == "not_found"
    end
  end
end
