# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (@hyperpolymath) <j.d.a.jewell@open.ac.uk>

defmodule LithHttpWeb.Plugs.AuthenticateTest do
  @moduledoc """
  Tests for the Authenticate plug.
  Covers init options, auth bypass, public path checking, and auth flow.
  """

  use ExUnit.Case, async: false

  alias LithHttpWeb.Plugs.Authenticate

  # ============================================================
  # init/1
  # ============================================================

  describe "init/1" do
    test "sets default auth_enabled to false" do
      opts = Authenticate.init([])
      assert Keyword.get(opts, :auth_enabled) == false
    end

    test "preserves custom auth_enabled option" do
      opts = Authenticate.init(auth_enabled: true)
      assert Keyword.get(opts, :auth_enabled) == true
    end

    test "sets default public_paths" do
      opts = Authenticate.init([])
      public_paths = Keyword.get(opts, :public_paths)
      assert is_list(public_paths)
      assert "/health" in public_paths
      assert "/metrics" in public_paths
    end

    test "preserves custom public_paths" do
      custom = ["/custom", "/public"]
      opts = Authenticate.init(public_paths: custom)
      assert Keyword.get(opts, :public_paths) == custom
    end
  end

  # ============================================================
  # call/2 with auth disabled
  # ============================================================

  describe "call/2 with auth disabled" do
    test "passes through without modification when auth disabled" do
      conn = Plug.Test.conn(:get, "/api/v1/databases")
      opts = Authenticate.init(auth_enabled: false)
      result = Authenticate.call(conn, opts)
      # Connection should not be halted
      refute result.halted
    end
  end

  # ============================================================
  # call/2 with auth enabled (public paths)
  # ============================================================

  describe "call/2 with auth enabled on public paths" do
    test "allows public health path without auth" do
      conn = Plug.Test.conn(:get, "/health")
      opts = Authenticate.init(auth_enabled: true)
      result = Authenticate.call(conn, opts)
      refute result.halted
    end

    test "allows public metrics path without auth" do
      conn = Plug.Test.conn(:get, "/metrics")
      opts = Authenticate.init(auth_enabled: true)
      result = Authenticate.call(conn, opts)
      refute result.halted
    end

    test "allows paths starting with public prefix" do
      conn = Plug.Test.conn(:get, "/health/ready")
      opts = Authenticate.init(auth_enabled: true)
      result = Authenticate.call(conn, opts)
      refute result.halted
    end
  end
end
