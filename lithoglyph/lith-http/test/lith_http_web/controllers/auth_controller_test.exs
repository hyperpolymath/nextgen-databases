# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (@hyperpolymath) <j.d.a.jewell@open.ac.uk>

defmodule LithHttpWeb.AuthControllerTest do
  @moduledoc """
  Tests for the Auth controller endpoints (token generation and verification).
  """

  use LithHttpWeb.ConnCase

  @moduletag :capture_log

  setup do
    # Configure JWT for tests
    original_secret = Application.get_env(:lith_http, :jwt_secret)
    Application.put_env(:lith_http, :jwt_secret, "test_auth_controller_secret")
    Application.put_env(:lith_http, :jwt_issuer, "lith-http-test")
    Application.put_env(:lith_http, :jwt_expiration, 3600)

    on_exit(fn ->
      if original_secret, do: Application.put_env(:lith_http, :jwt_secret, original_secret),
        else: Application.delete_env(:lith_http, :jwt_secret)
    end)

    :ok
  end

  # ============================================================
  # POST /auth/token - Generate token
  # ============================================================

  describe "POST /auth/token" do
    test "generates token for valid credentials", %{conn: conn} do
      conn = post(conn, "/auth/token", %{
        "username" => "admin",
        "password" => "admin"
      })
      body = json_response(conn, 200)
      assert is_binary(body["token"])
      assert body["token_type"] == "Bearer"
      assert is_integer(body["expires_in"])
    end

    test "rejects invalid credentials", %{conn: conn} do
      conn = post(conn, "/auth/token", %{
        "username" => "admin",
        "password" => "wrong_password"
      })
      body = json_response(conn, 401)
      assert body["error"]["code"] == "INVALID_CREDENTIALS"
    end

    test "rejects missing credentials", %{conn: conn} do
      conn = post(conn, "/auth/token", %{})
      body = json_response(conn, 401)
      assert body["error"]["code"] == "INVALID_CREDENTIALS"
    end
  end

  # ============================================================
  # POST /auth/verify - Verify token
  # ============================================================

  describe "POST /auth/verify" do
    test "verifies a valid token", %{conn: conn} do
      # First generate a token
      conn1 = post(conn, "/auth/token", %{
        "username" => "admin",
        "password" => "admin"
      })
      %{"token" => token} = json_response(conn1, 200)

      # Then verify it
      conn2 = post(build_conn(), "/auth/verify", %{"token" => token})
      body = json_response(conn2, 200)
      assert body["valid"] == true
      assert is_map(body["claims"])
    end

    test "rejects invalid token", %{conn: conn} do
      conn = post(conn, "/auth/verify", %{"token" => "invalid.token.value"})
      body = json_response(conn, 200)
      assert body["valid"] == false
    end

    test "returns 400 for missing token", %{conn: conn} do
      conn = post(conn, "/auth/verify", %{})
      body = json_response(conn, 400)
      assert body["error"]["code"] == "MISSING_TOKEN"
    end
  end
end
