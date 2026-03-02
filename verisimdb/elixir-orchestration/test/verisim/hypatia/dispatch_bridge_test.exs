# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim.Hypatia.DispatchBridgeTest do
  @moduledoc """
  Tests for the Hypatia dispatch bridge module.

  Verifies that the bridge correctly:
  1. Reads pending dispatch actions from JSONL files
  2. Reads dispatch logs and outcomes
  3. Computes dispatch summaries
  4. Feeds outcomes back for drift tracking
  """

  use ExUnit.Case, async: true

  alias VeriSim.Hypatia.DispatchBridge

  setup do
    dir = Path.join(System.tmp_dir!(), "hypatia_dispatch_#{System.unique_integer([:positive])}")
    dispatch_dir = Path.join(dir, "dispatch")
    outcomes_dir = Path.join(dir, "outcomes")
    File.mkdir_p!(dispatch_dir)
    File.mkdir_p!(outcomes_dir)

    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, data_path: dir, dispatch_dir: dispatch_dir, outcomes_dir: outcomes_dir}
  end

  # ===========================================================================
  # Sample Data Helpers
  # ===========================================================================

  defp write_jsonl(path, records) do
    lines = Enum.map_join(records, "\n", &Jason.encode!/1)
    File.write!(path, lines <> "\n")
  end

  defp sample_pending do
    [
      %{"repo" => "echidna", "pattern" => "PA001", "strategy" => "auto_execute", "confidence" => 0.98,
        "mutation" => "mutation { createPR(repo: \"echidna\") }"},
      %{"repo" => "ambientops", "pattern" => "PA003", "strategy" => "review", "confidence" => 0.87,
        "mutation" => "mutation { createPR(repo: \"ambientops\") }"},
      %{"repo" => "verisimdb", "pattern" => "PA001", "strategy" => "auto_execute", "confidence" => 0.96,
        "mutation" => "mutation { createPR(repo: \"verisimdb\") }"}
    ]
  end

  defp sample_dispatch_log do
    [
      %{"repo" => "echidna", "pattern" => "PA001", "strategy" => "auto_execute",
        "status" => "dispatched", "timestamp" => "2026-02-12T10:00:00Z"},
      %{"repo" => "proven", "pattern" => "PA005", "strategy" => "report_only",
        "status" => "dispatched", "timestamp" => "2026-02-12T10:01:00Z"},
      %{"repo" => "ambientops", "pattern" => "PA003", "strategy" => "review",
        "status" => "dispatched", "timestamp" => "2026-02-12T10:02:00Z"}
    ]
  end

  defp sample_outcomes do
    [
      %{"repo" => "echidna", "pattern" => "PA001", "status" => "success",
        "timestamp" => "2026-02-12T11:00:00Z"},
      %{"repo" => "proven", "pattern" => "PA005", "status" => "success",
        "timestamp" => "2026-02-12T11:01:00Z"},
      %{"repo" => "ambientops", "pattern" => "PA003", "status" => "failure",
        "timestamp" => "2026-02-12T11:02:00Z"}
    ]
  end

  # ===========================================================================
  # read_pending/1
  # ===========================================================================

  describe "read_pending/1" do
    test "reads pending actions from JSONL", %{data_path: dp, dispatch_dir: dd} do
      write_jsonl(Path.join(dd, "pending.jsonl"), sample_pending())

      assert {:ok, actions} = DispatchBridge.read_pending(dp)
      assert length(actions) == 3
      assert hd(actions)["repo"] == "echidna"
    end

    test "returns error when file missing", %{data_path: dp} do
      assert {:error, _} = DispatchBridge.read_pending(dp)
    end
  end

  # ===========================================================================
  # read_dispatch_log/2
  # ===========================================================================

  describe "read_dispatch_log/2" do
    test "reads dispatch log for a specific date", %{data_path: dp, dispatch_dir: dd} do
      write_jsonl(Path.join(dd, "dispatch-2026-02-12.jsonl"), sample_dispatch_log())

      assert {:ok, records} = DispatchBridge.read_dispatch_log(dp, "2026-02-12")
      assert length(records) == 3
    end

    test "returns error for non-existent date", %{data_path: dp} do
      assert {:error, _} = DispatchBridge.read_dispatch_log(dp, "2099-01-01")
    end
  end

  # ===========================================================================
  # read_all_dispatch_logs/1
  # ===========================================================================

  describe "read_all_dispatch_logs/1" do
    test "reads all dispatch logs", %{data_path: dp, dispatch_dir: dd} do
      write_jsonl(Path.join(dd, "dispatch-2026-02-12.jsonl"), sample_dispatch_log())
      write_jsonl(Path.join(dd, "dispatch-2026-02-13.jsonl"), [
        %{"repo" => "verisimdb", "pattern" => "PA001", "strategy" => "auto_execute"}
      ])

      assert {:ok, records} = DispatchBridge.read_all_dispatch_logs(dp)
      assert length(records) == 4
    end

    test "ignores non-dispatch files", %{data_path: dp, dispatch_dir: dd} do
      write_jsonl(Path.join(dd, "dispatch-2026-02-12.jsonl"), sample_dispatch_log())
      File.write!(Path.join(dd, "pending.jsonl"), "")

      assert {:ok, records} = DispatchBridge.read_all_dispatch_logs(dp)
      assert length(records) == 3
    end
  end

  # ===========================================================================
  # read_outcomes/1
  # ===========================================================================

  describe "read_outcomes/1" do
    test "reads outcome files", %{data_path: dp, outcomes_dir: od} do
      write_jsonl(Path.join(od, "2026-02.jsonl"), sample_outcomes())

      assert {:ok, outcomes} = DispatchBridge.read_outcomes(dp)
      assert length(outcomes) == 3
    end
  end

  # ===========================================================================
  # summarize/1
  # ===========================================================================

  describe "summarize/1" do
    test "aggregates dispatch statistics", %{
      data_path: dp,
      dispatch_dir: dd,
      outcomes_dir: od
    } do
      write_jsonl(Path.join(dd, "pending.jsonl"), sample_pending())
      write_jsonl(Path.join(dd, "dispatch-2026-02-12.jsonl"), sample_dispatch_log())
      write_jsonl(Path.join(od, "2026-02.jsonl"), sample_outcomes())

      summary = DispatchBridge.summarize(dp)

      assert summary.pending_count == 3
      assert summary.dispatched_count == 3
      assert summary.outcome_count == 3
      assert summary.outcome_success_rate == 66.7

      assert summary.by_strategy["auto_execute"] == 1
      assert summary.by_strategy["review"] == 1
      assert summary.by_strategy["report_only"] == 1

      assert summary.repos_with_pending == 3
    end

    test "handles empty data gracefully", %{data_path: dp} do
      summary = DispatchBridge.summarize(dp)

      assert summary.pending_count == 0
      assert summary.dispatched_count == 0
      assert summary.outcome_count == 0
    end
  end

  # ===========================================================================
  # feedback_to_drift/1
  # ===========================================================================

  describe "feedback_to_drift/1" do
    test "computes drift direction from outcomes", %{data_path: dp, outcomes_dir: od} do
      outcomes = [
        %{"repo" => "echidna", "status" => "success"},
        %{"repo" => "echidna", "status" => "success"},
        %{"repo" => "proven", "status" => "success"},
        %{"repo" => "proven", "status" => "failure"},
        %{"repo" => "ambientops", "status" => "failure"},
        %{"repo" => "ambientops", "status" => "failure"}
      ]

      write_jsonl(Path.join(od, "outcomes.jsonl"), outcomes)

      drift = DispatchBridge.feedback_to_drift(dp)

      # echidna: 2/2 success → improving
      echidna = Enum.find(drift, fn {repo, _, _} -> repo == "echidna" end)
      assert {_, :improving, %{successful: 2, total: 2}} = echidna

      # proven: 1/2 success → stable
      proven = Enum.find(drift, fn {repo, _, _} -> repo == "proven" end)
      assert {_, :stable, %{successful: 1, total: 2}} = proven

      # ambientops: 0/2 success → regressing
      ambientops = Enum.find(drift, fn {repo, _, _} -> repo == "ambientops" end)
      assert {_, :regressing, %{successful: 0, total: 2}} = ambientops
    end

    test "returns empty when no outcomes", %{data_path: dp} do
      drift = DispatchBridge.feedback_to_drift(dp)
      assert drift == []
    end
  end
end
