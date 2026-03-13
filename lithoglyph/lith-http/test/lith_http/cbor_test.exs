# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (@hyperpolymath) <j.d.a.jewell@open.ac.uk>

defmodule LithHttp.CBORTest do
  @moduledoc """
  Tests for the CBOR (RFC 8949) encoder/decoder.
  Covers encoding and decoding of all supported types,
  round-trip consistency, and error handling.
  """

  use ExUnit.Case, async: true

  alias LithHttp.CBOR

  # ============================================================
  # Encoding: Unsigned Integers (Major Type 0)
  # ============================================================

  describe "encode unsigned integers" do
    test "encodes small integers (0-23) as single byte" do
      assert {:ok, <<0>>} = CBOR.encode(0)
      assert {:ok, <<1>>} = CBOR.encode(1)
      assert {:ok, <<23>>} = CBOR.encode(23)
    end

    test "encodes 1-byte integers (24-255)" do
      assert {:ok, <<0x18, 24>>} = CBOR.encode(24)
      assert {:ok, <<0x18, 255>>} = CBOR.encode(255)
    end

    test "encodes 2-byte integers (256-65535)" do
      assert {:ok, <<0x19, 1, 0>>} = CBOR.encode(256)
      assert {:ok, <<0x19, 0xFF, 0xFF>>} = CBOR.encode(65535)
    end

    test "encodes 4-byte integers" do
      assert {:ok, <<0x1A, 0, 1, 0, 0>>} = CBOR.encode(65536)
    end

    test "encodes 8-byte integers" do
      assert {:ok, <<0x1B, _::binary-size(8)>>} = CBOR.encode(5_000_000_000)
    end
  end

  # ============================================================
  # Encoding: Negative Integers (Major Type 1)
  # ============================================================

  describe "encode negative integers" do
    test "encodes small negatives (-1 to -24)" do
      assert {:ok, <<0x20>>} = CBOR.encode(-1)
      assert {:ok, <<0x21>>} = CBOR.encode(-2)
      assert {:ok, <<0x37>>} = CBOR.encode(-24)
    end

    test "encodes 1-byte negatives (-25 to -256)" do
      assert {:ok, <<0x38, 24>>} = CBOR.encode(-25)
      assert {:ok, <<0x38, 255>>} = CBOR.encode(-256)
    end

    test "encodes 2-byte negatives" do
      assert {:ok, <<0x39, 1, 0>>} = CBOR.encode(-257)
    end
  end

  # ============================================================
  # Encoding: Strings (Major Type 3)
  # ============================================================

  describe "encode strings" do
    test "encodes empty string" do
      assert {:ok, <<0x60>>} = CBOR.encode("")
    end

    test "encodes short strings (length < 24)" do
      assert {:ok, <<0x65, "hello">>} = CBOR.encode("hello")
    end

    test "encodes medium strings (length 24-255)" do
      str = String.duplicate("x", 30)
      assert {:ok, <<0x78, 30, _rest::binary>>} = CBOR.encode(str)
    end

    test "encodes UTF-8 strings correctly" do
      # Multi-byte UTF-8 characters
      assert {:ok, result} = CBOR.encode("cafe\u0301")
      assert is_binary(result)
    end
  end

  # ============================================================
  # Encoding: Arrays (Major Type 4)
  # ============================================================

  describe "encode arrays" do
    test "encodes empty array" do
      assert {:ok, <<0x80>>} = CBOR.encode([])
    end

    test "encodes array of integers" do
      assert {:ok, result} = CBOR.encode([1, 2, 3])
      assert is_binary(result)
      # Verify round-trip
      assert {:ok, [1, 2, 3]} = CBOR.decode(result)
    end

    test "encodes nested arrays" do
      assert {:ok, result} = CBOR.encode([[1, 2], [3, 4]])
      assert {:ok, [[1, 2], [3, 4]]} = CBOR.decode(result)
    end

    test "encodes mixed-type arrays" do
      assert {:ok, result} = CBOR.encode([1, "hello", true, nil])
      assert {:ok, [1, "hello", true, nil]} = CBOR.decode(result)
    end
  end

  # ============================================================
  # Encoding: Maps (Major Type 5)
  # ============================================================

  describe "encode maps" do
    test "encodes empty map" do
      assert {:ok, <<0xA0>>} = CBOR.encode(%{})
    end

    test "encodes simple map" do
      assert {:ok, result} = CBOR.encode(%{"key" => "value"})
      assert {:ok, %{"key" => "value"}} = CBOR.decode(result)
    end

    test "encodes map with atom keys (converted to strings)" do
      assert {:ok, result} = CBOR.encode(%{name: "test"})
      # Atom keys get converted to strings via to_string/1
      assert {:ok, %{"name" => "test"}} = CBOR.decode(result)
    end

    test "encodes nested maps" do
      input = %{"outer" => %{"inner" => 42}}
      assert {:ok, result} = CBOR.encode(input)
      assert {:ok, %{"outer" => %{"inner" => 42}}} = CBOR.decode(result)
    end

    test "encodes map with mixed value types" do
      input = %{"int" => 1, "str" => "hello", "bool" => true, "null" => nil}
      assert {:ok, result} = CBOR.encode(input)
      assert {:ok, decoded} = CBOR.decode(result)
      assert decoded["int"] == 1
      assert decoded["str"] == "hello"
      assert decoded["bool"] == true
      assert decoded["null"] == nil
    end
  end

  # ============================================================
  # Encoding: Floats (Major Type 7)
  # ============================================================

  describe "encode floats" do
    test "encodes float64" do
      assert {:ok, <<0xFB, _::binary-size(8)>>} = CBOR.encode(3.14)
    end

    test "encodes negative float" do
      assert {:ok, result} = CBOR.encode(-2.5)
      assert {:ok, -2.5} = CBOR.decode(result)
    end

    test "encodes zero float" do
      assert {:ok, result} = CBOR.encode(0.0)
      assert {:ok, decoded} = CBOR.decode(result)
      assert decoded == +0.0
    end
  end

  # ============================================================
  # Encoding: Special Values (Major Type 7)
  # ============================================================

  describe "encode special values" do
    test "encodes true" do
      assert {:ok, <<0xF5>>} = CBOR.encode(true)
    end

    test "encodes false" do
      assert {:ok, <<0xF4>>} = CBOR.encode(false)
    end

    test "encodes nil" do
      assert {:ok, <<0xF6>>} = CBOR.encode(nil)
    end
  end

  # ============================================================
  # Decoding: Round-trip tests
  # ============================================================

  describe "round-trip encode/decode" do
    test "round-trips integers" do
      for i <- [0, 1, 23, 24, 255, 256, 65535, 65536, 1_000_000] do
        assert {:ok, encoded} = CBOR.encode(i)
        assert {:ok, ^i} = CBOR.decode(encoded)
      end
    end

    test "round-trips negative integers" do
      for i <- [-1, -2, -24, -25, -256, -257, -65536] do
        assert {:ok, encoded} = CBOR.encode(i)
        assert {:ok, ^i} = CBOR.decode(encoded)
      end
    end

    test "round-trips strings" do
      for s <- ["", "a", "hello", String.duplicate("x", 100)] do
        assert {:ok, encoded} = CBOR.encode(s)
        assert {:ok, ^s} = CBOR.decode(encoded)
      end
    end

    test "round-trips complex structures" do
      input = %{
        "name" => "test_db",
        "version" => 1,
        "features" => ["geo", "timeseries"],
        "config" => %{"max_size" => 1024, "enabled" => true}
      }

      assert {:ok, encoded} = CBOR.encode(input)
      assert {:ok, decoded} = CBOR.decode(encoded)
      assert decoded["name"] == "test_db"
      assert decoded["version"] == 1
      assert decoded["features"] == ["geo", "timeseries"]
      assert decoded["config"]["max_size"] == 1024
      assert decoded["config"]["enabled"] == true
    end
  end

  # ============================================================
  # Decode from list
  # ============================================================

  describe "decode from list" do
    test "decodes from byte list" do
      assert {:ok, encoded} = CBOR.encode(42)
      byte_list = :binary.bin_to_list(encoded)
      assert {:ok, 42} = CBOR.decode(byte_list)
    end
  end

  # ============================================================
  # Error handling
  # ============================================================

  describe "decode error handling" do
    test "returns error for truncated binary" do
      # A 2-byte integer header with missing payload
      assert {:error, _reason} = CBOR.decode(<<0x19, 1>>)
    end

    test "returns error for empty binary" do
      assert {:error, _reason} = CBOR.decode(<<>>)
    end
  end
end
