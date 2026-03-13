# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (@hyperpolymath) <j.d.a.jewell@open.ac.uk>

defmodule LithHttpWeb.ApiControllerTest do
  @moduledoc """
  Tests for the core API controller endpoints.
  Covers database info lookup, journal retrieval, and block retrieval.
  Tests use the DatabaseRegistry to simulate stored handles where needed.
  """

  use LithHttpWeb.ConnCase

  alias LithHttp.DatabaseRegistry

  @moduletag :capture_log

  # ============================================================
  # GET /api/v1/databases/:db_id - Get database info
  # ============================================================

  describe "GET /api/v1/databases/:db_id" do
    test "returns 404 for non-existent database", %{conn: conn} do
      conn = get(conn, "/api/v1/databases/nonexistent_db_id")
      body = json_response(conn, 404)
      assert body["error"]["code"] == "NOT_FOUND"
    end

    test "returns database info for registered handle", %{conn: conn} do
      # Register a fake handle
      handle = make_ref()
      metadata = %{name: "test_api_db", description: "Test DB", path: "/tmp/test"}
      DatabaseRegistry.put("api_test_db_1", handle, metadata)

      conn = get(conn, "/api/v1/databases/api_test_db_1")
      body = json_response(conn, 200)
      assert body["db_id"] == "api_test_db_1"
      assert body["name"] == "test_api_db"
      assert body["description"] == "Test DB"
      assert body["status"] == "connected"

      # Clean up
      DatabaseRegistry.delete("api_test_db_1")
    end
  end

  # ============================================================
  # GET /api/v1/databases/:db_id/journal - Get journal
  # ============================================================

  describe "GET /api/v1/databases/:db_id/journal" do
    test "returns 404 for non-existent database", %{conn: conn} do
      conn = get(conn, "/api/v1/databases/nonexistent/journal")
      body = json_response(conn, 404)
      assert body["error"]["code"] == "NOT_FOUND"
    end
  end

  # ============================================================
  # GET /api/v1/databases/:db_id/blocks/:hash - Get block
  # ============================================================

  describe "GET /api/v1/databases/:db_id/blocks/:hash" do
    test "returns 501 not implemented", %{conn: conn} do
      conn = get(conn, "/api/v1/databases/any_db/blocks/any_hash")
      body = json_response(conn, 501)
      assert body["error"]["code"] == "NOT_IMPLEMENTED"
    end
  end

  # ============================================================
  # DELETE /api/v1/databases/:db_id - Delete database
  # ============================================================

  describe "DELETE /api/v1/databases/:db_id" do
    test "returns 404 for non-existent database", %{conn: conn} do
      conn = delete(conn, "/api/v1/databases/nonexistent")
      body = json_response(conn, 404)
      assert body["error"]["code"] == "NOT_FOUND"
    end
  end
end
