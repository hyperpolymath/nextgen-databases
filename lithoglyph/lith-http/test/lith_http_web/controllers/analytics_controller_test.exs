# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (@hyperpolymath) <j.d.a.jewell@open.ac.uk>

defmodule LithHttpWeb.AnalyticsControllerTest do
  @moduledoc """
  Tests for the Analytics controller endpoints.
  Covers input validation, not-found handling, and parameter parsing.
  """

  use LithHttpWeb.ConnCase

  alias LithHttp.DatabaseRegistry

  @moduletag :capture_log

  # ============================================================
  # POST /api/v1/databases/:db_id/timeseries - Insert data
  # ============================================================

  describe "POST /api/v1/databases/:db_id/timeseries" do
    test "returns 404 for non-existent database", %{conn: conn} do
      conn = post(conn, "/api/v1/databases/nonexistent/timeseries", %{
        "series_id" => "temp",
        "timestamp" => "2026-01-01T00:00:00Z",
        "value" => 42.0
      })
      body = json_response(conn, 404)
      assert body["error"]["code"] == "NOT_FOUND"
    end

    test "returns 400 for missing series_id", %{conn: conn} do
      handle = make_ref()
      DatabaseRegistry.put("analytics_db_1", handle)

      conn = post(conn, "/api/v1/databases/analytics_db_1/timeseries", %{
        "timestamp" => "2026-01-01T00:00:00Z",
        "value" => 42.0
      })
      body = json_response(conn, 400)
      assert body["error"]["code"] == "INVALID_REQUEST"

      DatabaseRegistry.delete("analytics_db_1")
    end

    test "returns 400 for missing timestamp", %{conn: conn} do
      handle = make_ref()
      DatabaseRegistry.put("analytics_db_2", handle)

      conn = post(conn, "/api/v1/databases/analytics_db_2/timeseries", %{
        "series_id" => "temp",
        "value" => 42.0
      })
      body = json_response(conn, 400)
      assert body["error"]["code"] == "INVALID_REQUEST"

      DatabaseRegistry.delete("analytics_db_2")
    end

    test "returns 400 for missing value", %{conn: conn} do
      handle = make_ref()
      DatabaseRegistry.put("analytics_db_3", handle)

      conn = post(conn, "/api/v1/databases/analytics_db_3/timeseries", %{
        "series_id" => "temp",
        "timestamp" => "2026-01-01T00:00:00Z"
      })
      body = json_response(conn, 400)
      assert body["error"]["code"] == "INVALID_REQUEST"

      DatabaseRegistry.delete("analytics_db_3")
    end

    test "returns 400 for invalid timestamp format", %{conn: conn} do
      handle = make_ref()
      DatabaseRegistry.put("analytics_db_4", handle)

      conn = post(conn, "/api/v1/databases/analytics_db_4/timeseries", %{
        "series_id" => "temp",
        "timestamp" => "not-a-timestamp",
        "value" => 42.0
      })
      body = json_response(conn, 400)
      assert body["error"]["code"] == "INVALID_REQUEST"

      DatabaseRegistry.delete("analytics_db_4")
    end

    test "returns 400 for non-numeric value", %{conn: conn} do
      handle = make_ref()
      DatabaseRegistry.put("analytics_db_5", handle)

      conn = post(conn, "/api/v1/databases/analytics_db_5/timeseries", %{
        "series_id" => "temp",
        "timestamp" => "2026-01-01T00:00:00Z",
        "value" => "not_a_number"
      })
      body = json_response(conn, 400)
      assert body["error"]["code"] == "INVALID_REQUEST"

      DatabaseRegistry.delete("analytics_db_5")
    end
  end

  # ============================================================
  # GET /api/v1/databases/:db_id/timeseries/:series_id - Query
  # ============================================================

  describe "GET /api/v1/databases/:db_id/timeseries/:series_id" do
    test "returns 404 for non-existent database", %{conn: conn} do
      conn = get(conn, "/api/v1/databases/nonexistent/timeseries/temp")
      body = json_response(conn, 404)
      assert body["error"]["code"] == "NOT_FOUND"
    end
  end

  # ============================================================
  # GET .../timeseries/:series_id/provenance
  # ============================================================

  describe "GET /api/v1/databases/:db_id/timeseries/:series_id/provenance" do
    test "returns 404 for non-existent database", %{conn: conn} do
      conn = get(conn, "/api/v1/databases/nonexistent/timeseries/temp/provenance")
      body = json_response(conn, 404)
      assert body["error"]["code"] == "NOT_FOUND"
    end

    test "returns provenance for registered database", %{conn: conn} do
      handle = make_ref()
      DatabaseRegistry.put("analytics_prov_db", handle)

      conn = get(conn, "/api/v1/databases/analytics_prov_db/timeseries/temp/provenance")
      body = json_response(conn, 200)
      assert body["series_id"] == "temp"
      assert is_map(body["provenance_summary"])

      DatabaseRegistry.delete("analytics_prov_db")
    end
  end

  # ============================================================
  # GET .../timeseries/:series_id/latest
  # ============================================================

  describe "GET /api/v1/databases/:db_id/timeseries/:series_id/latest" do
    test "returns 404 for non-existent database", %{conn: conn} do
      conn = get(conn, "/api/v1/databases/nonexistent/timeseries/temp/latest")
      body = json_response(conn, 404)
      assert body["error"]["code"] == "NOT_FOUND"
    end
  end
end
