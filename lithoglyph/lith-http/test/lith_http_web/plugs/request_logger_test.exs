# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (@hyperpolymath) <j.d.a.jewell@open.ac.uk>

defmodule LithHttpWeb.Plugs.RequestLoggerTest do
  @moduledoc """
  Tests for the RequestLogger plug.
  Covers init and registration of before_send callback.
  """

  use ExUnit.Case, async: true

  alias LithHttpWeb.Plugs.RequestLogger

  describe "init/1" do
    test "returns opts unchanged" do
      opts = [foo: :bar]
      assert RequestLogger.init(opts) == opts
    end
  end

  describe "call/2" do
    test "registers a before_send callback in private" do
      conn = Plug.Test.conn(:get, "/test")
      result = RequestLogger.call(conn, [])
      # The before_send list lives in conn.private
      assert length(result.private.before_send) > 0
    end

    test "does not halt the connection" do
      conn = Plug.Test.conn(:get, "/test")
      result = RequestLogger.call(conn, [])
      refute result.halted
    end
  end
end
