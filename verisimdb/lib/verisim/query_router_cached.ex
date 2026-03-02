# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim.QueryRouter.Cached do
  @moduledoc """
  Query router with integrated caching.

  Wraps VeriSim.QueryRouter to add caching at multiple levels:
  1. Parsed AST cache (avoid re-parsing)
  2. Execution plan cache (avoid re-planning)
  3. Query result cache (avoid re-execution)
  4. ZKP proof cache (avoid re-generation)

  Drift-aware: Automatically invalidates cache when drift detected.
  """

  alias VeriSim.QueryCache
  alias VeriSim.QueryRouter
  alias VeriSim.DriftMonitor
  require Logger

  @doc """
  Execute query with caching.

  Cache strategy:
  - Dependent-type queries: Cache AST, plan, results, and proofs
  - Slipstream queries: Cache AST and plan only (results too volatile)
  - Invalidate on drift detection
  """
  def execute_with_cache(raw_query, opts \\ []) do
    use_dependent_types = Keyword.get(opts, :use_dependent_types, false)
    force_fresh = Keyword.get(opts, :force_fresh, false)

    # Step 1: Try to get parsed AST from cache
    {ast, ast_cache_hit?} = if force_fresh do
      {parse_query(raw_query), false}
    else
      case get_cached_ast(raw_query) do
        {:ok, cached_ast} -> {cached_ast, true}
        {:error, :not_found} ->
          ast = parse_query(raw_query)
          cache_ast(raw_query, ast)
          {ast, false}
      end
    end

    Logger.debug("AST cache #{if ast_cache_hit?, do: "HIT", else: "MISS"}")

    # Step 2: Try to get execution plan from cache
    {plan, plan_cache_hit?} = if force_fresh do
      {generate_plan(ast), false}
    else
      case get_cached_plan(ast) do
        {:ok, cached_plan} -> {cached_plan, true}
        {:error, :not_found} ->
          plan = generate_plan(ast)
          cache_plan(ast, plan)
          {plan, false}
      end
    end

    Logger.debug("Plan cache #{if plan_cache_hit?, do: "HIT", else: "MISS"}")

    # Step 3: Check if we should cache query results
    should_cache_result? = should_cache_query_result?(ast, use_dependent_types)

    # Step 4: Try to get query results from cache
    if should_cache_result? and not force_fresh do
      case get_cached_result(ast) do
        {:ok, cached_result} ->
          Logger.info("Query result cache HIT")
          {:ok, %{cached_result | cache_hit: true}}

        {:error, :not_found} ->
          # Execute and cache
          execute_and_cache(ast, plan, use_dependent_types)
      end
    else
      # Don't use result cache
      execute_query(ast, plan, use_dependent_types)
    end
  end

  # === Cache Retrieval ===

  defp get_cached_ast(raw_query) do
    key = QueryCache.parsed_ast_key(raw_query)
    QueryCache.get(key)
  end

  defp get_cached_plan(ast) do
    optimization_mode = VeriSim.QueryPlannerConfig.get_mode_for_modality(
      List.first(ast.modalities)
    )
    key = QueryCache.execution_plan_key(ast, optimization_mode)
    QueryCache.get(key)
  end

  defp get_cached_result(ast) do
    key = QueryCache.query_result_key(ast)
    QueryCache.get(key)
  end

  # === Cache Storage ===

  defp cache_ast(raw_query, ast) do
    key = QueryCache.parsed_ast_key(raw_query)
    tags = ["ast"]

    QueryCache.put(key, ast,
      ttl: 3600,  # ASTs don't change, cache for 1 hour
      tags: tags,
      layer: :l1
    )
  end

  defp cache_plan(ast, plan) do
    optimization_mode = VeriSim.QueryPlannerConfig.get_mode_for_modality(
      List.first(ast.modalities)
    )
    key = QueryCache.execution_plan_key(ast, optimization_mode)
    tags = ["plan"] ++ extract_tags_from_ast(ast)

    QueryCache.put(key, plan,
      ttl: 600,  # Plans can change with statistics, cache for 10 minutes
      tags: tags,
      layer: :l1
    )
  end

  defp cache_result(ast, result) do
    key = QueryCache.query_result_key(ast)
    tags = extract_tags_from_ast(ast)

    # TTL based on modality policy
    ttl = get_result_ttl(ast)

    QueryCache.put(key, result,
      ttl: ttl,
      tags: tags,
      layer: :all  # Store in all layers (L1, L2, L3)
    )
  end

  defp cache_zkp_proof(contract_name, data_hash, proof) do
    key = QueryCache.zkp_proof_key(contract_name, data_hash)
    tags = ["zkp", "contract:#{contract_name}"]

    QueryCache.put(key, proof,
      ttl: 1800,  # ZKP proofs valid for 30 minutes
      tags: tags,
      layer: :all
    )
  end

  # === Query Execution ===

  defp execute_and_cache(ast, plan, use_dependent_types) do
    case execute_query(ast, plan, use_dependent_types) do
      {:ok, result} ->
        # Cache the result
        cache_result(ast, result)

        # If ZKP proof included, cache it separately
        if result.proof do
          data_hash = compute_data_hash(result.data)
          cache_zkp_proof(result.proof.contract_name, data_hash, result.proof)
        end

        {:ok, %{result | cache_hit: false}}

      error ->
        error
    end
  end

  defp execute_query(ast, plan, use_dependent_types) do
    # Delegate to actual QueryRouter
    QueryRouter.handle_query(%{
      ast: ast,
      plan: plan,
      typed: use_dependent_types
    })
  end

  # === Cache Policy Decisions ===

  defp should_cache_query_result?(ast, use_dependent_types) do
    # Check each modality's cache policy
    ast.modalities
    |> Enum.all?(fn modality ->
      modality_str = modality_to_string(modality)
      query_type = if use_dependent_types, do: :dependent_type, else: :slipstream

      QueryCache.should_cache?(modality_str, query_type)
    end)
  end

  defp get_result_ttl(ast) do
    # Use the most conservative TTL among all modalities
    ast.modalities
    |> Enum.map(fn modality ->
      modality_str = modality_to_string(modality)
      QueryCache.get_ttl_for_modality(modality_str)
    end)
    |> Enum.min()
  end

  # === Drift-Aware Invalidation ===

  @doc """
  Invalidate cache when drift is detected for a hexad.
  Should be called by DriftMonitor when drift detected.
  """
  def invalidate_on_drift(hexad_id) do
    Logger.info("Invalidating cache due to drift for hexad: #{hexad_id}")

    # Invalidate all queries involving this hexad
    QueryCache.invalidate_by_tag("hexad:#{hexad_id}")

    :ok
  end

  @doc """
  Invalidate cache when drift is detected across a federation.
  """
  def invalidate_federation_cache(federation_pattern) do
    Logger.info("Invalidating cache for federation: #{federation_pattern}")

    QueryCache.invalidate_by_tag("federation:#{federation_pattern}")

    :ok
  end

  @doc """
  Invalidate cache for specific modality.
  Used when modality store is updated.
  """
  def invalidate_modality_cache(modality) do
    Logger.info("Invalidating cache for modality: #{modality}")

    QueryCache.invalidate_by_tag("modality:#{modality}")

    :ok
  end

  # === Cache Warming ===

  @doc """
  Pre-warm cache with common queries.
  Should be called at startup or after major data changes.
  """
  def warm_cache(common_queries) do
    Logger.info("Warming cache with #{length(common_queries)} queries")

    common_queries
    |> Task.async_stream(
      fn query ->
        execute_with_cache(query, use_dependent_types: false)
      end,
      max_concurrency: 10,
      timeout: 30_000
    )
    |> Stream.run()

    Logger.info("Cache warming complete")
  end

  # === Helper Functions ===

  defp parse_query(raw_query) do
    modalities = extract_modalities(raw_query)
    source = extract_source(raw_query)
    %{raw: raw_query, modalities: modalities, source: source}
  end

  defp extract_modalities(query) do
    upper = String.upcase(query)
    modalities = []
    modalities = if String.contains?(upper, "GRAPH"), do: ["GRAPH" | modalities], else: modalities
    modalities = if String.contains?(upper, "VECTOR"), do: ["VECTOR" | modalities], else: modalities
    modalities = if String.contains?(upper, "TENSOR"), do: ["TENSOR" | modalities], else: modalities
    modalities = if String.contains?(upper, "SEMANTIC"), do: ["SEMANTIC" | modalities], else: modalities
    modalities = if String.contains?(upper, "DOCUMENT"), do: ["DOCUMENT" | modalities], else: modalities
    modalities = if String.contains?(upper, "TEMPORAL"), do: ["TEMPORAL" | modalities], else: modalities
    if modalities == [], do: ["GRAPH"], else: Enum.reverse(modalities)
  end

  defp extract_source(query) do
    cond do
      String.contains?(query, "FEDERATION") ->
        case Regex.run(~r/FEDERATION\s+(\S+)/, query) do
          [_, pattern] -> {:federation, pattern, %{}}
          _ -> {:hexad, "unknown"}
        end
      true ->
        {:hexad, "unknown"}
    end
  end

  defp generate_plan(ast) do
    # Call query planner
    VeriSim.QueryPlanner.plan_query(ast)
  end

  defp extract_tags_from_ast(ast) do
    tags = []

    # Add hexad tags
    hexad_tags = case ast.source do
      {:hexad, id} -> ["hexad:#{id}"]
      {:federation, pattern, _} -> ["federation:#{pattern}"]
      {:store, store_id} -> ["store:#{store_id}"]
      _ -> []
    end

    # Add modality tags
    modality_tags = Enum.map(ast.modalities, fn mod ->
      "modality:#{modality_to_string(mod)}"
    end)

    tags ++ hexad_tags ++ modality_tags
  end

  defp modality_to_string(modality) when is_binary(modality), do: modality
  defp modality_to_string(modality) when is_atom(modality) do
    modality |> Atom.to_string() |> String.upcase()
  end
  defp modality_to_string(modality), do: "#{modality}"

  defp compute_data_hash(data) do
    :crypto.hash(:blake3, :erlang.term_to_binary(data))
    |> Base.encode16(case: :lower)
  end
end
