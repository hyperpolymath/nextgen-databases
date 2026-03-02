# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim.Query.VQLExecutor do
  @moduledoc """
  VQL Executor - Executes VQL queries and mutations parsed by the ReScript VQL parser.

  Supports three phases:
  1. Dependent-type queries with multi-proof composition
  2. Cross-modal correlation conditions
  3. Write path (INSERT / UPDATE / DELETE)

  ## Execution Pipeline

  1. Parse VQL query (done by ReScript VQLParser)
  2. Type-check if PROOF clause present (VQLTypeChecker → VQLBidir)
  3. Generate execution plan (VQLExplain)
  4. Classify conditions (pushdown vs cross-modal)
  5. Route to appropriate modality stores
  6. Evaluate cross-modal conditions post-fetch
  7. Aggregate and return results
  """

  require Logger

  alias VeriSim.{QueryRouter, RustClient, Telemetry}
  alias VeriSim.Query.VQLProofCertificate

  @doc """
  Execute a parsed VQL query.

  ## Parameters

  - `query_ast` - Parsed VQL query from ReScript VQLParser
  - `opts` - Execution options

  ## Options

  - `:explain` - Return execution plan instead of results
  - `:timeout` - Query timeout in milliseconds (default: 30000)
  - `:verify_proof` - Verify ZKP proofs for dependent-type queries (default: true)

  ## Returns

  - `{:ok, results}` - Query results
  - `{:error, reason}` - Query execution failed
  """
  def execute(query_ast, opts \\ []) do
    explain = Keyword.get(opts, :explain, false)
    timeout = Keyword.get(opts, :timeout, 30_000)

    if explain do
      {:ok, generate_explain_plan(query_ast)}
    else
      execute_query(query_ast, timeout)
    end
  end

  @doc """
  Execute a VQL mutation (INSERT / UPDATE / DELETE).
  """
  def execute_mutation(mutation_ast, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 30_000)

    case mutation_ast do
      %{TAG: "Insert", modalities: modality_data, proof: proof} ->
        execute_insert(modality_data, proof, timeout)

      %{TAG: "Update", hexadId: hexad_id, sets: sets, proof: proof} ->
        execute_update(hexad_id, sets, proof, timeout)

      %{TAG: "Delete", hexadId: hexad_id, proof: proof} ->
        execute_delete(hexad_id, proof, timeout)

      _ ->
        {:error, {:invalid_mutation, "Unknown mutation type"}}
    end
  end

  @doc """
  Execute a VQL statement (query or mutation).
  """
  def execute_statement(statement_ast, opts \\ []) do
    case statement_ast do
      %{TAG: "Query", _0: query} -> execute(query, opts)
      %{TAG: "Mutation", _0: mutation} -> execute_mutation(mutation, opts)
      # Map with :type key from built-in parser
      %{type: :query} -> execute(statement_ast, opts)
      %{type: :mutation, mutation: mutation} -> execute_mutation(mutation, opts)
      _ -> execute(statement_ast, opts)
    end
  end

  @doc """
  Execute a VQL query string (includes parsing).
  """
  def execute_string(query_string, opts \\ []) do
    start_time = System.monotonic_time()

    result =
      case VeriSim.Query.VQLBridge.parse(query_string) do
        {:ok, ast} -> execute(ast, opts)
        {:error, reason} -> {:error, {:parse_error, reason}}
      end

    # Emit telemetry for product insights (aggregate-only, no query content).
    duration = System.monotonic_time() - start_time
    statement_type = classify_statement_type(query_string)
    modalities = extract_modalities_from_string(query_string)

    case result do
      {:ok, _} ->
        Telemetry.emit_query_stop(duration, %{
          statement_type: statement_type,
          modalities: modalities
        })
      {:error, _} ->
        Telemetry.emit_query_exception(%{statement_type: statement_type})
    end

    result
  end

  # Classify a query string into a statement type for telemetry (no content captured).
  defp classify_statement_type(query_string) do
    upper = String.upcase(String.trim(query_string))
    cond do
      String.starts_with?(upper, "SELECT") -> "SELECT"
      String.starts_with?(upper, "INSERT") -> "INSERT"
      String.starts_with?(upper, "UPDATE") -> "UPDATE"
      String.starts_with?(upper, "DELETE") -> "DELETE"
      String.starts_with?(upper, "EXPLAIN") -> "EXPLAIN"
      String.starts_with?(upper, "SHOW") -> "SHOW"
      String.starts_with?(upper, "SEARCH") -> "SEARCH"
      String.starts_with?(upper, "COUNT") -> "COUNT"
      true -> "OTHER"
    end
  end

  # Extract modality names from a query string for telemetry (names only, no content).
  defp extract_modalities_from_string(query_string) do
    upper = String.upcase(query_string)
    ~w(GRAPH VECTOR TENSOR SEMANTIC DOCUMENT TEMPORAL PROVENANCE SPATIAL)
    |> Enum.filter(&String.contains?(upper, &1))
    |> Enum.map(&String.downcase/1)
    |> Enum.map(&String.to_atom/1)
  end

  # ===========================================================================
  # Query Execution
  # ===========================================================================

  defp execute_query(query_ast, timeout) do
    modalities = extract_modalities(query_ast)
    source = extract_source(query_ast)
    where_clause = extract_where(query_ast)
    proof_specs = extract_proof(query_ast)
    limit = extract_limit(query_ast)
    offset = extract_offset(query_ast)
    order_by = extract_order_by(query_ast)
    group_by = extract_group_by(query_ast)
    aggregates = extract_aggregates(query_ast)
    projections = extract_projections(query_ast)

    if proof_specs do
      # VQL-DT path: type-check → execute → verify proofs → bundle certificate
      execute_dt_query(query_ast, proof_specs, modalities, source, where_clause,
                       limit, offset, order_by, group_by, aggregates, projections, timeout)
    else
      # Slipstream path: no proofs, no type checking
      execute_slipstream_query(modalities, source, where_clause,
                               limit, offset, order_by, group_by, aggregates, projections, timeout)
    end
  end

  # Slipstream execution — fast path, no proofs
  defp execute_slipstream_query(modalities, source, where_clause,
                                 limit, offset, order_by, group_by, aggregates, projections, timeout) do
    {pushdown_conditions, cross_modal_conditions} = classify_conditions(where_clause)

    result = execute_by_source(source, modalities, pushdown_conditions, limit, offset, timeout)

    case result do
      {:ok, rows} ->
        rows
        |> maybe_evaluate_cross_modal(cross_modal_conditions)
        |> maybe_group_and_aggregate(group_by, aggregates)
        |> maybe_order_by(order_by)
        |> maybe_project_columns(projections)
        |> then(&{:ok, &1})

      error -> error
    end
  end

  # VQL-DT execution — type check, execute, verify proofs, bundle certificate
  defp execute_dt_query(query_ast, proof_specs, modalities, source, where_clause,
                         limit, offset, order_by, group_by, aggregates, projections, timeout) do
    alias VeriSim.Query.{VQLBridge, VQLTypeChecker}

    # Step 1: Type-check the query to get proof obligations and composition strategy.
    # Tries three strategies in order:
    #   1. ReScript bidirectional type checker (VQLBridge.typecheck — full formal system)
    #   2. Elixir-native type checker (VQLTypeChecker — validates types, generates obligations)
    #   3. Bare AST extraction (last resort — no validation, just structuring)
    type_info = case VQLBridge.typecheck(query_ast) do
      {:ok, info} ->
        info

      {:error, :type_checker_unavailable} ->
        # ReScript subprocess not running. Use the Elixir-native type checker
        # which validates proof types, modality compatibility, and composition.
        Logger.info("VQL-DT: Using Elixir-native type checker (ReScript subprocess unavailable)")

        case VQLTypeChecker.typecheck(query_ast) do
          {:ok, info} ->
            info

          {:error, reason} ->
            # Native type checker rejected the query — this is a real type error.
            Logger.error("VQL-DT: Type checking failed: #{inspect(reason)}")
            nil
        end

      {:error, reason} ->
        Logger.error("VQL-DT: Type checking failed: #{inspect(reason)}")
        nil
    end

    if is_nil(type_info) do
      {:error, {:type_check_failed, "VQL-DT query type checking failed"}}
    else
      # Step 2: Execute the query (get data)
      {pushdown_conditions, cross_modal_conditions} = classify_conditions(where_clause)
      data_result = execute_by_source(source, modalities, pushdown_conditions, limit, offset, timeout)

      case data_result do
        {:ok, rows} ->
          processed_rows =
            rows
            |> maybe_evaluate_cross_modal(cross_modal_conditions)
            |> maybe_group_and_aggregate(group_by, aggregates)
            |> maybe_order_by(order_by)
            |> maybe_project_columns(projections)

          # Step 3: Verify all proof obligations
          obligations = type_info[:proof_obligations] || type_info["proof_obligations"] || proof_specs
          proof_result = verify_multi_proof(query_ast, obligations)

          case proof_result do
            {:ok, artifacts} ->
              # Step 4: Bundle data + proof certificate as ProvedResult.
              # The certificate includes the proof artifacts returned by each
              # verifier (e.g., hash commitments, Merkle proofs, entity existence
              # confirmations) so downstream consumers can independently verify.
              query_text = Map.get(query_ast, :raw, "") || ""
              composition = type_info[:composition_strategy] || type_info["composition_strategy"] || :conjunction

              # Step 4b: Generate independently verifiable certificates for
              # each proof obligation using VQLProofCertificate. Each artifact
              # from the verifier becomes the witness for its corresponding
              # obligation, yielding a hash-sealed certificate.
              verifiable_certificates =
                obligations
                |> Enum.zip(List.wrap(artifacts))
                |> Enum.map(fn {obligation, artifact} ->
                  witness = if is_map(artifact), do: artifact, else: %{raw: artifact}
                  case VQLProofCertificate.generate_certificate(obligation, witness) do
                    {:ok, cert} -> cert
                    {:error, _} -> nil
                  end
                end)
                |> Enum.reject(&is_nil/1)

              proved_result = %{
                data: processed_rows,
                proof_certificate: %{
                  proofs: artifacts,
                  obligations: obligations,
                  composition: composition,
                  verified_at: DateTime.utc_now(),
                  query_hash: :crypto.hash(:sha256, to_string(query_text)) |> Base.encode16(case: :lower),
                  verifiable_certificates: verifiable_certificates
                }
              }
              {:ok, proved_result}

            {:error, reason} ->
              {:error, {:proof_verification_failed, reason}}
          end

        error -> error
      end
    end
  end

  # Shared: route query to the appropriate source
  defp execute_by_source(source, modalities, pushdown_conditions, limit, offset, timeout) do
    case source do
      {:hexad, entity_id} ->
        execute_hexad_query(entity_id, modalities, pushdown_conditions, limit, offset, timeout)

      {:federation, pattern, drift_policy} ->
        execute_federation_query(pattern, drift_policy, modalities, pushdown_conditions, limit, offset, timeout)

      {:store, store_id} ->
        execute_store_query(store_id, modalities, pushdown_conditions, limit, offset, timeout)

      :reflect ->
        execute_reflect_query(modalities, pushdown_conditions, limit, offset, timeout)
    end
  end

  # ===========================================================================
  # Phase 2: Condition Classification
  # ===========================================================================

  defp classify_conditions(nil), do: {nil, []}
  defp classify_conditions(%{raw: _} = condition), do: {condition, []}
  defp classify_conditions(condition) when is_map(condition) do
    case condition do
      %{TAG: "CrossModalFieldCompare"} -> {nil, [condition]}
      %{TAG: "ModalityDrift"} -> {nil, [condition]}
      %{TAG: "ModalityExists"} -> {nil, [condition]}
      %{TAG: "ModalityNotExists"} -> {nil, [condition]}
      %{TAG: "ModalityConsistency"} -> {nil, [condition]}
      %{TAG: "And", _0: left, _1: right} ->
        {push_l, cross_l} = classify_conditions(left)
        {push_r, cross_r} = classify_conditions(right)
        pushdown = combine_pushdown(push_l, push_r, :and)
        {pushdown, cross_l ++ cross_r}
      %{TAG: "Or", _0: left, _1: right} ->
        {push_l, cross_l} = classify_conditions(left)
        {push_r, cross_r} = classify_conditions(right)
        pushdown = combine_pushdown(push_l, push_r, :or)
        {pushdown, cross_l ++ cross_r}
      %{TAG: "Not", _0: inner} ->
        {push, cross} = classify_conditions(inner)
        {push, cross}
      _ ->
        # Simple condition: pushdown
        {condition, []}
    end
  end
  defp classify_conditions(condition), do: {condition, []}

  defp combine_pushdown(nil, nil, _op), do: nil
  defp combine_pushdown(a, nil, _op), do: a
  defp combine_pushdown(nil, b, _op), do: b
  defp combine_pushdown(a, b, :and), do: %{TAG: "And", _0: a, _1: b}
  defp combine_pushdown(a, b, :or), do: %{TAG: "Or", _0: a, _1: b}

  # ===========================================================================
  # Phase 2: Cross-Modal Evaluation
  # ===========================================================================

  defp maybe_evaluate_cross_modal(rows, []), do: rows
  defp maybe_evaluate_cross_modal(rows, cross_modal_conditions) do
    Enum.filter(rows, fn hexad ->
      Enum.all?(cross_modal_conditions, fn condition ->
        evaluate_cross_modal(hexad, condition)
      end)
    end)
  end

  defp evaluate_cross_modal(hexad, condition) do
    case condition do
      %{TAG: "CrossModalFieldCompare",
        _0: mod1, _1: field1, _2: op, _3: mod2, _4: field2} ->
        val1 = get_modality_field(hexad, mod1, field1)
        val2 = get_modality_field(hexad, mod2, field2)
        compare_values_with_op(val1, op, val2)

      %{TAG: "ModalityDrift", _0: mod1, _1: mod2, _2: threshold} ->
        drift = compute_modality_drift(hexad, mod1, mod2)
        drift > threshold

      %{TAG: "ModalityExists", _0: modality} ->
        has_modality_data?(hexad, modality)

      %{TAG: "ModalityNotExists", _0: modality} ->
        not has_modality_data?(hexad, modality)

      %{TAG: "ModalityConsistency", _0: mod1, _1: mod2, _2: metric} ->
        compute_consistency(hexad, mod1, mod2, metric) > 0.0

      _ -> true
    end
  end

  defp get_modality_field(hexad, modality, field) do
    mod_str = modality_to_string(modality)
    mod_data = Map.get(hexad, mod_str, %{})
    Map.get(mod_data, field) || Map.get(hexad, "#{mod_str}.#{field}")
  end

  defp has_modality_data?(hexad, modality) do
    mod_str = modality_to_string(modality)
    case Map.get(hexad, mod_str) do
      nil -> false
      data when data == %{} -> false
      _ -> true
    end
  end

  defp compute_modality_drift(hexad, mod1, mod2) do
    # Compute drift between two modality representations.
    # Uses the Rust drift API when both modalities have data,
    # falling back to embedding-based comparison.
    mod1_str = modality_to_string(mod1)
    mod2_str = modality_to_string(mod2)

    case {Map.get(hexad, mod1_str), Map.get(hexad, mod2_str)} do
      {nil, _} -> 1.0  # Missing modality = maximum drift
      {_, nil} -> 1.0

      {data1, data2} ->
        # Try to get drift from the Rust drift detector via hexad ID
        hexad_id = Map.get(hexad, "id") || Map.get(hexad, :id)

        case hexad_id && RustClient.get_drift_score(hexad_id) do
          {:ok, score} when is_number(score) ->
            score

          _ ->
            # Fallback: compute local drift from modality data
            vec1 = extract_embedding_from_modality(data1)
            vec2 = extract_embedding_from_modality(data2)
            compute_cosine_distance(vec1, vec2)
        end
    end
  end

  defp extract_embedding_from_modality(data) when is_map(data) do
    # Extract a numeric vector from modality data for comparison.
    # Vector modality stores embeddings directly; others use hash fingerprints.
    cond do
      is_list(data["embedding"]) -> data["embedding"]
      is_list(data["vector"]) -> data["vector"]
      is_binary(data["content"]) -> content_fingerprint(data["content"])
      true -> []
    end
  end
  defp extract_embedding_from_modality(data) when is_list(data), do: data
  defp extract_embedding_from_modality(_), do: []

  defp content_fingerprint(text) when is_binary(text) do
    # Simple hash-based fingerprint for non-vector modalities.
    # Produces a 4-element vector from character distribution.
    bytes = :binary.bin_to_list(text)
    len = max(length(bytes), 1)
    quartiles = Enum.chunk_every(bytes, max(div(len, 4), 1))

    Enum.map(quartiles |> Enum.take(4), fn chunk ->
      Enum.sum(chunk) / max(length(chunk), 1) / 255.0
    end)
  end

  defp compute_cosine_distance([], _), do: 0.5  # Unknown = moderate drift
  defp compute_cosine_distance(_, []), do: 0.5
  defp compute_cosine_distance(vec1, vec2) do
    # Cosine distance: 1 - cosine_similarity. Range: [0.0, 2.0], normalized to [0.0, 1.0].
    {dot, mag1, mag2} = Enum.zip(vec1, vec2)
      |> Enum.reduce({0.0, 0.0, 0.0}, fn {a, b}, {d, m1, m2} ->
        {d + a * b, m1 + a * a, m2 + b * b}
      end)

    denom = :math.sqrt(mag1) * :math.sqrt(mag2)

    if denom > 0.0 do
      similarity = dot / denom
      # Clamp and normalize to [0.0, 1.0]
      min(max(1.0 - similarity, 0.0), 1.0)
    else
      1.0  # Zero vectors = max drift
    end
  end

  defp compute_consistency(hexad, mod1, mod2, metric) do
    # Compute consistency score between two modalities using the specified metric.
    # Returns a score in [0.0, 1.0] where 1.0 = perfectly consistent.
    mod1_str = modality_to_string(mod1)
    mod2_str = modality_to_string(mod2)

    data1 = Map.get(hexad, mod1_str)
    data2 = Map.get(hexad, mod2_str)

    case {data1, data2} do
      {nil, _} -> 0.0
      {_, nil} -> 0.0

      {d1, d2} ->
        vec1 = extract_embedding_from_modality(d1)
        vec2 = extract_embedding_from_modality(d2)

        case metric do
          m when m in ["COSINE", :cosine, %{TAG: "Cosine"}] ->
            cosine_similarity(vec1, vec2)

          m when m in ["EUCLIDEAN", :euclidean, %{TAG: "Euclidean"}] ->
            euclidean_similarity(vec1, vec2)

          m when m in ["DOT_PRODUCT", :dot_product, %{TAG: "DotProduct"}] ->
            dot_product_similarity(vec1, vec2)

          m when m in ["JACCARD", :jaccard, %{TAG: "Jaccard"}] ->
            jaccard_similarity(d1, d2)

          _ ->
            cosine_similarity(vec1, vec2)  # Default to cosine
        end
    end
  end

  defp cosine_similarity([], _), do: 0.0
  defp cosine_similarity(_, []), do: 0.0
  defp cosine_similarity(vec1, vec2) do
    {dot, mag1, mag2} = Enum.zip(vec1, vec2)
      |> Enum.reduce({0.0, 0.0, 0.0}, fn {a, b}, {d, m1, m2} ->
        {d + a * b, m1 + a * a, m2 + b * b}
      end)

    denom = :math.sqrt(mag1) * :math.sqrt(mag2)
    if denom > 0.0, do: max(dot / denom, 0.0), else: 0.0
  end

  defp euclidean_similarity([], _), do: 0.0
  defp euclidean_similarity(_, []), do: 0.0
  defp euclidean_similarity(vec1, vec2) do
    dist = Enum.zip(vec1, vec2)
      |> Enum.reduce(0.0, fn {a, b}, acc -> acc + (a - b) * (a - b) end)
      |> :math.sqrt()

    # Convert distance to similarity: 1 / (1 + distance)
    1.0 / (1.0 + dist)
  end

  defp dot_product_similarity([], _), do: 0.0
  defp dot_product_similarity(_, []), do: 0.0
  defp dot_product_similarity(vec1, vec2) do
    dot = Enum.zip(vec1, vec2) |> Enum.reduce(0.0, fn {a, b}, acc -> acc + a * b end)
    # Normalize to [0.0, 1.0] using sigmoid
    1.0 / (1.0 + :math.exp(-dot))
  end

  defp jaccard_similarity(d1, d2) when is_map(d1) and is_map(d2) do
    # Jaccard: |intersection| / |union| of map keys
    keys1 = MapSet.new(Map.keys(d1))
    keys2 = MapSet.new(Map.keys(d2))
    intersection = MapSet.intersection(keys1, keys2) |> MapSet.size()
    union = MapSet.union(keys1, keys2) |> MapSet.size()
    if union > 0, do: intersection / union, else: 0.0
  end
  defp jaccard_similarity(_, _), do: 0.0

  defp compare_values_with_op(val1, op, val2) when is_number(val1) and is_number(val2) do
    case op do
      "==" -> val1 == val2
      "!=" -> val1 != val2
      ">" -> val1 > val2
      "<" -> val1 < val2
      ">=" -> val1 >= val2
      "<=" -> val1 <= val2
      %{TAG: "Eq"} -> val1 == val2
      %{TAG: "Neq"} -> val1 != val2
      %{TAG: "Gt"} -> val1 > val2
      %{TAG: "Lt"} -> val1 < val2
      %{TAG: "Gte"} -> val1 >= val2
      %{TAG: "Lte"} -> val1 <= val2
      _ -> false
    end
  end
  defp compare_values_with_op(val1, op, val2) when is_binary(val1) and is_binary(val2) do
    case op do
      "==" -> val1 == val2
      "!=" -> val1 != val2
      %{TAG: "Eq"} -> val1 == val2
      %{TAG: "Neq"} -> val1 != val2
      _ -> false
    end
  end
  defp compare_values_with_op(_val1, _op, _val2), do: false

  defp modality_to_string(mod) when is_binary(mod), do: String.downcase(mod)
  defp modality_to_string(mod) when is_atom(mod), do: Atom.to_string(mod)
  defp modality_to_string(%{TAG: tag}), do: String.downcase(tag)
  defp modality_to_string(_), do: "unknown"

  # ===========================================================================
  # Phase 3: Mutation Execution
  # ===========================================================================

  defp execute_insert(modality_data, proof, _timeout) do
    proof_result = if proof, do: verify_multi_proof(nil, proof), else: {:ok, []}

    case proof_result do
      {:error, reason} ->
        {:error, {:write_proof_failed, reason}}

      {:ok, _artifacts} ->
        case RustClient.create_hexad(modality_data) do
          {:ok, hexad_id} -> {:ok, %{hexad_id: hexad_id, operation: :insert}}
          {:error, reason} -> {:error, {:insert_failed, reason}}
        end
    end
  rescue
    e -> {:error, {:insert_failed, Exception.message(e)}}
  end

  defp execute_update(hexad_id, sets, proof, _timeout) do
    proof_result = if proof, do: verify_multi_proof(nil, proof), else: {:ok, []}

    case proof_result do
      {:error, reason} ->
        {:error, {:write_proof_failed, reason}}

      {:ok, _artifacts} ->
        field_updates = Enum.map(sets, fn {field_ref, value} ->
          {field_ref, value}
        end)

        case RustClient.update_hexad(hexad_id, field_updates) do
          {:ok, _} -> {:ok, %{hexad_id: hexad_id, operation: :update, fields_updated: length(sets)}}
          {:error, reason} -> {:error, {:update_failed, reason}}
        end
    end
  rescue
    e -> {:error, {:update_failed, Exception.message(e)}}
  end

  defp execute_delete(hexad_id, proof, _timeout) do
    proof_result = if proof, do: verify_multi_proof(nil, proof), else: {:ok, []}

    case proof_result do
      {:error, reason} ->
        {:error, {:write_proof_failed, reason}}

      {:ok, _artifacts} ->
        case RustClient.delete_hexad(hexad_id) do
          {:ok, _} -> {:ok, %{hexad_id: hexad_id, operation: :delete}}
          {:error, reason} -> {:error, {:delete_failed, reason}}
        end
    end
  rescue
    e -> {:error, {:delete_failed, Exception.message(e)}}
  end

  # ===========================================================================
  # Multi-Proof Verification
  # ===========================================================================

  defp verify_multi_proof(_query_ast, proof_specs) when is_list(proof_specs) do
    # Verify each proof in the composition, collecting proof artifacts.
    # Each verify_single_proof/1 returns {:ok, artifact} or {:error, reason}.
    results = Enum.map(proof_specs, fn spec ->
      verify_single_proof(spec)
    end)

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil ->
        # All proofs passed — collect the artifacts for the ProvedResult certificate
        artifacts = Enum.map(results, fn {:ok, artifact} -> artifact end)
        {:ok, artifacts}

      error ->
        error
    end
  end
  defp verify_multi_proof(_query_ast, nil), do: {:ok, []}
  defp verify_multi_proof(_query_ast, proof_specs) do
    # Non-list proof specs are a safety violation — they must not silently pass.
    # This catch-all previously returned :ok, which meant malformed proof specs
    # (e.g., a bare map or atom) would bypass verification entirely.
    {:error, {:invalid_proof_specs, "Expected a list of proof specifications, got: #{inspect(proof_specs)}"}}
  end

  defp verify_single_proof(proof_spec) do
    # Verify a single proof obligation against the VeriSimDB contract registry.
    # Validates proof type, contract existence, and parameter compatibility.
    # Full ZKP witness generation requires the verisim-semantic crate.
    proof_type = extract_proof_type(proof_spec)
    contract_name = extract_contract_name(proof_spec)

    case proof_type do
      :existence ->
        # Existence proofs verify the hexad exists and is accessible.
        entity_id = contract_name || extract_entity_from_proof(proof_spec)

        if entity_id do
          case RustClient.get_hexad(entity_id) do
            {:ok, hexad} ->
              {:ok, %{type: :existence, entity_id: entity_id, verified: true,
                       status: Map.get(hexad, "status", %{})}}
            {:error, :not_found} ->
              {:error, {:existence_failed, "Entity '#{entity_id}' does not exist"}}
            {:error, reason} ->
              {:error, {:existence_check_failed, reason}}
          end
        else
          {:error, {:missing_entity, "Existence proof requires an entity ID or contract name"}}
        end

      :citation ->
        # Citation proofs verify the citation chain is valid
        if contract_name do
          case validate_contract_exists(contract_name) do
            {:ok, artifact} -> {:ok, artifact}
            {:error, _} = err -> err
          end
        else
          {:error, {:missing_contract, "Citation proof requires a contract name"}}
        end

      :access ->
        # Access proofs verify the user has rights via the Rust RBAC module.
        entity_id = contract_name || extract_entity_from_proof(proof_spec)

        if entity_id do
          case RustClient.get("/auth/check/#{entity_id}") do
            {:ok, %{status: 200, body: %{"authorized" => true}}} ->
              {:ok, %{type: :access, entity_id: entity_id, authorized: true}}
            {:ok, %{status: 200, body: %{"authorized" => false}}} ->
              {:error, {:access_denied, "Not authorized to access '#{entity_id}'"}}
            {:ok, %{status: 403}} ->
              {:error, {:access_denied, "Not authorized to access '#{entity_id}'"}}
            {:error, reason} ->
              {:error, {:access_check_failed, reason}}
          end
        else
          # No specific entity — log a warning but allow for global queries.
          Logger.warning("VQL-DT: Access proof without entity ID — global query, skipping entity-level check")
          {:ok, %{type: :access, entity_id: nil, authorized: true, scope: :global}}
        end

      :integrity ->
        # Integrity proofs verify data has not been tampered with.
        # Route to the Rust proofs/generate endpoint for Merkle proof generation.
        if contract_name do
          case RustClient.post("/proofs/generate", %{
                 type: "integrity",
                 contract: contract_name,
                 privacy_level: "public"
               }) do
            {:ok, %{status: 200, body: %{"success" => true} = body}} ->
              {:ok, %{type: :integrity, contract: contract_name, verified: true,
                       proof_data: Map.get(body, "proof")}}
            {:ok, %{status: 200, body: %{"success" => false, "error" => reason}}} ->
              {:error, {:integrity_failed, reason}}
            {:ok, %{status: 200, body: %{"error" => reason}}} ->
              {:error, {:integrity_failed, reason}}
            {:error, reason} ->
              {:error, {:integrity_check_failed, reason}}
          end
        else
          {:error, {:missing_contract, "Integrity proof requires a contract name"}}
        end

      :provenance ->
        # Provenance proofs verify lineage is verifiable via the provenance store.
        # An entity/contract reference is REQUIRED.
        entity_id = contract_name || extract_entity_from_proof(proof_spec)

        if entity_id do
          case RustClient.verify_provenance(entity_id) do
            {:ok, %{"has_provenance" => true, "chain_valid" => true} = body} ->
              {:ok, %{type: :provenance, entity_id: entity_id, chain_valid: true,
                       chain_length: Map.get(body, "chain_length", 0)}}

            {:ok, %{"has_provenance" => true, "chain_valid" => false}} ->
              {:error, {:provenance_chain_broken, entity_id}}

            {:ok, %{"has_provenance" => false}} ->
              {:error, {:no_provenance, "Entity '#{entity_id}' has no provenance chain"}}

            {:error, :not_found} ->
              {:error, {:entity_not_found, entity_id}}

            {:error, reason} ->
              {:error, {:provenance_verify_failed, reason}}
          end
        else
          {:error, {:missing_entity, "Provenance proof requires an entity ID or contract name"}}
        end

      :consistency ->
        # Consistency proofs verify that two or more modalities are in agreement.
        # Uses the Rust drift API to get the cross-modal drift score and compares
        # against the threshold (default: 0.3). Requires an entity ID.
        entity_id = contract_name || extract_entity_from_proof(proof_spec)

        if entity_id do
          case RustClient.get_drift_score(entity_id) do
            {:ok, score} when is_number(score) ->
              threshold = Map.get(proof_spec, :threshold, 0.3)
              if score <= threshold do
                {:ok, %{type: :consistency, entity_id: entity_id, drift_score: score,
                         threshold: threshold, consistent: true}}
              else
                {:error, {:consistency_failed,
                  "Entity '#{entity_id}' drift score #{score} exceeds threshold #{threshold}"}}
              end

            {:error, reason} ->
              {:error, {:consistency_check_failed, reason}}
          end
        else
          {:error, {:missing_entity, "Consistency proof requires an entity ID"}}
        end

      :freshness ->
        # Freshness proofs verify that entity data is recent enough.
        # Checks the temporal modality's last-modified timestamp against
        # a maximum age (default: 1 hour = 3_600_000ms).
        entity_id = contract_name || extract_entity_from_proof(proof_spec)

        if entity_id do
          case RustClient.get_hexad(entity_id) do
            {:ok, hexad} ->
              max_age_ms = Map.get(proof_spec, :max_age_ms, 3_600_000)
              temporal = Map.get(hexad, "temporal", %{})
              last_modified = Map.get(temporal, "last_modified") ||
                              Map.get(temporal, "updated_at") ||
                              Map.get(hexad, "updated_at")

              if last_modified do
                age_ms = case DateTime.from_iso8601(to_string(last_modified)) do
                  {:ok, dt, _} ->
                    DateTime.diff(DateTime.utc_now(), dt, :millisecond)
                  _ ->
                    # If timestamp is a unix epoch, convert
                    if is_number(last_modified) do
                      now_ms = System.system_time(:millisecond)
                      now_ms - trunc(last_modified)
                    else
                      max_age_ms + 1  # Unknown format — treat as stale
                    end
                end

                if age_ms <= max_age_ms do
                  {:ok, %{type: :freshness, entity_id: entity_id, age_ms: age_ms,
                           max_age_ms: max_age_ms, fresh: true}}
                else
                  {:error, {:freshness_expired,
                    "Entity '#{entity_id}' is #{age_ms}ms old, exceeds max age #{max_age_ms}ms"}}
                end
              else
                {:error, {:no_temporal_data,
                  "Entity '#{entity_id}' has no temporal/timestamp data for freshness check"}}
              end

            {:error, :not_found} ->
              {:error, {:entity_not_found, entity_id}}

            {:error, reason} ->
              {:error, {:freshness_check_failed, reason}}
          end
        else
          {:error, {:missing_entity, "Freshness proof requires an entity ID"}}
        end

      :custom ->
        # Custom ZKP proofs route to the circuit-specific proof generation endpoint
        if contract_name do
          claim = Map.get(proof_spec, :claim, "")

          case RustClient.post("/proofs/generate-with-circuit", %{
                 circuit: contract_name,
                 claim: claim,
                 privacy_level: Map.get(proof_spec, :privacy_level, "public")
               }) do
            {:ok, %{status: 200, body: %{"success" => true} = body}} ->
              {:ok, %{type: :custom, circuit: contract_name, verified: true,
                       proof_data: Map.get(body, "proof")}}
            {:ok, %{status: 200, body: %{"error" => reason}}} ->
              {:error, {:custom_proof_failed, reason}}
            {:error, reason} ->
              {:error, {:custom_proof_failed, reason}}
          end
        else
          {:error, {:missing_contract, "Custom proof requires a circuit/contract name"}}
        end

      :zkp ->
        # ZKP proofs route to the zkp_bridge via the Rust API.
        # When the type checker provides witness_fields and circuit, include them
        # for richer proof generation (privacy-aware with blinding).
        privacy_level = Map.get(proof_spec, :privacy_level, "public")
        claim = Map.get(proof_spec, :claim, "")
        witness = Map.get(proof_spec, :witness_fields, [])
        circuit = Map.get(proof_spec, :circuit)

        request = %{claim: claim, privacy_level: privacy_level}
        request = if witness != [], do: Map.put(request, :witness, witness), else: request
        request = if circuit, do: Map.put(request, :circuit_name, circuit), else: request

        case RustClient.post("/proofs/generate", request) do
          {:ok, %{status: 200, body: %{"success" => true} = body}} ->
            {:ok, %{type: :zkp, verified: true, privacy_level: privacy_level,
                     proof_data: Map.get(body, "proof")}}
          {:ok, %{status: 200, body: %{"error" => reason}}} ->
            {:error, {:zkp_failed, reason}}
          {:error, reason} ->
            {:error, {:zkp_unavailable, reason}}
        end

      :proven ->
        # Proven proofs verify against certificates from the proven library
        claim = Map.get(proof_spec, :claim, "")
        case RustClient.post("/proofs/generate", %{claim: claim, privacy_level: "public"}) do
          {:ok, %{status: 200, body: %{"success" => true} = body}} ->
            {:ok, %{type: :proven, verified: true,
                     proof_data: Map.get(body, "proof")}}
          _ ->
            {:error, {:proven_unavailable, "proven certificate verification failed"}}
        end

      :sanctify ->
        # Sanctify proofs verify security contracts from sanctify-php
        if contract_name do
          case validate_contract_exists(contract_name) do
            {:ok, artifact} -> {:ok, artifact}
            {:error, _} = err -> err
          end
        else
          {:error, {:missing_contract, "Sanctify proof requires a contract name"}}
        end

      _ ->
        {:error, {:unknown_proof_type, proof_type}}
    end
  end

  defp extract_proof_type(%{proofType: type}), do: normalize_proof_type(type)
  defp extract_proof_type(%{TAG: tag}), do: normalize_proof_type(tag)
  defp extract_proof_type(%{raw: raw}) when is_binary(raw) do
    # Raw proof strings look like "EXISTENCE(entity-001)" or "EXISTENCE entity-001".
    # Extract just the proof type name (before any parens or whitespace).
    raw
    |> String.split(~r/[\s(]/, parts: 2)
    |> List.first()
    |> normalize_proof_type()
  end
  defp extract_proof_type(_), do: :unknown

  defp normalize_proof_type("EXISTENCE"), do: :existence
  defp normalize_proof_type("CITATION"), do: :citation
  defp normalize_proof_type("ACCESS"), do: :access
  defp normalize_proof_type("INTEGRITY"), do: :integrity
  defp normalize_proof_type("CONSISTENCY"), do: :consistency
  defp normalize_proof_type("PROVENANCE"), do: :provenance
  defp normalize_proof_type("FRESHNESS"), do: :freshness
  defp normalize_proof_type("CUSTOM"), do: :custom
  defp normalize_proof_type("ZKP"), do: :zkp
  defp normalize_proof_type("PROVEN"), do: :proven
  defp normalize_proof_type("SANCTIFY"), do: :sanctify
  defp normalize_proof_type(%{TAG: tag}), do: normalize_proof_type(tag)
  defp normalize_proof_type(atom) when is_atom(atom), do: atom
  defp normalize_proof_type(str) when is_binary(str) do
    try do
      String.downcase(str) |> String.to_existing_atom()
    rescue
      ArgumentError -> :unknown
    end
  end
  defp normalize_proof_type(_), do: :unknown

  defp extract_contract_name(%{contractName: name}), do: name
  defp extract_contract_name(%{contract: name}), do: name
  defp extract_contract_name(%{raw: raw}) when is_binary(raw) do
    # Extract contract name from raw proof spec: "INTEGRITY(my_contract)"
    case Regex.run(~r/\(([^)]+)\)/, raw) do
      [_, name] -> String.trim(name)
      _ -> nil
    end
  end
  defp extract_contract_name(_), do: nil

  defp validate_contract_exists(contract_name) do
    # Check if the contract exists in the semantic store via search.
    # If the store is unreachable, the proof MUST fail — silently passing
    # would defeat the purpose of verified queries.
    case RustClient.search_text("contract:#{contract_name}", 1) do
      {:ok, results} when is_list(results) and length(results) > 0 ->
        {:ok, %{type: :contract_verified, contract: contract_name, verified: true}}
      {:ok, %{"results" => [_ | _]}} ->
        {:ok, %{type: :contract_verified, contract: contract_name, verified: true}}
      {:ok, _} ->
        {:error, {:contract_not_found, contract_name}}
      {:error, reason} ->
        {:error, {:contract_verification_failed, reason}}
    end
  end

  defp extract_entity_from_proof(%{entity_id: id}), do: id
  defp extract_entity_from_proof(%{entityId: id}), do: id
  defp extract_entity_from_proof(%{hexad_id: id}), do: id
  defp extract_entity_from_proof(%{hexadId: id}), do: id
  defp extract_entity_from_proof(_), do: nil

  # ---------------------------------------------------------------------------
  # Proof obligation structuring (fallback when type checker unavailable)
  # ---------------------------------------------------------------------------

  # Proof obligation structuring and composition determination are now handled
  # by VeriSim.Query.VQLTypeChecker, which provides richer validation and
  # enrichment (witness fields, circuit names, time estimates).

  # ===========================================================================
  # Query execution by source type
  # ===========================================================================

  defp execute_hexad_query(entity_id, modalities, where_clause, limit, offset, _timeout) do
    case RustClient.get_hexad(entity_id) do
      {:ok, hexad} ->
        filtered = filter_hexad(hexad, modalities, where_clause)
        paginated = paginate_results([filtered], limit, offset)
        {:ok, paginated}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute_federation_query(pattern, drift_policy, modalities, where_clause, limit, offset, timeout) do
    Logger.info("Federation query: pattern=#{inspect(pattern)}, drift=#{inspect(drift_policy)}")

    # Delegate to Rust federation API which handles peer discovery and fan-out
    federation_params = %{
      pattern: pattern,
      drift_policy: drift_policy_to_string(drift_policy),
      modalities: Enum.map(modalities, &to_string/1),
      limit: limit || 100,
      offset: offset || 0,
      timeout_ms: timeout
    }

    # Add query parameters if WHERE clause exists
    federation_params = if where_clause do
      text = case where_clause do
        %{raw: raw} -> raw
        _ -> nil
      end
      if text, do: Map.put(federation_params, :text_query, text), else: federation_params
    else
      federation_params
    end

    case RustClient.post("/federation/query", federation_params) do
      {:ok, %{status: 200, body: body}} when is_list(body) ->
        {:ok, body}

      {:ok, %{status: 200, body: %{"results" => results}}} when is_list(results) ->
        {:ok, results}

      {:ok, %{status: 200, body: body}} when is_map(body) ->
        {:ok, Map.get(body, "results", [])}

      {:ok, %{status: status, body: body}} ->
        Logger.warning("Federation query returned status #{status}: #{inspect(body)}")
        {:error, {:federation_error, status, body}}

      {:error, reason} ->
        Logger.warning("Federation query failed: #{inspect(reason)}")
        # Graceful degradation: return empty results instead of crashing
        {:ok, []}
    end
  end

  defp drift_policy_to_string(:strict), do: "strict"
  defp drift_policy_to_string(:repair), do: "repair"
  defp drift_policy_to_string(:tolerate), do: "tolerate"
  defp drift_policy_to_string(:latest), do: "latest"
  defp drift_policy_to_string(nil), do: "tolerate"
  defp drift_policy_to_string(s) when is_binary(s), do: s

  defp execute_store_query(store_id, modalities, where_clause, limit, _offset, _timeout) do
    Logger.info("Store query: store_id=#{store_id}")

    query_type = determine_query_type(modalities, where_clause)

    case query_type do
      :text ->
        text_query = extract_text_query(where_clause)
        QueryRouter.query(:text, text_query, limit: limit || 10)

      :vector ->
        {embedding, _threshold} = extract_vector_query(where_clause)
        QueryRouter.query(:vector, embedding, k: limit || 10)

      :graph ->
        graph_params = extract_graph_query(where_clause)
        QueryRouter.query(:graph, graph_params)

      :provenance ->
        provenance_params = extract_provenance_query(where_clause)
        execute_provenance_query(provenance_params, limit)

      :spatial ->
        spatial_params = extract_spatial_query(where_clause)
        execute_spatial_query(spatial_params, limit)

      :multi ->
        params = extract_multi_modal_params(modalities, where_clause)
        QueryRouter.query(:multi, params, limit: limit || 10)

      _ ->
        {:error, :unsupported_query_type}
    end
  end

  defp execute_reflect_query(modalities, where_clause, limit, _offset, _timeout) do
    # REFLECT queries the query store itself — meta-circular homoiconicity.
    # Stored queries are hexads, so we search them via the /queries/similar
    # and /search/text endpoints filtered to type=vql_query.
    Logger.info("REFLECT query: querying the query store")

    text_query = extract_text_query(where_clause)
    search_limit = limit || 20

    # Search stored queries by text similarity
    result = if text_query != "" do
      case RustClient.post("/search/text", %{q: "type:vql_query #{text_query}", limit: search_limit}) do
        {:ok, %{status: 200, body: %{"results" => results}}} -> {:ok, results}
        {:ok, %{status: 200, body: body}} when is_list(body) -> {:ok, body}
        {:ok, %{status: 200, body: body}} when is_map(body) -> {:ok, Map.get(body, "results", [])}
        {:error, reason} -> {:error, {:reflect_query_failed, reason}}
        _ -> {:ok, []}
      end
    else
      # No text filter — list all stored queries
      case RustClient.post("/search/text", %{q: "type:vql_query", limit: search_limit}) do
        {:ok, %{status: 200, body: %{"results" => results}}} -> {:ok, results}
        {:ok, %{status: 200, body: body}} when is_list(body) -> {:ok, body}
        {:ok, %{status: 200, body: body}} when is_map(body) -> {:ok, Map.get(body, "results", [])}
        {:error, reason} -> {:error, {:reflect_query_failed, reason}}
        _ -> {:ok, []}
      end
    end

    # Enrich results with query-specific metadata
    case result do
      {:ok, rows} ->
        enriched = Enum.map(rows, fn row ->
          row
          |> Map.put("_source", "reflect")
          |> Map.put("_type", "stored_query")
          |> maybe_filter_modalities(modalities)
        end)
        {:ok, enriched}

      error -> error
    end
  end

  defp maybe_filter_modalities(row, [:all]), do: row
  defp maybe_filter_modalities(row, modalities) do
    mod_strings = Enum.map(modalities, &to_string/1)
    base_keys = ["id", "_source", "_type", "status"]
    keep_keys = base_keys ++ mod_strings
    Map.take(row, keep_keys ++ Map.keys(row) |> Enum.filter(fn k ->
      Enum.any?(mod_strings, &String.starts_with?(k, &1))
    end))
  end

  defp filter_hexad(hexad, modalities, _where_clause) do
    if :all in modalities do
      hexad
    else
      Map.take(hexad, modalities |> Enum.map(&to_string/1))
    end
  end

  defp paginate_results(results, nil, nil), do: results
  defp paginate_results(results, limit, nil), do: Enum.take(results, limit)
  defp paginate_results(results, nil, offset), do: Enum.drop(results, offset)
  defp paginate_results(results, limit, offset) do
    results
    |> Enum.drop(offset)
    |> Enum.take(limit)
  end

  defp determine_query_type(modalities, where_clause) do
    cond do
      has_fulltext_condition?(where_clause) -> :text
      has_vector_condition?(where_clause) -> :vector
      has_graph_pattern?(where_clause) -> :graph
      has_provenance_condition?(where_clause) -> :provenance
      has_spatial_condition?(where_clause) -> :spatial
      length(modalities) > 1 -> :multi
      true -> :multi
    end
  end

  # AST-walking condition detectors: check TAG values for modality-specific conditions

  defp has_fulltext_condition?(nil), do: false
  defp has_fulltext_condition?(%{raw: raw}) when is_binary(raw) do
    upper = String.upcase(raw)
    String.contains?(upper, "FULLTEXT") or String.contains?(upper, "CONTAINS") or
    String.contains?(upper, "MATCHES")
  end
  defp has_fulltext_condition?(%{TAG: tag}) when tag in ["FulltextContains", "FulltextMatches", "DocumentCondition"], do: true
  defp has_fulltext_condition?(%{TAG: "And", _0: left, _1: right}), do: has_fulltext_condition?(left) or has_fulltext_condition?(right)
  defp has_fulltext_condition?(%{TAG: "Or", _0: left, _1: right}), do: has_fulltext_condition?(left) or has_fulltext_condition?(right)
  defp has_fulltext_condition?(%{TAG: "Not", _0: inner}), do: has_fulltext_condition?(inner)
  defp has_fulltext_condition?(_), do: false

  defp has_vector_condition?(nil), do: false
  defp has_vector_condition?(%{raw: raw}) when is_binary(raw) do
    upper = String.upcase(raw)
    String.contains?(upper, "SIMILAR") or String.contains?(upper, "NEAREST")
  end
  defp has_vector_condition?(%{TAG: tag}) when tag in ["VectorSimilar", "VectorNearest", "VectorCondition"], do: true
  defp has_vector_condition?(%{TAG: "And", _0: left, _1: right}), do: has_vector_condition?(left) or has_vector_condition?(right)
  defp has_vector_condition?(%{TAG: "Or", _0: left, _1: right}), do: has_vector_condition?(left) or has_vector_condition?(right)
  defp has_vector_condition?(%{TAG: "Not", _0: inner}), do: has_vector_condition?(inner)
  defp has_vector_condition?(_), do: false

  defp has_graph_pattern?(nil), do: false
  defp has_graph_pattern?(%{raw: raw}) when is_binary(raw) do
    # Graph patterns use SPARQL-like syntax with arrow edges
    String.contains?(raw, "->") or String.contains?(raw, "-[")
  end
  defp has_graph_pattern?(%{TAG: tag}) when tag in ["SparqlPattern", "PathPattern", "GraphCondition"], do: true
  defp has_graph_pattern?(%{TAG: "And", _0: left, _1: right}), do: has_graph_pattern?(left) or has_graph_pattern?(right)
  defp has_graph_pattern?(%{TAG: "Or", _0: left, _1: right}), do: has_graph_pattern?(left) or has_graph_pattern?(right)
  defp has_graph_pattern?(%{TAG: "Not", _0: inner}), do: has_graph_pattern?(inner)
  defp has_graph_pattern?(_), do: false

  # Provenance condition detection: actor, origin, chain_valid, event_type queries
  defp has_provenance_condition?(nil), do: false
  defp has_provenance_condition?(%{raw: raw}) when is_binary(raw) do
    upper = String.upcase(raw)
    String.contains?(upper, "PROVENANCE.") or String.contains?(upper, "CHAIN_VALID") or
    String.contains?(upper, "CHAIN_LENGTH")
  end
  defp has_provenance_condition?(%{TAG: tag}) when tag in [
    "ProvenanceActor", "ProvenanceOrigin", "ProvenanceChainValid",
    "ProvenanceEventType", "ProvenanceCondition"
  ], do: true
  defp has_provenance_condition?(%{TAG: "And", _0: left, _1: right}), do: has_provenance_condition?(left) or has_provenance_condition?(right)
  defp has_provenance_condition?(%{TAG: "Or", _0: left, _1: right}), do: has_provenance_condition?(left) or has_provenance_condition?(right)
  defp has_provenance_condition?(%{TAG: "Not", _0: inner}), do: has_provenance_condition?(inner)
  defp has_provenance_condition?(%{modality: mod}) when mod in [:provenance, "PROVENANCE", "provenance"], do: true
  defp has_provenance_condition?(_), do: false

  # Spatial condition detection: radius, bounding box, nearest queries
  defp has_spatial_condition?(nil), do: false
  defp has_spatial_condition?(%{raw: raw}) when is_binary(raw) do
    upper = String.upcase(raw)
    String.contains?(upper, "WITHIN RADIUS") or String.contains?(upper, "WITHIN BOUNDS") or
    String.contains?(upper, "SPATIAL.") or String.contains?(upper, "NEAREST")
  end
  defp has_spatial_condition?(%{TAG: tag}) when tag in [
    "SpatialRadius", "SpatialBounds", "SpatialNearest",
    "SpatialCondition", "WithinRadius", "WithinBounds"
  ], do: true
  defp has_spatial_condition?(%{TAG: "And", _0: left, _1: right}), do: has_spatial_condition?(left) or has_spatial_condition?(right)
  defp has_spatial_condition?(%{TAG: "Or", _0: left, _1: right}), do: has_spatial_condition?(left) or has_spatial_condition?(right)
  defp has_spatial_condition?(%{TAG: "Not", _0: inner}), do: has_spatial_condition?(inner)
  defp has_spatial_condition?(%{modality: mod}) when mod in [:spatial, "SPATIAL", "spatial"], do: true
  defp has_spatial_condition?(_), do: false

  # AST-walking query extractors: pull actual values from parsed conditions

  defp extract_text_query(nil), do: ""
  defp extract_text_query(%{raw: raw}) when is_binary(raw) do
    # Extract text between quotes from raw WHERE clause: FULLTEXT CONTAINS 'search terms'
    case Regex.run(~r/'([^']*)'/, raw) do
      [_, text] -> text
      _ ->
        # Try without quotes: FULLTEXT CONTAINS keyword
        case Regex.run(~r/(?:CONTAINS|MATCHES)\s+(.+?)(?:\s+AND|\s+OR|\s*$)/i, raw) do
          [_, text] -> String.trim(text)
          _ -> raw  # Use the raw clause as search text
        end
    end
  end
  defp extract_text_query(%{TAG: "FulltextContains", _0: text}), do: text
  defp extract_text_query(%{TAG: "FulltextMatches", _0: pattern}), do: pattern
  defp extract_text_query(%{TAG: "And", _0: left, _1: right}) do
    case {has_fulltext_condition?(left), has_fulltext_condition?(right)} do
      {true, _} -> extract_text_query(left)
      {_, true} -> extract_text_query(right)
      _ -> ""
    end
  end
  defp extract_text_query(_), do: ""

  defp extract_vector_query(nil), do: {[], 0.9}
  defp extract_vector_query(%{raw: raw}) when is_binary(raw) do
    # Extract vector literal [0.1, 0.2, ...] and optional WITHIN threshold
    vector = case Regex.run(~r/\[([0-9.,\s-]+)\]/, raw) do
      [_, nums] ->
        nums
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.flat_map(fn s ->
          case Float.parse(s) do
            {f, _} -> [f]
            :error -> []
          end
        end)
      _ -> []
    end

    threshold = case Regex.run(~r/WITHIN\s+([0-9.]+)/i, raw) do
      [_, t] ->
        case Float.parse(t) do
          {f, _} -> f
          :error -> 0.9
        end
      _ -> 0.9
    end

    {vector, threshold}
  end
  defp extract_vector_query(%{TAG: "VectorSimilar", _0: _field, _1: vector, _2: threshold}) do
    {vector, threshold || 0.9}
  end
  defp extract_vector_query(%{TAG: "VectorNearest", _0: _field, _1: k}) do
    {[], k}  # k-nearest doesn't have a vector, uses the field's own embedding
  end
  defp extract_vector_query(%{TAG: "And", _0: left, _1: right}) do
    case {has_vector_condition?(left), has_vector_condition?(right)} do
      {true, _} -> extract_vector_query(left)
      {_, true} -> extract_vector_query(right)
      _ -> {[], 0.9}
    end
  end
  defp extract_vector_query(_), do: {[], 0.9}

  defp extract_graph_query(nil), do: %{}
  defp extract_graph_query(%{raw: raw}) when is_binary(raw) do
    # Parse simple SPARQL-like patterns from raw WHERE clause
    %{raw_pattern: raw}
  end
  defp extract_graph_query(%{TAG: "SparqlPattern", _0: node1, _1: edge, _2: node2}) do
    %{subject: node1, predicate: edge, object: node2}
  end
  defp extract_graph_query(%{TAG: "PathPattern", _0: start, _1: edge, _2: finish}) do
    %{start: start, edge: edge, finish: finish, traversal: true}
  end
  defp extract_graph_query(%{TAG: "And", _0: left, _1: right}) do
    case {has_graph_pattern?(left), has_graph_pattern?(right)} do
      {true, _} -> extract_graph_query(left)
      {_, true} -> extract_graph_query(right)
      _ -> %{}
    end
  end
  defp extract_graph_query(_), do: %{}

  # ---------------------------------------------------------------------------
  # Provenance query extraction and execution
  # ---------------------------------------------------------------------------

  defp extract_provenance_query(nil), do: %{}
  defp extract_provenance_query(%{raw: raw}) when is_binary(raw) do
    params = %{}

    # Extract actor filter: PROVENANCE.actor = 'someone'
    params = case Regex.run(~r/(?:PROVENANCE\.)?actor\s*=\s*'([^']+)'/i, raw) do
      [_, actor] -> Map.put(params, :actor, actor)
      _ -> params
    end

    # Extract origin filter: PROVENANCE.origin = 'source'
    params = case Regex.run(~r/(?:PROVENANCE\.)?origin\s*=\s*'([^']+)'/i, raw) do
      [_, origin] -> Map.put(params, :origin, origin)
      _ -> params
    end

    # Extract chain_valid filter: PROVENANCE.chain_valid = true
    params = case Regex.run(~r/(?:PROVENANCE\.)?chain_valid\s*=\s*(true|false)/i, raw) do
      [_, val] -> Map.put(params, :chain_valid, String.downcase(val) == "true")
      _ -> params
    end

    # Extract event_type filter: PROVENANCE.event_type = 'Modified'
    params = case Regex.run(~r/(?:PROVENANCE\.)?event_type\s*=\s*'([^']+)'/i, raw) do
      [_, et] -> Map.put(params, :event_type, et)
      _ -> params
    end

    params
  end
  defp extract_provenance_query(%{TAG: "ProvenanceActor", _0: actor}), do: %{actor: actor}
  defp extract_provenance_query(%{TAG: "ProvenanceOrigin", _0: origin}), do: %{origin: origin}
  defp extract_provenance_query(%{TAG: "ProvenanceChainValid", _0: valid}), do: %{chain_valid: valid}
  defp extract_provenance_query(%{TAG: "ProvenanceEventType", _0: event_type}), do: %{event_type: event_type}
  defp extract_provenance_query(%{TAG: "And", _0: left, _1: right}) do
    Map.merge(extract_provenance_query(left), extract_provenance_query(right))
  end
  defp extract_provenance_query(%{modality: mod, field: field, value: value})
    when mod in [:provenance, "PROVENANCE", "provenance"] do
    %{String.to_existing_atom(field) => value}
  end
  defp extract_provenance_query(_), do: %{}

  defp execute_provenance_query(params, limit) do
    # Route to dedicated RustClient provenance methods for caching and telemetry
    cond do
      Map.has_key?(params, :entity_id) ->
        # Get the full provenance chain for a specific entity
        case RustClient.get_provenance_chain(params.entity_id) do
          {:ok, body} -> {:ok, wrap_provenance_results(body)}
          {:error, :not_found} -> {:ok, []}
          {:error, reason} -> {:error, {:provenance_query_failed, reason}}
        end

      Map.has_key?(params, :verify_entity_id) ->
        # Verify chain integrity for a specific entity
        case RustClient.verify_provenance(params.verify_entity_id) do
          {:ok, body} -> {:ok, wrap_provenance_results([body])}
          {:error, :not_found} -> {:ok, []}
          {:error, reason} -> {:error, {:provenance_query_failed, reason}}
        end

      Map.has_key?(params, :actor) ->
        # Search by actor — uses the provenance search-by-actor endpoint
        case RustClient.post("/provenance/search", %{actor: params.actor, limit: limit || 50}) do
          {:ok, %{status: 200, body: body}} -> {:ok, wrap_provenance_results(body)}
          {:error, reason} -> {:error, {:provenance_query_failed, reason}}
          _ -> {:ok, []}
        end

      Map.has_key?(params, :chain_valid) ->
        # Verify chain integrity across all provenance chains
        case RustClient.get("/provenance/verify-all") do
          {:ok, %{status: 200, body: body}} when is_list(body) ->
            filtered = if params.chain_valid do
              Enum.filter(body, &(&1["chain_valid"] == true))
            else
              Enum.filter(body, &(&1["chain_valid"] == false))
            end
            {:ok, wrap_provenance_results(filtered)}
          {:ok, %{status: 200, body: body}} when is_map(body) ->
            {:ok, wrap_provenance_results(Map.get(body, "results", []))}
          {:error, reason} -> {:error, {:provenance_query_failed, reason}}
          _ -> {:ok, []}
        end

      true ->
        # Generic provenance search with all params
        case RustClient.post("/provenance/search", Map.put(params, :limit, limit || 50)) do
          {:ok, %{status: 200, body: body}} -> {:ok, wrap_provenance_results(body)}
          {:error, reason} -> {:error, {:provenance_query_failed, reason}}
          _ -> {:ok, []}
        end
    end
  end

  defp wrap_provenance_results(body) when is_list(body) do
    Enum.map(body, fn item ->
      %{"provenance" => item, "_source" => "provenance"}
    end)
  end
  defp wrap_provenance_results(body) when is_map(body) do
    results = Map.get(body, "results", [body])
    wrap_provenance_results(results)
  end
  defp wrap_provenance_results(_), do: []

  # ---------------------------------------------------------------------------
  # Spatial query extraction and execution
  # ---------------------------------------------------------------------------

  defp extract_spatial_query(nil), do: %{}
  defp extract_spatial_query(%{raw: raw}) when is_binary(raw) do
    upper = String.upcase(raw)

    cond do
      # WITHIN RADIUS(lat, lon, radius_km)
      String.contains?(upper, "WITHIN RADIUS") ->
        case Regex.run(~r/WITHIN\s+RADIUS\s*\(\s*([0-9.\-]+)\s*,\s*([0-9.\-]+)\s*,\s*([0-9.]+)\s*\)/i, raw) do
          [_, lat, lon, radius] ->
            %{type: :radius,
              latitude: parse_float_safe(lat),
              longitude: parse_float_safe(lon),
              radius_km: parse_float_safe(radius)}
          _ -> %{}
        end

      # WITHIN BOUNDS(min_lat, min_lon, max_lat, max_lon)
      String.contains?(upper, "WITHIN BOUNDS") ->
        case Regex.run(~r/WITHIN\s+BOUNDS\s*\(\s*([0-9.\-]+)\s*,\s*([0-9.\-]+)\s*,\s*([0-9.\-]+)\s*,\s*([0-9.\-]+)\s*\)/i, raw) do
          [_, min_lat, min_lon, max_lat, max_lon] ->
            %{type: :bounds,
              min_lat: parse_float_safe(min_lat),
              min_lon: parse_float_safe(min_lon),
              max_lat: parse_float_safe(max_lat),
              max_lon: parse_float_safe(max_lon)}
          _ -> %{}
        end

      # NEAREST(lat, lon, k)
      String.contains?(upper, "NEAREST") ->
        case Regex.run(~r/NEAREST\s*\(\s*([0-9.\-]+)\s*,\s*([0-9.\-]+)\s*,\s*([0-9]+)\s*\)/i, raw) do
          [_, lat, lon, k] ->
            %{type: :nearest,
              latitude: parse_float_safe(lat),
              longitude: parse_float_safe(lon),
              k: String.to_integer(k)}
          _ -> %{}
        end

      true -> %{}
    end
  end
  defp extract_spatial_query(%{TAG: "SpatialRadius", _0: lat, _1: lon, _2: radius}) do
    %{type: :radius, latitude: lat, longitude: lon, radius_km: radius}
  end
  defp extract_spatial_query(%{TAG: "SpatialBounds", _0: min_lat, _1: min_lon, _2: max_lat, _3: max_lon}) do
    %{type: :bounds, min_lat: min_lat, min_lon: min_lon, max_lat: max_lat, max_lon: max_lon}
  end
  defp extract_spatial_query(%{TAG: "SpatialNearest", _0: lat, _1: lon, _2: k}) do
    %{type: :nearest, latitude: lat, longitude: lon, k: k}
  end
  defp extract_spatial_query(%{TAG: "And", _0: left, _1: right}) do
    case {has_spatial_condition?(left), has_spatial_condition?(right)} do
      {true, _} -> extract_spatial_query(left)
      {_, true} -> extract_spatial_query(right)
      _ -> %{}
    end
  end
  defp extract_spatial_query(_), do: %{}

  defp execute_spatial_query(params, limit) do
    # Route to dedicated RustClient spatial methods for caching and telemetry
    case Map.get(params, :type) do
      :radius ->
        case RustClient.search_spatial_radius(
               params.latitude,
               params.longitude,
               params.radius_km,
               limit: limit || 50
             ) do
          {:ok, results} -> {:ok, wrap_spatial_results(results)}
          {:error, reason} -> {:error, {:spatial_query_failed, reason}}
        end

      :bounds ->
        case RustClient.search_spatial_bounds(
               params.min_lat,
               params.min_lon,
               params.max_lat,
               params.max_lon,
               limit: limit || 50
             ) do
          {:ok, results} -> {:ok, wrap_spatial_results(results)}
          {:error, reason} -> {:error, {:spatial_query_failed, reason}}
        end

      :nearest ->
        k = params[:k] || limit || 10

        case RustClient.search_spatial_nearest(
               params.latitude,
               params.longitude,
               k
             ) do
          {:ok, results} -> {:ok, wrap_spatial_results(results)}
          {:error, reason} -> {:error, {:spatial_query_failed, reason}}
        end

      _ ->
        {:error, {:invalid_spatial_query, "Missing spatial query type (radius, bounds, or nearest)"}}
    end
  end

  defp wrap_spatial_results(body) when is_list(body) do
    Enum.map(body, fn item ->
      %{"spatial" => item, "_source" => "spatial",
        "distance_km" => Map.get(item, "distance_km")}
    end)
  end
  defp wrap_spatial_results(body) when is_map(body) do
    results = Map.get(body, "results", [body])
    wrap_spatial_results(results)
  end
  defp wrap_spatial_results(_), do: []

  defp parse_float_safe(str) when is_binary(str) do
    case Float.parse(str) do
      {f, _} -> f
      :error -> 0.0
    end
  end
  defp parse_float_safe(num) when is_number(num), do: num / 1
  defp parse_float_safe(_), do: 0.0

  defp extract_multi_modal_params(modalities, where_clause) do
    %{modalities: modalities, conditions: where_clause}
  end

  defp generate_explain_plan(query_ast) do
    # Generate a cost-aware execution plan based on actual query structure.
    # Tries the Rust verisim-planner first; falls back to local estimation.
    modalities = extract_modalities(query_ast)
    source = extract_source(query_ast)
    where_clause = extract_where(query_ast)
    proof_specs = extract_proof(query_ast)
    group_by = extract_group_by(query_ast)
    {_pushdown, cross_modal} = classify_conditions(where_clause)

    # Try Rust planner API for optimized plan
    case RustClient.post("/query/explain", %{query_ast: query_ast}) do
      {:ok, %{status: 200, body: plan}} ->
        plan

      _ ->
        # Fallback: local cost estimation
        steps = []

        # Step 1: Parse (already done)
        steps = [%{operation: "Parse VQL", cost_ms: 1, notes: "Already completed"} | steps]

        # Step 2: Type check (if proofs present)
        steps = if proof_specs do
          proof_count = length(proof_specs)
          [%{operation: "Type check + proof verification", cost_ms: 5 * proof_count,
             notes: "#{proof_count} proof obligation(s)"} | steps]
        else
          steps
        end

        # Step 3: Route to stores
        {source_type, source_cost, source_notes} = case source do
          {:hexad, id} -> {"Hexad lookup", 2, "Direct ID: #{id}"}
          {:federation, pattern, _} -> {"Federation fan-out", 100, "Pattern: #{inspect(pattern)}"}
          {:store, id} -> {"Store query", 15, "Store: #{id}"}
          :reflect -> {"REFLECT (meta-query)", 20, "Query the query store itself"}
        end
        steps = [%{operation: source_type, cost_ms: source_cost, notes: source_notes} | steps]

        # Step 4: Modality queries
        modality_cost = length(modalities) * 10
        steps = [%{operation: "Query #{length(modalities)} modality store(s)",
                   cost_ms: modality_cost,
                   modalities: Enum.map(modalities, &to_string/1)} | steps]

        # Step 5: Where clause evaluation
        where_cost = if where_clause, do: 5, else: 0
        steps = if where_clause do
          query_type = determine_query_type(modalities, where_clause)
          [%{operation: "Evaluate WHERE (#{query_type})", cost_ms: where_cost} | steps]
        else
          steps
        end

        # Step 6: Cross-modal evaluation (if any)
        steps = if cross_modal != [] do
          [%{operation: "Cross-modal evaluation", cost_ms: 20 * length(cross_modal),
             conditions: length(cross_modal),
             notes: "Post-fetch filter across modalities"} | steps]
        else
          steps
        end

        # Step 7: Aggregation (if GROUP BY present)
        steps = if group_by do
          [%{operation: "Group + Aggregate", cost_ms: 8,
             group_fields: length(group_by)} | steps]
        else
          steps
        end

        steps = Enum.reverse(steps)
        total = Enum.reduce(steps, 0, fn step, acc -> acc + Map.get(step, :cost_ms, 0) end)

        %{
          strategy: if(cross_modal != [], do: :two_phase, else: :sequential),
          steps: steps,
          total_cost_ms: total,
          modalities_queried: modalities,
          has_cross_modal: cross_modal != [],
          has_proof: proof_specs != nil
        }
    end
  end

  # ---------------------------------------------------------------------------
  # Post-processing: GROUP BY, Aggregation, ORDER BY, Projection
  # ---------------------------------------------------------------------------

  defp maybe_group_and_aggregate(rows, nil, _aggregates), do: rows
  defp maybe_group_and_aggregate(rows, _group_by, nil), do: rows
  defp maybe_group_and_aggregate(rows, group_by, aggregates) do
    grouped = Enum.group_by(rows, fn row ->
      Enum.map(group_by, fn %{modality: mod, field: field} ->
        get_in(row, [to_string(mod), field])
      end)
    end)

    Enum.map(grouped, fn {group_key, group_rows} ->
      base = group_by
        |> Enum.zip(group_key)
        |> Enum.into(%{}, fn {%{modality: mod, field: field}, val} ->
          {"#{mod}.#{field}", val}
        end)

      Enum.reduce(aggregates, base, fn agg, acc ->
        case agg do
          :count_all ->
            Map.put(acc, "COUNT(*)", length(group_rows))

          {:aggregate_field, func, %{modality: mod, field: field}} ->
            values = Enum.map(group_rows, fn row ->
              get_in(row, [to_string(mod), field]) || 0
            end)

            result = case func do
              :count -> length(values)
              :sum -> Enum.sum(values)
              :avg ->
                if length(values) > 0, do: Enum.sum(values) / length(values), else: 0
              :min -> Enum.min(values, fn -> 0 end)
              :max -> Enum.max(values, fn -> 0 end)
            end

            label = "#{String.upcase(to_string(func))}(#{mod}.#{field})"
            Map.put(acc, label, result)
        end
      end)
    end)
  end

  defp maybe_order_by(rows, nil), do: rows
  defp maybe_order_by(rows, order_items) do
    Enum.sort_by(rows, fn row ->
      Enum.map(order_items, fn %{field: %{modality: mod, field: field}} ->
        get_in(row, [to_string(mod), field]) || get_in(row, ["#{mod}.#{field}"])
      end)
    end, fn a, b ->
      order_items
      |> Enum.zip(Enum.zip(a, b))
      |> Enum.reduce_while(:eq, fn {item, {va, vb}}, _acc ->
        cmp = compare_values(va, vb)
        direction = Map.get(item, :direction, :asc)
        effective = if direction == :desc, do: invert_cmp(cmp), else: cmp
        case effective do
          :eq -> {:cont, :eq}
          :lt -> {:halt, true}
          :gt -> {:halt, false}
        end
      end)
      |> case do
        :eq -> true
        bool -> bool
      end
    end)
  end

  defp compare_values(a, b) when is_number(a) and is_number(b) do
    cond do
      a < b -> :lt
      a > b -> :gt
      true -> :eq
    end
  end
  defp compare_values(a, b) when is_binary(a) and is_binary(b) do
    cond do
      a < b -> :lt
      a > b -> :gt
      true -> :eq
    end
  end
  defp compare_values(_a, _b), do: :eq

  defp invert_cmp(:lt), do: :gt
  defp invert_cmp(:gt), do: :lt
  defp invert_cmp(:eq), do: :eq

  defp maybe_project_columns(rows, nil), do: rows
  defp maybe_project_columns(rows, projections) do
    Enum.map(rows, fn row ->
      Enum.into(projections, %{}, fn %{modality: mod, field: field} ->
        value = get_in(row, [to_string(mod), field]) || get_in(row, ["#{mod}.#{field}"])
        {"#{mod}.#{field}", value}
      end)
    end)
  end

  # ---------------------------------------------------------------------------
  # AST extraction helpers
  # ---------------------------------------------------------------------------

  defp extract_modalities(query_ast), do: Map.get(query_ast, :modalities, [:all])
  defp extract_source(query_ast) do
    case Map.get(query_ast, :source, {:hexad, "default"}) do
      %{TAG: "Reflect"} -> :reflect
      :reflect -> :reflect
      "REFLECT" -> :reflect
      other -> other
    end
  end
  defp extract_where(query_ast), do: Map.get(query_ast, :where, nil)

  defp extract_proof(query_ast) do
    case Map.get(query_ast, :proof, nil) do
      nil -> nil
      proof when is_list(proof) -> proof
      proof when is_map(proof) -> [proof]  # backward compat: single proof → list
    end
  end

  defp extract_limit(query_ast), do: Map.get(query_ast, :limit, nil)
  defp extract_offset(query_ast), do: Map.get(query_ast, :offset, nil)
  defp extract_order_by(query_ast), do: Map.get(query_ast, :orderBy, nil)
  defp extract_group_by(query_ast), do: Map.get(query_ast, :groupBy, nil)
  defp extract_aggregates(query_ast), do: Map.get(query_ast, :aggregates, nil)
  defp extract_projections(query_ast), do: Map.get(query_ast, :projections, nil)
end
