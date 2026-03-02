# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim.QueryPlanner.Bidirectional do
  @moduledoc """
  Bidirectional query optimization using both forward and backward propagation.

  Forward Propagation (Top-Down):
    - Push predicates down from SELECT to WHERE
    - Example: If LIMIT 10, tell stores "only need 10 results"

  Backward Propagation (Bottom-Up):
    - Pull constraints up from stores to query plan
    - Example: If store has index on 'year', reorganize to use it

  Combined:
    - Forward pass: Optimize predicates
    - Backward pass: Rewrite based on store capabilities
    - Forward pass: Execute optimized plan
  """

  alias VeriSim.QueryPlannerConfig

  @doc """
  Optimize query using bidirectional propagation.

  Steps:
  1. Forward pass: Push down predicates (LIMIT, WHERE conditions)
  2. Backward pass: Pull up store capabilities (indexes, partitions)
  3. Generate final plan incorporating both
  """
  def optimize_bidirectional(query_ast) do
    # Phase 1: Forward propagation
    forward_plan = forward_propagate(query_ast)

    # Phase 2: Backward propagation (gather store capabilities)
    store_hints = backward_propagate(forward_plan)

    # Phase 3: Merge and finalize
    finalize_plan(forward_plan, store_hints)
  end

  # === Forward Propagation (Top-Down) ===

  defp forward_propagate(query_ast) do
    query_ast
    |> push_limit_down()
    |> push_predicates_down()
    |> push_projections_down()
    |> eliminate_redundant_operations()
  end

  defp push_limit_down(query_ast) do
    # If query has LIMIT, tell each store to limit results early
    case query_ast.limit do
      nil -> query_ast
      limit_value ->
        # Push LIMIT to each modality operation
        updated_operations = Enum.map(query_ast.operations, fn op ->
          %{op | early_limit: limit_value * 2}  # 2x buffer for joins
        end)
        %{query_ast | operations: updated_operations}
    end
  end

  defp push_predicates_down(query_ast) do
    # Push WHERE conditions to the stores that can evaluate them
    case query_ast.where do
      nil -> query_ast
      conditions ->
        # Decompose conditions by modality
        condition_map = decompose_conditions_by_modality(conditions)

        # Assign to operations
        updated_operations = Enum.map(query_ast.operations, fn op ->
          modality_conditions = Map.get(condition_map, op.modality, [])
          %{op | pushed_predicates: modality_conditions}
        end)

        %{query_ast | operations: updated_operations}
    end
  end

  defp push_projections_down(query_ast) do
    # If SELECT only requests specific fields, tell stores to return subset
    # Example: SELECT GRAPH(nodes, edges) → only fetch nodes and edges
    case query_ast.projections do
      nil -> query_ast
      projections ->
        updated_operations = Enum.map(query_ast.operations, fn op ->
          fields = Map.get(projections, op.modality, :all)
          %{op | projection: fields}
        end)
        %{query_ast | operations: updated_operations}
    end
  end

  defp eliminate_redundant_operations(query_ast) do
    # Remove operations that can't possibly return results
    # Example: If SEMANTIC condition fails, no need to query other modalities
    query_ast
  end

  # === Backward Propagation (Bottom-Up) ===

  defp backward_propagate(forward_plan) do
    # Query each store for capabilities and hints
    forward_plan.operations
    |> Enum.map(&gather_store_hints/1)
    |> aggregate_hints()
  end

  defp gather_store_hints(operation) do
    store_id = operation.store_id
    modality = operation.modality

    # Ask store: "What indexes/optimizations do you have?"
    hints = case modality do
      "GRAPH" -> gather_graph_hints(store_id, operation)
      "VECTOR" -> gather_vector_hints(store_id, operation)
      "DOCUMENT" -> gather_document_hints(store_id, operation)
      "SEMANTIC" -> gather_semantic_hints(store_id, operation)
      "TENSOR" -> gather_tensor_hints(store_id, operation)
      "TEMPORAL" -> gather_temporal_hints(store_id, operation)
    end

    %{operation: operation, hints: hints}
  end

  defp gather_graph_hints(store_id, operation) do
    # Ask Oxigraph: "What indexes exist for this query?"
    # Example response: [:edge_type_index, :node_label_index]
    case OxigraphClient.get_available_indexes(store_id, operation.condition) do
      {:ok, indexes} ->
        %{
          available_indexes: indexes,
          supports_parallel: true,
          estimated_cardinality: OxigraphClient.estimate_result_count(store_id, operation.condition),
          suggestion: suggest_graph_optimization(indexes, operation)
        }
      {:error, _} ->
        %{available_indexes: [], supports_parallel: false}
    end
  end

  defp gather_vector_hints(store_id, operation) do
    # Ask Milvus: "What's the best way to run this similarity search?"
    case MilvusClient.get_index_info(store_id) do
      {:ok, index_info} ->
        %{
          index_type: index_info.type,  # HNSW, IVF, etc.
          dimension: index_info.dimension,
          metric: index_info.metric,
          supports_filtering: index_info.supports_filtering,
          suggestion: suggest_vector_optimization(index_info, operation)
        }
      {:error, _} ->
        %{index_type: :unknown}
    end
  end

  defp gather_document_hints(store_id, operation) do
    # Ask Tantivy: "Do you have inverted index for this query?"
    case TantivyClient.get_schema_info(store_id) do
      {:ok, schema} ->
        %{
          indexed_fields: schema.indexed_fields,
          supports_phrase_query: schema.supports_phrase_query,
          has_stored_fields: schema.has_stored_fields,
          suggestion: suggest_document_optimization(schema, operation)
        }
      {:error, _} ->
        %{indexed_fields: []}
    end
  end

  defp gather_semantic_hints(_store_id, operation) do
    # Semantic operations are ZKP-based, limited optimization
    %{
      contract_name: operation.condition.contract_name,
      verification_cost: ProvenLibrary.estimate_verification_cost(operation.condition),
      suggestion: :execute_late  # ZKP verification is expensive, do last
    }
  end

  defp gather_tensor_hints(_store_id, _operation) do
    # Tensor operations depend on shape/dtype
    %{supports_gpu: BurnClient.has_gpu?()}
  end

  defp gather_temporal_hints(store_id, operation) do
    # Ask verisim-temporal: "Is this version cached?"
    case VeriSimTemporal.check_cache(store_id, operation.condition) do
      {:ok, :cached} -> %{suggestion: :execute_early, cached: true}
      {:ok, :not_cached} -> %{suggestion: :normal, cached: false}
      {:error, _} -> %{cached: false}
    end
  end

  # === Suggestion Heuristics ===

  defp suggest_graph_optimization(indexes, operation) do
    cond do
      :edge_type_index in indexes and operation.condition.edge_type != nil ->
        {:use_index, :edge_type_index}
      :node_label_index in indexes ->
        {:use_index, :node_label_index}
      true ->
        :full_scan
    end
  end

  defp suggest_vector_optimization(index_info, operation) do
    cond do
      index_info.type == :hnsw and operation.condition.threshold > 0.9 ->
        {:use_hnsw, :high_precision}
      index_info.supports_filtering and operation.condition.filter != nil ->
        {:use_filtering, :pre_filter}
      true ->
        :standard_ann
    end
  end

  defp suggest_document_optimization(schema, operation) do
    query_fields = extract_fulltext_fields(operation.condition)

    if Enum.all?(query_fields, &(&1 in schema.indexed_fields)) do
      {:use_inverted_index, query_fields}
    else
      :full_scan
    end
  end

  # === Finalization (Merge Forward + Backward) ===

  defp finalize_plan(forward_plan, store_hints) do
    # Reorder operations based on backward hints
    operations_with_hints = Enum.zip(forward_plan.operations, store_hints)

    # Sort by:
    # 1. Cached operations first
    # 2. Indexed operations second
    # 3. Full scans last
    sorted_operations = Enum.sort_by(operations_with_hints, fn {_op, hints} ->
      priority = case hints.hints.suggestion do
        :execute_early -> 1
        {:use_index, _} -> 2
        {:use_hnsw, _} -> 2
        :execute_late -> 99
        _ -> 50
      end
      priority
    end)

    final_operations = Enum.map(sorted_operations, fn {op, hints} ->
      %{op | optimization_hint: hints.hints.suggestion}
    end)

    %{forward_plan | operations: final_operations, optimization: :bidirectional}
  end

  # === Helper Functions ===

  defp decompose_conditions_by_modality(conditions) when is_list(conditions) do
    Enum.reduce(conditions, %{}, fn condition, acc ->
      modality = classify_condition_modality(condition)
      Map.update(acc, modality, [condition], &[condition | &1])
    end)
  end

  defp decompose_conditions_by_modality(conditions) when is_map(conditions) do
    # Single condition wrapped in a map
    modality = classify_condition_modality(conditions)
    %{modality => [conditions]}
  end

  defp decompose_conditions_by_modality(_), do: %{}

  defp classify_condition_modality(condition) when is_map(condition) do
    cond do
      Map.has_key?(condition, :embedding) or Map.has_key?(condition, :similar_to) ->
        "VECTOR"
      Map.has_key?(condition, :edge_type) or Map.has_key?(condition, :traversal) ->
        "GRAPH"
      Map.has_key?(condition, :fulltext) or Map.has_key?(condition, :contains) ->
        "DOCUMENT"
      Map.has_key?(condition, :proof) or Map.has_key?(condition, :contract) ->
        "SEMANTIC"
      Map.has_key?(condition, :shape) or Map.has_key?(condition, :tensor_op) ->
        "TENSOR"
      Map.has_key?(condition, :version) or Map.has_key?(condition, :as_of) ->
        "TEMPORAL"
      true ->
        "GRAPH"  # Default modality
    end
  end

  defp classify_condition_modality(condition) when is_binary(condition) do
    upper = String.upcase(condition)
    cond do
      String.contains?(upper, "SIMILAR") or String.contains?(upper, "EMBEDDING") -> "VECTOR"
      String.contains?(upper, "CITES") or String.contains?(upper, "EDGE") or String.contains?(upper, ")-[") -> "GRAPH"
      String.contains?(upper, "FULLTEXT") or String.contains?(upper, "CONTAINS") -> "DOCUMENT"
      String.contains?(upper, "PROOF") or String.contains?(upper, "VERIFY") -> "SEMANTIC"
      String.contains?(upper, "TENSOR") or String.contains?(upper, "SHAPE") -> "TENSOR"
      String.contains?(upper, "VERSION") or String.contains?(upper, "AS OF") -> "TEMPORAL"
      true -> "GRAPH"
    end
  end

  defp classify_condition_modality(_), do: "GRAPH"

  defp aggregate_hints(hints_list) do
    hints_list
  end

  defp extract_fulltext_fields(condition) when is_map(condition) do
    case Map.get(condition, :fulltext) do
      nil ->
        case Map.get(condition, :fields) do
          nil -> ["title", "body"]  # Default searchable fields
          fields when is_list(fields) -> fields
          field when is_binary(field) -> [field]
          _ -> ["title", "body"]
        end
      %{fields: fields} when is_list(fields) -> fields
      _ -> ["title", "body"]
    end
  end

  defp extract_fulltext_fields(_condition), do: ["title", "body"]
end
