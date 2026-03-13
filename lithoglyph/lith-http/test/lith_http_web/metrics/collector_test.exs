# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (@hyperpolymath) <j.d.a.jewell@open.ac.uk>

defmodule LithHttpWeb.Metrics.CollectorTest do
  @moduledoc """
  Tests for the Metrics.Collector GenServer.
  Covers counter increments, value recording, and Prometheus export.
  """

  use ExUnit.Case, async: false

  alias LithHttpWeb.Metrics.Collector

  @moduletag :capture_log

  # ============================================================
  # Counter operations
  # ============================================================

  describe "increment_counter/3" do
    test "increments a new counter from 0" do
      Collector.increment_counter(:test_requests_total, %{method: "GET"})
      metrics = Collector.get_all_metrics()
      found = Enum.find(metrics, fn {name, labels, _val} ->
        name == :test_requests_total and labels == %{method: "GET"}
      end)
      assert found != nil
      {_, _, val} = found
      assert val >= 1
    end

    test "increments counter by specified value" do
      Collector.increment_counter(:test_bytes_total, %{}, 100)
      Collector.increment_counter(:test_bytes_total, %{}, 200)
      metrics = Collector.get_all_metrics()
      found = Enum.find(metrics, fn {name, _, _} -> name == :test_bytes_total end)
      assert found != nil
      {_, _, val} = found
      assert val >= 300
    end

    test "tracks different label sets independently" do
      Collector.increment_counter(:test_status, %{code: "200"})
      Collector.increment_counter(:test_status, %{code: "404"})
      Collector.increment_counter(:test_status, %{code: "200"})

      metrics = Collector.get_all_metrics()
      ok_count = Enum.find(metrics, fn {n, l, _} ->
        n == :test_status and l == %{code: "200"}
      end)
      not_found_count = Enum.find(metrics, fn {n, l, _} ->
        n == :test_status and l == %{code: "404"}
      end)

      assert ok_count != nil
      assert not_found_count != nil
      {_, _, ok_val} = ok_count
      {_, _, nf_val} = not_found_count
      assert ok_val >= 2
      assert nf_val >= 1
    end
  end

  # ============================================================
  # Value recording
  # ============================================================

  describe "record_value/3" do
    test "records a gauge value" do
      Collector.record_value(:test_latency_ms, %{endpoint: "/health"}, 42)
      # Give the async cast time to process
      Process.sleep(50)

      metrics = Collector.get_all_metrics()
      found = Enum.find(metrics, fn {name, labels, _val} ->
        name == :test_latency_ms and labels == %{endpoint: "/health"}
      end)
      assert found != nil
      {_, _, val} = found
      assert val == 42
    end
  end

  # ============================================================
  # Prometheus export
  # ============================================================

  describe "export_prometheus/0" do
    test "returns a string in Prometheus text format" do
      Collector.increment_counter(:prom_test_metric, %{label: "val"})
      Process.sleep(50)

      text = Collector.export_prometheus()
      assert is_binary(text)
      assert String.contains?(text, "# HELP")
      assert String.contains?(text, "# TYPE")
    end
  end

  # ============================================================
  # get_all_metrics/0
  # ============================================================

  describe "get_all_metrics/0" do
    test "returns list of {metric, labels, value} tuples" do
      Collector.increment_counter(:gam_test, %{})
      metrics = Collector.get_all_metrics()
      assert is_list(metrics)
      assert Enum.all?(metrics, fn {name, labels, value} ->
        (is_atom(name) or is_binary(name)) and is_map(labels) and (is_number(value) or is_binary(value))
      end)
    end
  end
end
