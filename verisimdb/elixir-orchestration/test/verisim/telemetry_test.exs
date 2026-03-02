# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim.TelemetryTest do
  @moduledoc """
  Tests for the telemetry collector and reporter.

  Verifies that:
  1. Collector aggregates counters and distributions correctly
  2. Reporter produces structured product insights
  3. Privacy guarantees are maintained (no PII, aggregate only)
  4. Telemetry opt-in gating works
  """

  use ExUnit.Case, async: false

  alias VeriSim.Telemetry.{Collector, Reporter}

  setup do
    # Ensure collector is started and reset before each test.
    case GenServer.whereis(Collector) do
      nil ->
        {:ok, _pid} = Collector.start_link()
        :ok
      _pid ->
        Collector.reset()
        :ok
    end

    # Temporarily enable telemetry for tests.
    prev = Application.get_env(:verisim, :telemetry_enabled, false)
    Application.put_env(:verisim, :telemetry_enabled, true)

    on_exit(fn ->
      Application.put_env(:verisim, :telemetry_enabled, prev)
      Collector.reset()
    end)

    :ok
  end

  # ── Collector Tests ─────────────────────────────────────────────────────

  describe "Collector" do
    test "increment/1 increases a counter by 1" do
      Collector.increment(:test_counter)
      Collector.increment(:test_counter)
      Collector.increment(:test_counter)

      snapshot = Collector.snapshot()
      assert snapshot[:test_counter] == 3
    end

    test "increment/2 increases a counter by specified amount" do
      Collector.increment(:batch_counter, 10)
      Collector.increment(:batch_counter, 5)

      snapshot = Collector.snapshot()
      assert snapshot[:batch_counter] == 15
    end

    test "increment_map/3 tracks sub-key counters" do
      Collector.increment_map(:modality_usage, :graph)
      Collector.increment_map(:modality_usage, :graph)
      Collector.increment_map(:modality_usage, :vector)
      Collector.increment_map(:modality_usage, :vector, 3)

      snapshot = Collector.snapshot()
      assert snapshot[{:modality_usage, :graph}] == 2
      assert snapshot[{:modality_usage, :vector}] == 4
    end

    test "record_distribution/2 tracks count, sum, min, max" do
      Collector.record_distribution(:query_duration, 10.0)
      Collector.record_distribution(:query_duration, 20.0)
      Collector.record_distribution(:query_duration, 5.0)

      # Give GenServer time to process casts.
      Process.sleep(50)

      snapshot = Collector.snapshot()
      assert snapshot[{:query_duration, :count}] == 3
      # Sum stored as integer * 1000 for precision
      assert snapshot[{:query_duration, :sum}] == 35_000
      assert snapshot[{:query_duration, :min}] == 5_000
      assert snapshot[{:query_duration, :max}] == 20_000
    end

    test "reset/0 clears all metrics" do
      Collector.increment(:counter_to_reset, 42)
      assert Collector.snapshot()[:counter_to_reset] == 42

      Collector.reset()
      assert Collector.snapshot() == %{}
    end

    test "snapshot/0 returns empty map when no metrics collected" do
      Collector.reset()
      assert Collector.snapshot() == %{}
    end

    test "enabled?/0 respects application config" do
      assert Collector.enabled?() == true

      Application.put_env(:verisim, :telemetry_enabled, false)
      # Also need to clear env var override
      prev_env = System.get_env("VERISIM_TELEMETRY")
      System.delete_env("VERISIM_TELEMETRY")

      refute Collector.enabled?()

      Application.put_env(:verisim, :telemetry_enabled, true)
      if prev_env, do: System.put_env("VERISIM_TELEMETRY", prev_env)
    end
  end

  # ── Reporter Tests ──────────────────────────────────────────────────────

  describe "Reporter" do
    test "report/0 returns structured map with all sections" do
      report = Reporter.report()

      assert is_map(report.meta)
      assert is_map(report.modality_heatmap)
      assert is_map(report.query_patterns)
      assert is_map(report.performance)
      assert is_map(report.drift)
      assert is_map(report.federation)
      assert is_map(report.proof_types)
      assert is_map(report.entities)
    end

    test "report/0 includes privacy notice" do
      report = Reporter.report()
      assert String.contains?(report.meta.privacy_notice, "aggregate metrics only")
      assert String.contains?(report.meta.privacy_notice, "No query content")
    end

    test "modality_heatmap/0 shows all 8 octad modalities" do
      heatmap = Reporter.modality_heatmap()

      assert Map.has_key?(heatmap.counts, :graph)
      assert Map.has_key?(heatmap.counts, :vector)
      assert Map.has_key?(heatmap.counts, :tensor)
      assert Map.has_key?(heatmap.counts, :semantic)
      assert Map.has_key?(heatmap.counts, :document)
      assert Map.has_key?(heatmap.counts, :temporal)
      assert Map.has_key?(heatmap.counts, :provenance)
      assert Map.has_key?(heatmap.counts, :spatial)
    end

    test "modality_heatmap/0 calculates percentages" do
      Collector.increment_map(:modality_usage, :graph, 3)
      Collector.increment_map(:modality_usage, :vector, 7)

      heatmap = Reporter.modality_heatmap()

      assert heatmap.total_modality_queries == 10
      assert heatmap.percentages[:graph] == 30.0
      assert heatmap.percentages[:vector] == 70.0
      assert heatmap.most_used == :vector
    end

    test "query_patterns/0 tracks statement types" do
      Collector.increment(:query_count, 5)
      Collector.increment(:query_error_count, 1)
      Collector.increment_map(:query_pattern, "SELECT", 3)
      Collector.increment_map(:query_pattern, "INSERT", 2)

      patterns = Reporter.query_patterns()

      assert patterns.total_queries == 5
      assert patterns.error_count == 1
      assert patterns.error_rate == 20.0
      assert patterns.by_type["SELECT"] == 3
      assert patterns.by_type["INSERT"] == 2
    end

    test "performance_summary/0 reports duration statistics" do
      Collector.record_distribution(:query_duration, 10.0)
      Collector.record_distribution(:query_duration, 30.0)
      Process.sleep(50)

      perf = Reporter.performance_summary()

      assert perf.query_count == 2
      assert perf.avg_duration_ms == 20.0
      assert perf.min_duration_ms == 10.0
      assert perf.max_duration_ms == 30.0
    end

    test "drift_report/0 tracks drift and normalisation" do
      Collector.increment(:drift_detected_count, 10)
      Collector.increment(:normalise_count, 8)
      Collector.increment(:normalise_success_count, 7)
      Collector.increment_map(:drift_modality_breakdown, :semantic, 5)
      Collector.increment_map(:drift_modality_breakdown, :graph, 3)

      drift = Reporter.drift_report()

      assert drift.drift_detected_count == 10
      assert drift.normalise_attempts == 8
      assert drift.normalise_success_count == 7
      assert drift.normalise_success_rate == 87.5
      assert drift.modality_breakdown[:semantic] == 5
      assert drift.most_drifted == :semantic
    end

    test "proof_type_usage/0 tracks VQL-DT adoption" do
      Collector.increment_map(:proof_type_usage, "EXISTENCE", 3)
      Collector.increment_map(:proof_type_usage, "INTEGRITY", 2)

      proofs = Reporter.proof_type_usage()

      assert proofs.total_proofs == 5
      assert proofs.vql_dt_active == true
      assert proofs.by_type["EXISTENCE"] == 3
    end

    test "entity_summary/0 tracks creates and deletes" do
      Collector.increment(:entity_created_count, 100)
      Collector.increment(:entity_deleted_count, 5)

      entities = Reporter.entity_summary()

      assert entities.created == 100
      assert entities.deleted == 5
    end

    test "report_json/0 returns valid JSON string" do
      json = Reporter.report_json()
      assert {:ok, decoded} = Jason.decode(json)
      assert is_map(decoded["meta"])
      assert is_map(decoded["modality_heatmap"])
    end
  end

  # ── Privacy Tests ───────────────────────────────────────────────────────

  describe "Privacy" do
    test "report never contains query content" do
      Collector.increment(:query_count, 1)
      Collector.increment_map(:query_pattern, "SELECT", 1)

      json = Reporter.report_json()

      # The report should never contain actual query strings.
      refute String.contains?(json, "SELECT GRAPH")
      refute String.contains?(json, "INSERT INTO")
      refute String.contains?(json, "entity-")
    end

    test "snapshot keys are only aggregate identifiers" do
      Collector.increment(:query_count)
      Collector.increment_map(:modality_usage, :graph)

      snapshot = Collector.snapshot()

      # All keys should be atoms or {atom, atom/string} tuples — never raw strings.
      Enum.each(snapshot, fn {key, _value} ->
        assert is_atom(key) or is_tuple(key),
          "Expected atom or tuple key, got: #{inspect(key)}"
      end)
    end
  end
end
