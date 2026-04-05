defmodule QuandleDBNifTest do
  use ExUnit.Case

  test "semantic_lookup returns scaffold payload" do
    assert {:ok, payload} = QuandleDBNif.semantic_lookup("3_1")
    assert payload[:name] == "3_1"
    assert payload[:descriptor_version] == "stub-v1"
  end

  test "semantic_equivalents returns scaffold buckets" do
    assert {:ok, payload} = QuandleDBNif.semantic_equivalents("3_1")
    assert payload[:name] == "3_1"
    assert payload[:strong_candidates] == ["3_1"]
    assert payload[:weak_candidates] == []
    assert payload[:combined_candidates] == ["3_1"]
    assert payload[:count] == 1
  end

  test "wrapper validates argument type" do
    assert {:error, :invalid_argument} = QuandleDBNif.semantic_lookup(31)
    assert {:error, :invalid_argument} = QuandleDBNif.semantic_equivalents(:bad)
  end
end
