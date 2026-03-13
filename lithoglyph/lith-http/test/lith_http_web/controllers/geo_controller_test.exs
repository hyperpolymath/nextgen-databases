# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (@hyperpolymath) <j.d.a.jewell@open.ac.uk>

defmodule LithHttpWeb.GeoControllerTest do
  @moduledoc """
  Tests for the Geo controller endpoints.
  Covers input validation, not-found handling, and bounding box parsing.
  """

  use LithHttpWeb.ConnCase

  alias LithHttp.DatabaseRegistry

  @moduletag :capture_log

  # ============================================================
  # POST /api/v1/databases/:db_id/features - Insert feature
  # ============================================================

  describe "POST /api/v1/databases/:db_id/features" do
    test "returns 404 for non-existent database", %{conn: conn} do
      conn = post(conn, "/api/v1/databases/nonexistent/features", %{
        "geometry" => %{"type" => "Point", "coordinates" => [1.0, 2.0]}
      })
      body = json_response(conn, 404)
      assert body["error"]["code"] == "NOT_FOUND"
    end

    test "returns 400 for missing geometry", %{conn: conn} do
      handle = make_ref()
      DatabaseRegistry.put("geo_test_db_1", handle)

      conn = post(conn, "/api/v1/databases/geo_test_db_1/features", %{})
      body = json_response(conn, 400)
      assert body["error"]["code"] == "INVALID_REQUEST"

      DatabaseRegistry.delete("geo_test_db_1")
    end

    test "returns 400 for invalid geometry type", %{conn: conn} do
      handle = make_ref()
      DatabaseRegistry.put("geo_test_db_2", handle)

      conn = post(conn, "/api/v1/databases/geo_test_db_2/features", %{
        "geometry" => %{"type" => "Invalid", "coordinates" => [1.0, 2.0]}
      })
      body = json_response(conn, 400)
      assert body["error"]["code"] == "INVALID_REQUEST"

      DatabaseRegistry.delete("geo_test_db_2")
    end
  end

  # ============================================================
  # GET /api/v1/databases/:db_id/features/bbox - Query by bbox
  # ============================================================

  describe "GET /api/v1/databases/:db_id/features/bbox" do
    test "returns 404 for non-existent database", %{conn: conn} do
      conn = get(conn, "/api/v1/databases/nonexistent/features/bbox", %{
        "minx" => "0", "miny" => "0", "maxx" => "10", "maxy" => "10"
      })
      body = json_response(conn, 404)
      assert body["error"]["code"] == "NOT_FOUND"
    end

    test "returns 400 for missing bbox parameters", %{conn: conn} do
      handle = make_ref()
      DatabaseRegistry.put("geo_bbox_db_1", handle)

      conn = get(conn, "/api/v1/databases/geo_bbox_db_1/features/bbox", %{
        "minx" => "0"
        # Missing miny, maxx, maxy
      })
      body = json_response(conn, 400)
      assert body["error"]["code"] == "INVALID_REQUEST"

      DatabaseRegistry.delete("geo_bbox_db_1")
    end
  end

  # ============================================================
  # GET /api/v1/databases/:db_id/features/:feature_id - Get feature
  # ============================================================

  describe "GET /api/v1/databases/:db_id/features/:feature_id" do
    test "returns 404 for non-existent database", %{conn: conn} do
      conn = get(conn, "/api/v1/databases/nonexistent/features/feat_abc")
      body = json_response(conn, 404)
      assert body["error"]["code"] == "NOT_FOUND"
    end

    test "returns feature for registered database (PoC stub)", %{conn: conn} do
      handle = make_ref()
      DatabaseRegistry.put("geo_feat_db_1", handle)

      conn = get(conn, "/api/v1/databases/geo_feat_db_1/features/feat_abc")
      body = json_response(conn, 200)
      assert body["type"] == "Feature"
      assert body["id"] == "feat_abc"

      DatabaseRegistry.delete("geo_feat_db_1")
    end
  end

  # ============================================================
  # GET /api/v1/databases/:db_id/features/:feature_id/provenance
  # ============================================================

  describe "GET /api/v1/databases/:db_id/features/:feature_id/provenance" do
    test "returns 404 for non-existent database", %{conn: conn} do
      conn = get(conn, "/api/v1/databases/nonexistent/features/feat_abc/provenance")
      body = json_response(conn, 404)
      assert body["error"]["code"] == "NOT_FOUND"
    end

    test "returns provenance for registered database", %{conn: conn} do
      handle = make_ref()
      DatabaseRegistry.put("geo_prov_db_1", handle)

      conn = get(conn, "/api/v1/databases/geo_prov_db_1/features/feat_abc/provenance")
      body = json_response(conn, 200)
      assert body["feature_id"] == "feat_abc"
      assert is_list(body["provenance_chain"])

      DatabaseRegistry.delete("geo_prov_db_1")
    end
  end
end
