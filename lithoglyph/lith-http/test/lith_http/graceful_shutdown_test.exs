# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (@hyperpolymath) <j.d.a.jewell@open.ac.uk>

defmodule LithHttp.GracefulShutdownTest do
  @moduledoc """
  Tests for the GracefulShutdown GenServer.
  Covers shutdown triggering and double-shutdown prevention.
  """

  use ExUnit.Case, async: false

  alias LithHttp.GracefulShutdown

  @moduletag :capture_log

  describe "shutdown/0" do
    test "returns :ok or already_shutting_down (singleton GenServer)" do
      # This is a singleton GenServer shared across tests. If another
      # test already triggered shutdown, we get :already_shutting_down.
      result = GracefulShutdown.shutdown()
      assert result in [:ok, {:error, :already_shutting_down}]
    end

    test "subsequent call returns already_shutting_down" do
      # After the first shutdown call, subsequent calls return error
      GracefulShutdown.shutdown()
      result = GracefulShutdown.shutdown()
      assert result == {:error, :already_shutting_down}
    end
  end
end
