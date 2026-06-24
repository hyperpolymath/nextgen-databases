# SPDX-License-Identifier: MPL-2.0

defmodule VeriSimTest do
  use ExUnit.Case
  doctest VeriSim

  test "version returns string" do
    assert is_binary(VeriSim.version())
  end
end
