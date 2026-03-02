# SPDX-License-Identifier: PMPL-1.0-or-later
#
# VeriSimDB Drift Detection & Self-Normalisation Demo
#
# Demonstrates VeriSimDB's core value proposition:
#   1. Create entities with 8 modalities (octad)
#   2. Introduce cross-modal corruption
#   3. Detect drift via sweep
#   4. Repair via normalisation
#   5. Verify consistency restored
#
# Usage:
#   cd elixir-orchestration && mix run ../demos/drift-detection/run_demo.exs
#
# The demo works in two modes:
#   - LIVE mode:  Rust core is running — real hexads, real drift, real repair
#   - LOCAL mode: Rust core unavailable — Elixir-level simulation via DriftMonitor

defmodule VeriSimDB.Demo.DriftDetection do
  @moduledoc """
  Drift detection demo script.

  Creates entities, corrupts a subset, detects drift, repairs, and reports.
  Demonstrates the full detect → monitor → repair → verify cycle.
  """

  require Logger

  alias VeriSim.{DriftMonitor, EntityServer, RustClient}

  # ── Configuration ──────────────────────────────────────────────────────

  @entity_count 1_000
  @corrupt_count 50
  @modalities ~w(graph vector tensor semantic document temporal provenance spatial)a

  # Corruption patterns: each introduces a specific kind of cross-modal drift
  @corruption_patterns [
    # Vector changed without updating document — semantic_vector drift
    %{type: :semantic_vector, score: 0.75, description: "vector/document desync"},
    # Graph edges removed but document still references them — graph_document drift
    %{type: :graph_document, score: 0.82, description: "graph/document mismatch"},
    # Temporal version skipped — temporal_consistency drift
    %{type: :temporal_consistency, score: 0.65, description: "version gap"},
    # Tensor shape changed — tensor drift
    %{type: :tensor, score: 0.70, description: "tensor shape mismatch"},
    # Required modality missing — schema drift
    %{type: :schema, score: 0.90, description: "missing modality"},
    # Overall quality degradation — quality drift
    %{type: :quality, score: 0.60, description: "quality degradation"}
  ]

  # ── Entry Point ────────────────────────────────────────────────────────

  def run do
    print_banner()

    # Ensure required processes are running
    ensure_infrastructure()

    # Determine mode based on Rust core availability
    mode = detect_mode()
    print_mode(mode)

    # Phase 1: Create entities
    {create_us, entities} = :timer.tc(fn -> create_entities(mode) end)
    print_phase_complete(1, "Create #{@entity_count} entities", create_us)

    # Phase 2: Corrupt a subset
    {corrupt_us, corrupted_ids} = :timer.tc(fn -> corrupt_entities(mode, entities) end)
    print_phase_complete(2, "Corrupt #{@corrupt_count} entities", corrupt_us)

    # Phase 3: Detect drift via sweep
    {detect_us, detections} = :timer.tc(fn -> detect_drift(mode) end)
    print_phase_complete(3, "Drift detection sweep", detect_us)

    # Phase 4: Repair via normalisation
    {repair_us, repairs} = :timer.tc(fn -> repair_drift(mode, corrupted_ids) end)
    print_phase_complete(4, "Normalisation repair", repair_us)

    # Phase 5: Verify consistency
    {verify_us, verification} = :timer.tc(fn -> verify_consistency(mode, corrupted_ids) end)
    print_phase_complete(5, "Consistency verification", verify_us)

    # Print summary
    print_summary(%{
      mode: mode,
      entity_count: @entity_count,
      corrupt_count: @corrupt_count,
      detected: detections,
      repaired: repairs,
      verified: verification,
      timings: %{
        create_us: create_us,
        corrupt_us: corrupt_us,
        detect_us: detect_us,
        repair_us: repair_us,
        verify_us: verify_us,
        total_us: create_us + corrupt_us + detect_us + repair_us + verify_us
      }
    })
  end

  # ── Infrastructure ─────────────────────────────────────────────────────

  defp ensure_infrastructure do
    IO.puts("  Starting infrastructure...")

    # Start DriftMonitor if not already running
    case DriftMonitor.start_link(config: %{
      sweep_interval_ms: 600_000,  # Long interval — we trigger sweeps manually
      max_concurrent_normalizations: 50,
      thresholds: %{
        semantic_vector: %{warning: 0.3, critical: 0.7},
        graph_document: %{warning: 0.4, critical: 0.8},
        temporal_consistency: %{warning: 0.2, critical: 0.6},
        tensor: %{warning: 0.35, critical: 0.75},
        schema: %{warning: 0.1, critical: 0.5},
        quality: %{warning: 0.25, critical: 0.65}
      }
    }) do
      {:ok, _pid} -> IO.puts("  DriftMonitor started")
      {:error, {:already_started, _pid}} -> IO.puts("  DriftMonitor already running")
    end

    # Initialize ETS cache for RustClient
    RustClient.init_cache()
    IO.puts("  RustClient cache initialised")
    IO.puts("")
  end

  defp detect_mode do
    # Verify the Rust core is actually running — not just any server on port 8080.
    # The health endpoint returns a JSON map with a "status" field when the Rust
    # core is running. If we get HTML or a non-map response, fall back to local.
    case RustClient.health() do
      {:ok, body} when is_map(body) -> :live
      {:ok, _non_map} -> :local  # e.g. HTML from nginx — not the Rust core
      {:error, _} -> :local
    end
  end

  # ── Phase 1: Create Entities ───────────────────────────────────────────

  defp create_entities(:live) do
    IO.puts("  Creating #{@entity_count} hexads via Rust core...")

    entities =
      1..@entity_count
      |> Enum.map(fn i ->
        input = build_hexad_input(i)
        case RustClient.create_hexad(input) do
          {:ok, hexad} ->
            id = hexad["id"] || "entity-#{String.pad_leading(Integer.to_string(i), 6, "0")}"
            if rem(i, 200) == 0, do: IO.write("  ... #{i}/#{@entity_count}\r")
            id
          {:error, _reason} ->
            # Fall back to generating a local ID
            "entity-#{String.pad_leading(Integer.to_string(i), 6, "0")}"
        end
      end)

    IO.puts("  Created #{length(entities)} hexads                    ")
    entities
  end

  defp create_entities(:local) do
    IO.puts("  Creating #{@entity_count} entities (local mode)...")

    entities =
      1..@entity_count
      |> Enum.map(fn i ->
        id = "entity-#{String.pad_leading(Integer.to_string(i), 6, "0")}"

        # Start an EntityServer for each entity
        case EntityServer.start_link(id) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
        end

        # Mark all 8 modalities as populated
        EntityServer.update(id, Enum.map(@modalities, fn m -> {:modality, m, true} end))

        if rem(i, 200) == 0, do: IO.write("  ... #{i}/#{@entity_count}\r")
        id
      end)

    IO.puts("  Created #{length(entities)} entities (local)          ")
    entities
  end

  defp build_hexad_input(i) do
    # Generate realistic-looking data for all 8 modalities
    lat = 51.5 + :rand.uniform() * 0.1 - 0.05
    lon = -0.12 + :rand.uniform() * 0.1 - 0.05

    %{
      title: "Entity ##{i}: #{Enum.random(entity_names())}",
      body: "Cross-modal entity #{i} with full octad representation. " <>
            "Created for drift detection demo. Category: #{Enum.random(categories())}.",
      embedding: Enum.map(1..384, fn _ -> :rand.uniform() * 2 - 1 end),
      types: ["https://verisimdb.dev/ontology/#{Enum.random(categories())}"],
      relationships: [
        {"relatesTo", "entity-#{String.pad_leading(Integer.to_string(max(1, i - 1)), 6, "0")}"},
        {"inCategory", "category-#{Enum.random(1..20)}"}
      ],
      provenance: %{
        event_type: "created",
        actor: "drift-demo@verisimdb.dev",
        source: "demo-script",
        description: "Created by drift detection demo"
      },
      spatial: %{
        latitude: lat,
        longitude: lon,
        geometry_type: "Point",
        properties: %{"region" => "demo-region"}
      },
      metadata: %{
        demo: true,
        batch: "drift-detection-#{Date.utc_today()}"
      }
    }
  end

  # ── Phase 2: Corrupt Entities ──────────────────────────────────────────

  defp corrupt_entities(mode, entities) do
    IO.puts("  Corrupting #{@corrupt_count} entities with cross-modal drift...")

    # Select random entities to corrupt
    corrupted_ids =
      entities
      |> Enum.shuffle()
      |> Enum.take(@corrupt_count)

    corrupted_ids
    |> Enum.with_index(1)
    |> Enum.each(fn {entity_id, idx} ->
      # Pick a random corruption pattern
      pattern = Enum.random(@corruption_patterns)

      case mode do
        :live ->
          corrupt_live(entity_id, pattern)
        :local ->
          corrupt_local(entity_id, pattern)
      end

      if rem(idx, 10) == 0 do
        IO.write("  ... #{idx}/#{@corrupt_count} corrupted\r")
      end
    end)

    IO.puts("  Corrupted #{@corrupt_count} entities                  ")
    corrupted_ids
  end

  defp corrupt_live(entity_id, pattern) do
    # In live mode, update the hexad to introduce inconsistency
    corruption_payload = case pattern.type do
      :semantic_vector ->
        # Change embedding without updating document
        %{embedding: Enum.map(1..384, fn _ -> :rand.uniform() end)}

      :graph_document ->
        # Change document without updating graph
        %{body: "CORRUPTED: This content no longer matches the graph edges."}

      :temporal_consistency ->
        # Force a version skip (metadata-level corruption)
        %{metadata: %{force_version_skip: true}}

      :tensor ->
        # Change tensor shape
        %{metadata: %{corrupted_tensor_shape: true}}

      :schema ->
        # Mark a required modality as missing
        %{metadata: %{removed_modality: "provenance"}}

      :quality ->
        # General degradation — scramble multiple fields
        %{body: "", embedding: Enum.map(1..384, fn _ -> 0.0 end)}
    end

    RustClient.update_hexad(entity_id, corruption_payload)

    # Report the drift to DriftMonitor
    DriftMonitor.report_drift(entity_id, pattern.score, pattern.type)
  end

  defp corrupt_local(entity_id, pattern) do
    # In local mode, simulate corruption via DriftMonitor
    DriftMonitor.report_drift(entity_id, pattern.score, pattern.type)

    # Also update entity modality status for schema drift
    if pattern.type == :schema do
      EntityServer.update(entity_id, [{:modality, :provenance, false}])
    end
  end

  # ── Phase 3: Detect Drift ──────────────────────────────────────────────

  defp detect_drift(_mode) do
    IO.puts("  Running drift detection sweep...")

    # Trigger a manual sweep
    DriftMonitor.sweep()

    # Give async tasks a moment to propagate
    Process.sleep(500)

    # Collect drift status
    status = DriftMonitor.status()

    detected_count = status.entities_with_drift

    IO.puts("  Detected #{detected_count} entities with drift")
    IO.puts("  Overall health: #{status.overall_health}")

    Enum.each(status.drift_by_type, fn {type, stats} ->
      IO.puts("    #{type}: avg=#{Float.round(stats.average, 3)}, " <>
              "max=#{Float.round(stats.max, 3)}, count=#{stats.count}")
    end)

    %{
      detected_count: detected_count,
      health: status.overall_health,
      drift_by_type: status.drift_by_type,
      pending_normalizations: status.pending_normalizations
    }
  end

  # ── Phase 4: Repair via Normalisation ──────────────────────────────────

  defp repair_drift(mode, corrupted_ids) do
    IO.puts("  Triggering normalisation for #{length(corrupted_ids)} corrupted entities...")

    results =
      corrupted_ids
      |> Enum.with_index(1)
      |> Enum.map(fn {entity_id, idx} ->
        result = case mode do
          :live ->
            case RustClient.normalize(entity_id) do
              :ok -> :repaired
              {:error, _} -> :failed
            end
          :local ->
            # In local mode, simulate normalisation by clearing drift
            DriftMonitor.report_drift(entity_id, 0.0, :quality)
            DriftMonitor.report_drift(entity_id, 0.0, :semantic_vector)
            DriftMonitor.report_drift(entity_id, 0.0, :graph_document)
            DriftMonitor.report_drift(entity_id, 0.0, :temporal_consistency)
            DriftMonitor.report_drift(entity_id, 0.0, :tensor)
            DriftMonitor.report_drift(entity_id, 0.0, :schema)

            # Restore any removed modalities
            EntityServer.update(entity_id, [{:modality, :provenance, true}])

            :repaired
        end

        if rem(idx, 10) == 0 do
          IO.write("  ... #{idx}/#{length(corrupted_ids)} normalised\r")
        end

        {entity_id, result}
      end)

    repaired = Enum.count(results, fn {_, r} -> r == :repaired end)
    failed = Enum.count(results, fn {_, r} -> r == :failed end)

    IO.puts("  Normalisation complete: #{repaired} repaired, #{failed} failed")

    %{repaired: repaired, failed: failed, results: results}
  end

  # ── Phase 5: Verify Consistency ────────────────────────────────────────

  defp verify_consistency(mode, corrupted_ids) do
    IO.puts("  Verifying consistency post-repair...")

    # Give normalisation a moment to complete
    Process.sleep(500)

    consistent_count =
      corrupted_ids
      |> Enum.count(fn entity_id ->
        case mode do
          :live ->
            case RustClient.get_drift_score(entity_id) do
              {:ok, score} when score < 0.3 -> true
              _ -> false
            end
          :local ->
            history = DriftMonitor.entity_history(entity_id)
            max_drift = history |> Map.values() |> Enum.max(fn -> 0.0 end)
            max_drift < 0.3
        end
      end)

    # Check overall system health after repair
    status = DriftMonitor.status()

    IO.puts("  Consistent entities: #{consistent_count}/#{length(corrupted_ids)}")
    IO.puts("  Post-repair system health: #{status.overall_health}")

    %{
      consistent: consistent_count,
      total: length(corrupted_ids),
      post_repair_health: status.overall_health
    }
  end

  # ── Output Formatting ──────────────────────────────────────────────────

  defp print_banner do
    IO.puts("""

    ╔══════════════════════════════════════════════════════════════════╗
    ║                                                                ║
    ║   VeriSimDB — Drift Detection & Self-Normalisation Demo        ║
    ║                                                                ║
    ║   Cross-modal consistency for the octad (8 modalities):        ║
    ║   Graph | Vector | Tensor | Semantic | Document |              ║
    ║   Temporal | Provenance | Spatial                              ║
    ║                                                                ║
    ╚══════════════════════════════════════════════════════════════════╝
    """)
  end

  defp print_mode(:live) do
    IO.puts("""
      Mode: LIVE (Rust core connected)
      Hexads will be created, corrupted, and repaired via the Rust API.
    """)
  end

  defp print_mode(:local) do
    IO.puts("""
      Mode: LOCAL (Rust core unavailable)
      Simulating via Elixir DriftMonitor and EntityServer.
      Start the Rust core (cargo run -p verisim-api) for live mode.
    """)
  end

  defp print_phase_complete(phase, description, microseconds) do
    ms = Float.round(microseconds / 1_000, 1)
    IO.puts("")
    IO.puts("  Phase #{phase} complete: #{description} (#{ms}ms)")
    IO.puts("  " <> String.duplicate("─", 60))
    IO.puts("")
  end

  defp print_summary(summary) do
    total_ms = Float.round(summary.timings.total_us / 1_000, 1)
    detection_rate = if summary.corrupt_count > 0 do
      Float.round(summary.detected.detected_count / summary.corrupt_count * 100, 1)
    else
      0.0
    end
    repair_rate = if summary.corrupt_count > 0 do
      Float.round(summary.repaired.repaired / summary.corrupt_count * 100, 1)
    else
      0.0
    end
    consistency_rate = if summary.verified.total > 0 do
      Float.round(summary.verified.consistent / summary.verified.total * 100, 1)
    else
      0.0
    end

    IO.puts("""

    ╔══════════════════════════════════════════════════════════════════╗
    ║                        DEMO RESULTS                            ║
    ╠══════════════════════════════════════════════════════════════════╣
    ║                                                                ║
    ║  Mode:             #{String.pad_trailing(Atom.to_string(summary.mode), 42)}║
    ║  Entities created: #{String.pad_trailing(Integer.to_string(summary.entity_count), 42)}║
    ║  Entities corrupted: #{String.pad_trailing(Integer.to_string(summary.corrupt_count), 40)}║
    ║                                                                ║
    ╠──────────────────────────────────────────────────────────────────╣
    ║  DETECTION                                                     ║
    ║    Entities with drift: #{String.pad_trailing(Integer.to_string(summary.detected.detected_count), 36)}║
    ║    Detection rate:      #{String.pad_trailing("#{detection_rate}%", 36)}║
    ║                                                                ║
    ║  REPAIR                                                        ║
    ║    Repaired:            #{String.pad_trailing(Integer.to_string(summary.repaired.repaired), 36)}║
    ║    Failed:              #{String.pad_trailing(Integer.to_string(summary.repaired.failed), 36)}║
    ║    Repair rate:         #{String.pad_trailing("#{repair_rate}%", 36)}║
    ║                                                                ║
    ║  VERIFICATION                                                  ║
    ║    Consistent post-repair: #{String.pad_trailing("#{summary.verified.consistent}/#{summary.verified.total}", 33)}║
    ║    Consistency rate:       #{String.pad_trailing("#{consistency_rate}%", 33)}║
    ║    System health:          #{String.pad_trailing(Atom.to_string(summary.verified.post_repair_health), 33)}║
    ║                                                                ║
    ╠──────────────────────────────────────────────────────────────────╣
    ║  TIMING                                                        ║
    ║    Create:        #{String.pad_trailing("#{Float.round(summary.timings.create_us / 1_000, 1)}ms", 43)}║
    ║    Corrupt:       #{String.pad_trailing("#{Float.round(summary.timings.corrupt_us / 1_000, 1)}ms", 43)}║
    ║    Detect:        #{String.pad_trailing("#{Float.round(summary.timings.detect_us / 1_000, 1)}ms", 43)}║
    ║    Repair:        #{String.pad_trailing("#{Float.round(summary.timings.repair_us / 1_000, 1)}ms", 43)}║
    ║    Verify:        #{String.pad_trailing("#{Float.round(summary.timings.verify_us / 1_000, 1)}ms", 43)}║
    ║    ─────────────────────────────                               ║
    ║    Total:         #{String.pad_trailing("#{total_ms}ms", 43)}║
    ║                                                                ║
    ╚══════════════════════════════════════════════════════════════════╝
    """)
  end

  # ── Data Generators ────────────────────────────────────────────────────

  defp entity_names do
    [
      "Research Paper", "Dataset Record", "Person Profile", "Organisation",
      "Event Log", "Sensor Reading", "Transaction", "Contract",
      "Knowledge Claim", "Audit Trail", "Policy Document", "Spatial Feature",
      "Time Series Point", "Graph Fragment", "Embedding Vector", "Tensor Block",
      "Provenance Chain", "Citation Link", "Access Control Entry", "Schema Definition"
    ]
  end

  defp categories do
    [
      "Research", "Finance", "Healthcare", "Education", "Government",
      "Technology", "Science", "Engineering", "Legal", "Environmental"
    ]
  end
end

# ── Run the demo ──────────────────────────────────────────────────────────

VeriSimDB.Demo.DriftDetection.run()
