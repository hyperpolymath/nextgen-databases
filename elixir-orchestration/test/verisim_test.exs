# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSimTest do
  use ExUnit.Case
  doctest VeriSim

  test "version returns string" do
    assert is_binary(VeriSim.version())
  end
end
