# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (@hyperpolymath) <j.d.a.jewell@open.ac.uk>

defmodule LithHttpWeb.HealthControllerTest do
  @moduledoc """
  Tests for health check endpoints.
  These endpoints are public and require no database.
  """

  use LithHttpWeb.ConnCase

  @moduletag :capture_log

  describe "GET /health" do
    test "returns healthy status", %{conn: conn} do
      conn = get(conn, "/health")
      body = json_response(conn, 200)
      assert body["status"] == "healthy"
      assert body["service"] == "lith-http"
      assert is_binary(body["timestamp"])
    end
  end

  describe "GET /health/live" do
    test "returns alive status", %{conn: conn} do
      conn = get(conn, "/health/live")
      body = json_response(conn, 200)
      assert body["status"] == "alive"
      assert is_binary(body["timestamp"])
    end
  end

  describe "GET /health/ready" do
    test "returns ready or not_ready status", %{conn: conn} do
      conn = get(conn, "/health/ready")
      # NIF may or may not be loaded in test env, so accept either status code
      assert conn.status in [200, 503]
      body = json_response(conn, conn.status)
      assert body["status"] in ["ready", "not_ready"]
      assert is_map(body["checks"])
    end
  end
end
