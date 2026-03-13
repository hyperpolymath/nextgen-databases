# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (@hyperpolymath) <j.d.a.jewell@open.ac.uk>

defmodule LithHttpWeb.Auth.JWTTest do
  @moduledoc """
  Tests for JWT token generation, verification, and extraction.
  """

  use ExUnit.Case, async: false

  alias LithHttpWeb.Auth.JWT

  # ============================================================
  # Setup: configure JWT secret for tests
  # ============================================================

  setup do
    # Save original config
    original_secret = Application.get_env(:lith_http, :jwt_secret)
    original_issuer = Application.get_env(:lith_http, :jwt_issuer)
    original_expiration = Application.get_env(:lith_http, :jwt_expiration)

    # Set test config
    Application.put_env(:lith_http, :jwt_secret, "test_secret_key_for_hmac256")
    Application.put_env(:lith_http, :jwt_issuer, "lith-http-test")
    Application.put_env(:lith_http, :jwt_expiration, 3600)

    on_exit(fn ->
      if original_secret, do: Application.put_env(:lith_http, :jwt_secret, original_secret),
        else: Application.delete_env(:lith_http, :jwt_secret)
      if original_issuer, do: Application.put_env(:lith_http, :jwt_issuer, original_issuer),
        else: Application.delete_env(:lith_http, :jwt_issuer)
      if original_expiration, do: Application.put_env(:lith_http, :jwt_expiration, original_expiration),
        else: Application.delete_env(:lith_http, :jwt_expiration)
    end)

    :ok
  end

  # ============================================================
  # Token generation
  # ============================================================

  describe "generate_token/2" do
    test "generates a valid JWT token" do
      assert {:ok, token} = JWT.generate_token("user@example.com")
      assert is_binary(token)
      # JWT format: header.payload.signature
      parts = String.split(token, ".")
      assert length(parts) == 3
    end

    test "includes subject in claims" do
      {:ok, token} = JWT.generate_token("admin")
      {:ok, claims} = JWT.verify_token(token)
      assert claims["sub"] == "admin"
    end

    test "includes iat, exp, and iss claims" do
      {:ok, token} = JWT.generate_token("user1")
      {:ok, claims} = JWT.verify_token(token)

      assert is_integer(claims["iat"])
      assert is_integer(claims["exp"])
      assert claims["iss"] == "lith-http-test"
      assert claims["exp"] > claims["iat"]
    end

    test "merges custom claims" do
      custom = %{"role" => "admin", "db_access" => ["db1", "db2"]}
      {:ok, token} = JWT.generate_token("user1", custom)
      {:ok, claims} = JWT.verify_token(token)

      assert claims["role"] == "admin"
      assert claims["db_access"] == ["db1", "db2"]
    end

    test "returns error when secret not configured" do
      Application.delete_env(:lith_http, :jwt_secret)
      assert {:error, :jwt_secret_not_configured} = JWT.generate_token("user")
    end
  end

  # ============================================================
  # Token verification
  # ============================================================

  describe "verify_token/1" do
    test "verifies a valid token" do
      {:ok, token} = JWT.generate_token("valid_user")
      assert {:ok, claims} = JWT.verify_token(token)
      assert claims["sub"] == "valid_user"
    end

    test "rejects token with invalid signature" do
      {:ok, token} = JWT.generate_token("user")
      # Tamper with the signature
      [header, payload, _sig] = String.split(token, ".")
      tampered = "#{header}.#{payload}.invalid_signature"
      assert {:error, :invalid_signature} = JWT.verify_token(tampered)
    end

    test "rejects expired token" do
      # Generate token that expired 10 seconds ago by using negative expiration
      # We must manually craft the claims since the API uses seconds from now
      Application.put_env(:lith_http, :jwt_expiration, -10)
      {:ok, token} = JWT.generate_token("expired_user")
      assert {:error, :token_expired} = JWT.verify_token(token)
    end

    test "rejects malformed token (wrong number of parts)" do
      assert {:error, :invalid_token_format} = JWT.verify_token("not.a.valid.token.format")
      assert {:error, :invalid_token_format} = JWT.verify_token("single_part")
    end

    test "returns error when secret not configured" do
      Application.delete_env(:lith_http, :jwt_secret)
      assert {:error, :jwt_secret_not_configured} = JWT.verify_token("some.token.here")
    end
  end

  # ============================================================
  # Token extraction from header
  # ============================================================

  describe "extract_token_from_header/1" do
    test "extracts token from valid Bearer header" do
      assert {:ok, "mytoken123"} = JWT.extract_token_from_header("Bearer mytoken123")
    end

    test "trims whitespace from token" do
      assert {:ok, "mytoken"} = JWT.extract_token_from_header("Bearer   mytoken  ")
    end

    test "rejects non-Bearer authorization" do
      assert {:error, :invalid_authorization_header} = JWT.extract_token_from_header("Basic dXNlcjpwYXNz")
    end

    test "rejects empty string" do
      assert {:error, :invalid_authorization_header} = JWT.extract_token_from_header("")
    end

    test "rejects nil-like inputs" do
      assert {:error, :invalid_authorization_header} = JWT.extract_token_from_header("Token abc")
    end
  end

  # ============================================================
  # Round-trip: generate then verify
  # ============================================================

  describe "round-trip token flow" do
    test "generated token can be immediately verified" do
      {:ok, token} = JWT.generate_token("roundtrip_user", %{"scope" => "read"})
      {:ok, claims} = JWT.verify_token(token)

      assert claims["sub"] == "roundtrip_user"
      assert claims["scope"] == "read"
      assert claims["exp"] > System.system_time(:second)
    end
  end
end
