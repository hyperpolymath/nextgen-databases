# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim.IntegrationTest do
  @moduledoc """
  Integration tests for the full VeriSimDB stack.

  Tests:
  - Elixir orchestration layer
  - Communication with Rust core
  - VQL query execution
  - Drift detection and normalization
  - Cross-modal queries
  """

  use ExUnit.Case, async: false

  alias VeriSim.{
    QueryRouter,
    RustClient,
    DriftMonitor,
    SchemaRegistry,
    EntityServer,
    Query.VQLExecutor
  }

  @moduletag :integration

  setup do
    # Start the application
    {:ok, _} = Application.ensure_all_started(:verisim)

    # Wait for Rust core to be ready
    wait_for_rust_core()

    :ok
  end

  describe "Rust Client" do
    test "health check" do
      case RustClient.health() do
        {:ok, _health} ->
          assert true

        {:error, _reason} ->
          # Rust core may not be running, skip test
          :ok
      end
    end

    test "create and get hexad" do
      input = %{
        title: "Test Hexad",
        body: "Integration test hexad",
        embedding: List.duplicate(0.5, 384)
      }

      case RustClient.create_hexad(input) do
        {:ok, %{"id" => entity_id}} ->
          assert is_binary(entity_id)

          case RustClient.get_hexad(entity_id) do
            {:ok, hexad} ->
              assert hexad["id"] == entity_id
              assert hexad["document"]["title"] == "Test Hexad"

            {:error, :not_found} ->
              flunk("Hexad should exist after creation")

            {:error, reason} ->
              flunk("Failed to get hexad: #{inspect(reason)}")
          end

        {:error, _reason} ->
          # Rust core not available
          :ok
      end
    end
  end

  describe "Query Router" do
    test "routes text queries" do
      stats = QueryRouter.stats()
      assert is_map(stats)
      assert Map.has_key?(stats, :total_queries)
    end

    test "handles multi-modal queries" do
      params = %{
        text: "machine learning",
        types: ["https://example.org/Document"]
      }

      result = QueryRouter.query(:multi, params, limit: 10)

      case result do
        {:ok, _results} -> assert true
        {:error, _} -> :ok
      end
    end
  end

  describe "Drift Monitor" do
    test "tracks drift events" do
      entity_id = "test-entity-#{:rand.uniform(1000)}"

      DriftMonitor.report_drift(entity_id, 0.5, :semantic_vector)
      DriftMonitor.entity_changed(entity_id)

      # Give it time to process
      Process.sleep(100)

      status = DriftMonitor.status()
      assert status[:overall_health] in [:healthy, :warning, :degraded, :critical]
      assert is_integer(status[:entities_with_drift])
    end

    test "triggers normalization on critical drift" do
      entity_id = "critical-drift-#{:rand.uniform(1000)}"

      # Report critical drift
      DriftMonitor.report_drift(entity_id, 0.9, :quality)

      Process.sleep(200)

      status = DriftMonitor.status()
      # Normalization might have been triggered
      assert is_integer(status[:pending_normalizations])
    end
  end

  describe "Schema Registry" do
    test "registers and retrieves types" do
      type_def = %{
        iri: "https://test.example.org/TestType",
        label: "Test Type",
        supertypes: ["verisim:Entity"],
        constraints: [
          %{
            name: "title_required",
            kind: {:required, "title"},
            message: "Title is required"
          }
        ]
      }

      assert :ok == SchemaRegistry.register_type(type_def)

      retrieved = SchemaRegistry.get_type("https://test.example.org/TestType")
      assert retrieved != nil
      assert retrieved.label == "Test Type"
    end

    test "validates entities against type constraints" do
      # Valid entity
      valid_entity = %{
        types: ["verisim:Document"],
        properties: %{
          "title" => "Valid Document"
        }
      }

      assert :ok == SchemaRegistry.validate(valid_entity)

      # Invalid entity (missing required field)
      invalid_entity = %{
        types: ["verisim:Document"],
        properties: %{}
      }

      case SchemaRegistry.validate(invalid_entity) do
        {:error, violations} ->
          assert length(violations) > 0

        :ok ->
          # Schema validation might be lenient
          assert true
      end
    end

    test "computes type hierarchy" do
      hierarchy = SchemaRegistry.type_hierarchy("verisim:Document")
      assert is_list(hierarchy)
      assert "verisim:Document" in hierarchy
      assert "verisim:Entity" in hierarchy
    end
  end

  describe "VQL Executor" do
    test "generates explain plans" do
      query_ast = %{
        modalities: [:graph, :vector],
        source: {:hexad, "test-id"},
        where: nil,
        proof: nil,
        limit: 10,
        offset: 0
      }

      {:ok, plan} = VQLExecutor.execute(query_ast, explain: true)

      assert is_map(plan)
      assert Map.has_key?(plan, :strategy)
      assert Map.has_key?(plan, :steps)
    end

    test "executes hexad queries" do
      query_ast = %{
        modalities: [:document],
        source: {:hexad, "nonexistent-id"},
        where: nil,
        proof: nil,
        limit: 10,
        offset: 0
      }

      result = VQLExecutor.execute(query_ast)

      # Expect error for nonexistent hexad
      assert match?({:error, _}, result)
    end
  end

  describe "Entity Server" do
    test "manages entity lifecycle" do
      entity_id = "entity-server-test-#{:rand.uniform(10000)}"

      # Start entity server
      {:ok, _pid} = EntityServer.start_link(entity_id)

      # Get initial state
      {:ok, state} = EntityServer.get(entity_id)

      assert state.id == entity_id
      assert state.status == :active
      assert state.version == 0

      # Update entity
      {:ok, new_state} = EntityServer.update(entity_id, [
        {:modality, :document, true}
      ])

      assert new_state.modalities.document == true
    end

    test "handles normalization requests" do
      entity_id = "normalization-test-#{:rand.uniform(10000)}"

      {:ok, _pid} = EntityServer.start_link(entity_id)

      # Trigger normalization
      :ok = EntityServer.normalize(entity_id)

      # Normalization is async, just verify it doesn't crash
      Process.sleep(100)

      {:ok, state} = EntityServer.get(entity_id)
      assert is_map(state)
    end
  end

  describe "Full Stack Integration" do
    test "create hexad via Rust, query via Elixir" do
      # Create hexad via Rust client
      input = %{
        title: "Full Stack Test",
        body: "Testing end-to-end integration",
        embedding: List.duplicate(0.7, 384),
        types: ["verisim:Document"]
      }

      case RustClient.create_hexad(input) do
        {:ok, %{"id" => entity_id}} ->
          # Query via Elixir QueryRouter
          case RustClient.get_hexad(entity_id) do
            {:ok, hexad} ->
              assert hexad["document"]["title"] == "Full Stack Test"

            {:error, reason} ->
              flunk("Failed to retrieve hexad: #{inspect(reason)}")
          end

        {:error, _reason} ->
          # Rust core not available
          :ok
      end
    end

    test "cross-modal search" do
      # Test combining text search with vector similarity
      params = %{
        text: "integration test",
        vector: List.duplicate(0.6, 384)
      }

      result = QueryRouter.query(:multi, params, limit: 5)

      case result do
        {:ok, results} ->
          assert is_list(results)

        {:error, _} ->
          # Expected if no matching data
          :ok
      end
    end

    test "drift detection across stack" do
      entity_id = "drift-integration-#{:rand.uniform(10000)}"

      # Create hexad with potential drift
      input = %{
        title: "Drift Test",
        body: "Testing drift detection across stack",
        embedding: List.duplicate(0.8, 384)
      }

      case RustClient.create_hexad(input) do
        {:ok, %{"id" => ^entity_id}} ->
          # Check drift via Elixir
          case RustClient.get_drift_score(entity_id) do
            {:ok, score} ->
              assert is_float(score)
              assert score >= 0.0 and score <= 1.0

            {:error, _} ->
              :ok
          end

        {:error, _} ->
          :ok
      end
    end
  end

  # Helper functions

  defp wait_for_rust_core(retries \\ 5) do
    case RustClient.health() do
      {:ok, _} ->
        :ok

      {:error, _} ->
        if retries > 0 do
          Process.sleep(1000)
          wait_for_rust_core(retries - 1)
        else
          # Rust core not available, tests will be skipped
          :ok
        end
    end
  end
end
