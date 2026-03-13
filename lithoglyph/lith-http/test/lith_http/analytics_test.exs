# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (@hyperpolymath) <j.d.a.jewell@open.ac.uk>

defmodule LithHttp.AnalyticsTest do
  @moduledoc """
  Tests for LithHttp.Analytics module.
  Covers aggregation functions, interval parsing, and value validation.
  These are pure function tests that need no external services.
  """

  use ExUnit.Case, async: true

  alias LithHttp.Analytics

  # ============================================================
  # Aggregation functions
  # ============================================================

  describe "aggregate/2" do
    test "returns nil for empty list regardless of aggregation type" do
      assert nil == Analytics.aggregate([], :avg)
      assert nil == Analytics.aggregate([], :min)
      assert nil == Analytics.aggregate([], :max)
      assert nil == Analytics.aggregate([], :sum)
      assert nil == Analytics.aggregate([], :count)
    end

    test "computes average" do
      points = [%{value: 10.0}, %{value: 20.0}, %{value: 30.0}]
      assert Analytics.aggregate(points, :avg) == 20.0
    end

    test "computes average of single value" do
      points = [%{value: 42.0}]
      assert Analytics.aggregate(points, :avg) == 42.0
    end

    test "computes minimum" do
      points = [%{value: 30.0}, %{value: 10.0}, %{value: 20.0}]
      assert Analytics.aggregate(points, :min) == 10.0
    end

    test "computes maximum" do
      points = [%{value: 30.0}, %{value: 10.0}, %{value: 20.0}]
      assert Analytics.aggregate(points, :max) == 30.0
    end

    test "computes sum" do
      points = [%{value: 10.0}, %{value: 20.0}, %{value: 30.0}]
      assert Analytics.aggregate(points, :sum) == 60.0
    end

    test "computes count" do
      points = [%{value: 10.0}, %{value: 20.0}, %{value: 30.0}]
      assert Analytics.aggregate(points, :count) == 3
    end

    test "count returns 0 for empty list" do
      assert nil == Analytics.aggregate([], :count)
    end

    test ":none returns original points" do
      points = [%{value: 1.0}, %{value: 2.0}]
      assert Analytics.aggregate(points, :none) == points
    end

    test "handles negative values" do
      points = [%{value: -10.0}, %{value: -5.0}, %{value: -20.0}]
      assert Analytics.aggregate(points, :min) == -20.0
      assert Analytics.aggregate(points, :max) == -5.0
      assert Analytics.aggregate(points, :sum) == -35.0
      assert_in_delta Analytics.aggregate(points, :avg), -11.666, 0.01
    end

    test "handles mixed positive and negative values" do
      points = [%{value: -10.0}, %{value: 0.0}, %{value: 10.0}]
      assert Analytics.aggregate(points, :avg) == 0.0
      assert Analytics.aggregate(points, :min) == -10.0
      assert Analytics.aggregate(points, :max) == 10.0
      assert Analytics.aggregate(points, :sum) == 0.0
    end
  end

  # ============================================================
  # Interval parsing
  # ============================================================

  describe "parse_interval/1" do
    test "parses seconds" do
      assert {:ok, 1} = Analytics.parse_interval("1s")
      assert {:ok, 30} = Analytics.parse_interval("30s")
    end

    test "parses minutes" do
      assert {:ok, 60} = Analytics.parse_interval("1m")
      assert {:ok, 300} = Analytics.parse_interval("5m")
      assert {:ok, 900} = Analytics.parse_interval("15m")
    end

    test "parses hours" do
      assert {:ok, 3600} = Analytics.parse_interval("1h")
      assert {:ok, 43200} = Analytics.parse_interval("12h")
    end

    test "parses days" do
      assert {:ok, 86400} = Analytics.parse_interval("1d")
      assert {:ok, 604800} = Analytics.parse_interval("7d")
    end

    test "returns error for invalid format" do
      assert {:error, _} = Analytics.parse_interval("abc")
      assert {:error, _} = Analytics.parse_interval("")
      assert {:error, _} = Analytics.parse_interval("1w")
      assert {:error, _} = Analytics.parse_interval("m5")
      assert {:error, _} = Analytics.parse_interval("1.5h")
    end

    test "returns error for missing unit" do
      assert {:error, _} = Analytics.parse_interval("100")
    end

    test "returns error for missing number" do
      assert {:error, _} = Analytics.parse_interval("s")
    end
  end

  # ============================================================
  # Value validation
  # ============================================================

  describe "validate_value/1" do
    test "accepts integers" do
      assert :ok = Analytics.validate_value(42)
      assert :ok = Analytics.validate_value(0)
      assert :ok = Analytics.validate_value(-1)
    end

    test "accepts floats" do
      assert :ok = Analytics.validate_value(3.14)
      assert :ok = Analytics.validate_value(0.0)
      assert :ok = Analytics.validate_value(-2.5)
    end

    test "rejects strings" do
      assert {:error, _} = Analytics.validate_value("42")
    end

    test "rejects nil" do
      assert {:error, _} = Analytics.validate_value(nil)
    end

    test "rejects atoms" do
      assert {:error, _} = Analytics.validate_value(:foo)
    end

    test "rejects lists" do
      assert {:error, _} = Analytics.validate_value([1, 2, 3])
    end

    test "rejects maps" do
      assert {:error, _} = Analytics.validate_value(%{value: 1})
    end
  end

  # ============================================================
  # Provenance (PoC stub)
  # ============================================================

  describe "get_timeseries_provenance/2" do
    test "returns provenance summary for any series_id" do
      # PoC: always returns a dummy result
      assert {:ok, result} = Analytics.get_timeseries_provenance(make_ref(), "temp_sensor")
      assert result.series_id == "temp_sensor"
      assert is_map(result.provenance_summary)
      assert is_list(result.provenance_summary.sources)
    end
  end
end
