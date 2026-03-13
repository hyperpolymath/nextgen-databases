# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (@hyperpolymath) <j.d.a.jewell@open.ac.uk>

defmodule LithHttpWeb.Plugs.RateLimiterTest do
  @moduledoc """
  Tests for the RateLimiter plug.
  Covers init options and disabled-mode passthrough.
  """

  use ExUnit.Case, async: true

  alias LithHttpWeb.Plugs.RateLimiter

  # ============================================================
  # init/1
  # ============================================================

  describe "init/1" do
    test "sets default rate_limit_enabled to false" do
      opts = RateLimiter.init([])
      assert Keyword.get(opts, :rate_limit_enabled) == false
    end

    test "sets default rate_limit_per_minute" do
      opts = RateLimiter.init([])
      assert Keyword.get(opts, :rate_limit_per_minute) == 60
    end

    test "sets default burst" do
      opts = RateLimiter.init([])
      assert Keyword.get(opts, :rate_limit_burst) == 10
    end

    test "sets default window_seconds" do
      opts = RateLimiter.init([])
      assert Keyword.get(opts, :window_seconds) == 60
    end

    test "preserves custom options" do
      opts = RateLimiter.init(
        rate_limit_enabled: true,
        rate_limit_per_minute: 120,
        rate_limit_burst: 20,
        window_seconds: 30
      )
      assert Keyword.get(opts, :rate_limit_enabled) == true
      assert Keyword.get(opts, :rate_limit_per_minute) == 120
      assert Keyword.get(opts, :rate_limit_burst) == 20
      assert Keyword.get(opts, :window_seconds) == 30
    end
  end

  # ============================================================
  # call/2 with rate limiting disabled
  # ============================================================

  describe "call/2 with rate limiting disabled" do
    test "passes through without modification" do
      conn = Plug.Test.conn(:get, "/api/v1/databases")
      opts = RateLimiter.init(rate_limit_enabled: false)
      result = RateLimiter.call(conn, opts)
      refute result.halted
    end
  end
end
