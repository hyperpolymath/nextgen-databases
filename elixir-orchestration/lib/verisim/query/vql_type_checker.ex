# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim.Query.VQLTypeChecker do
  @moduledoc """
  Elixir-native VQL-DT type checker.

  Provides lightweight type checking for VQL queries with PROOF clauses when the
  ReScript subprocess (VQLBidir) is unavailable. This ensures that VQL-DT queries
  are always type-checked before execution — never silently downgraded to slipstream.

  ## Design

  The ReScript type checker (VQLBidir.res) is the canonical implementation with
  bidirectional type inference and full subtyping. This Elixir module implements a
  pragmatic subset of the same rules:

  1. **Modality validation** — queried modalities match proof requirements
  2. **Proof type validation** — proof types are known and well-formed
  3. **Multi-proof composition** — composition strategies are valid
  4. **Contract reference validation** — proof specs that need contracts have them
  5. **Proof obligation generation** — structured obligations with witness fields

  Falls back to the ReScript type checker when it's available (via VQLBridge.typecheck/2).

  ## Proof Types and Required Modalities

  | Proof Type   | Required Modalities       | Circuit Name          |
  |-------------|---------------------------|-----------------------|
  | EXISTENCE   | any                       | existence-proof-v1    |
  | INTEGRITY   | semantic                  | integrity-proof-v1    |
  | CONSISTENCY | 2+ modalities             | consistency-proof-v1  |
  | PROVENANCE  | provenance                | provenance-proof-v1   |
  | FRESHNESS   | temporal                  | freshness-proof-v1    |
  | ACCESS      | any                       | access-control-v1     |
  | CITATION    | document or semantic      | citation-proof-v1     |
  | CUSTOM      | varies (circuit-defined)  | (user-specified)      |
  | ZKP         | any                       | (privacy-aware)       |
  | PROVEN      | semantic                  | proven-cert-v1        |
  | SANCTIFY    | semantic                  | sanctify-v1           |
  """

  require Logger

  @known_proof_types ~w(
    existence integrity consistency provenance freshness access citation
    custom zkp proven sanctify
  )a

  @proof_required_modalities %{
    existence: [],
    integrity: [:semantic],
    consistency: [],
    provenance: [:provenance],
    freshness: [:temporal],
    access: [],
    citation: [:document, :semantic],
    custom: [],
    zkp: [],
    proven: [:semantic],
    sanctify: [:semantic]
  }

  @proof_witness_fields %{
    existence: ["hexad_id", "timestamp", "modality_count"],
    integrity: ["content_hash", "merkle_root", "schema_version"],
    consistency: ["modality_a", "modality_b", "drift_score", "threshold"],
    provenance: ["chain_hash", "chain_length", "origin", "actor_trail"],
    freshness: ["last_modified", "max_age_ms", "version_count"],
    access: ["principal_id", "resource_id", "permission_set"],
    citation: ["source_ids", "citation_chain", "reference_count"],
    custom: ["circuit_inputs"],
    zkp: ["claim", "blinding_nonce"],
    proven: ["certificate_hash", "proof_data"],
    sanctify: ["contract_hash", "security_level"]
  }

  @proof_circuits %{
    existence: "existence-proof-v1",
    integrity: "integrity-proof-v1",
    consistency: "consistency-proof-v1",
    provenance: "provenance-proof-v1",
    freshness: "freshness-proof-v1",
    access: "access-control-v1",
    citation: "citation-proof-v1",
    custom: nil,
    zkp: nil,
    proven: "proven-cert-v1",
    sanctify: "sanctify-v1"
  }

  @proof_time_estimates_ms %{
    existence: 50,
    integrity: 200,
    consistency: 250,
    provenance: 300,
    freshness: 100,
    access: 150,
    citation: 100,
    custom: 500,
    zkp: 400,
    proven: 200,
    sanctify: 200
  }

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Type-check a VQL-DT query AST.

  Validates proof types, modality compatibility, and composition rules.
  Returns structured proof obligations ready for the executor.

  ## Returns

  - `{:ok, type_info}` with:
    - `:proof_obligations` — list of structured obligation maps
    - `:composition_strategy` — how proofs compose (:conjunction, :independent, :sequential)
    - `:inferred_types` — modality type map (empty in native checker)
    - `:total_estimated_ms` — sum of per-proof time estimates
    - `:is_parallelizable` — whether proofs can run concurrently
  - `{:error, reason}` — type checking failed
  """
  def typecheck(query_ast) do
    modalities = extract_modalities(query_ast)
    proof_specs = extract_and_split_proofs(query_ast)

    with :ok <- validate_modalities(modalities),
         :ok <- validate_proof_specs(proof_specs),
         :ok <- validate_modality_compatibility(proof_specs, modalities),
         {:ok, obligations} <- generate_obligations(proof_specs),
         {:ok, composition} <- determine_composition(obligations) do
      total_ms = Enum.reduce(obligations, 0, & &1.estimated_time_ms + &2)

      {:ok, %{
        proof_obligations: obligations,
        composition_strategy: composition,
        inferred_types: %{},
        total_estimated_ms: total_ms,
        is_parallelizable: composition == :independent
      }}
    end
  end

  @doc """
  Parse a raw PROOF clause string into a list of individual proof spec maps.

  Splits on AND/OR connectors and extracts proof type + contract name from
  each spec. Handles the built-in parser's `%{raw: "..."}` format.

  ## Examples

      iex> VQLTypeChecker.parse_proof_specs(%{raw: "EXISTENCE(entity-001) AND PROVENANCE(entity-001)"})
      [
        %{proofType: "EXISTENCE", contractName: "entity-001", raw: "EXISTENCE(entity-001)"},
        %{proofType: "PROVENANCE", contractName: "entity-001", raw: "PROVENANCE(entity-001)"}
      ]

      iex> VQLTypeChecker.parse_proof_specs(%{raw: "INTEGRITY(my_contract)"})
      [%{proofType: "INTEGRITY", contractName: "my_contract", raw: "INTEGRITY(my_contract)"}]
  """
  def parse_proof_specs(nil), do: []
  def parse_proof_specs(specs) when is_list(specs) do
    Enum.flat_map(specs, &parse_proof_specs/1)
  end
  def parse_proof_specs(%{raw: raw}) when is_binary(raw) do
    # Split on AND/OR connectors (case-insensitive), preserving each proof spec
    raw
    |> String.split(~r/\s+AND\s+|\s+OR\s+/i)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(fn spec_str ->
      {proof_type, contract_name} = parse_single_proof_spec(spec_str)
      %{
        proofType: proof_type,
        contractName: contract_name,
        raw: spec_str
      }
    end)
  end
  def parse_proof_specs(%{proofType: _} = spec), do: [spec]
  def parse_proof_specs(%{TAG: _} = spec), do: [spec]
  def parse_proof_specs(_), do: []

  # ---------------------------------------------------------------------------
  # Private: Validation
  # ---------------------------------------------------------------------------

  defp validate_modalities([]), do: {:error, {:invalid_query, "No modalities specified"}}
  defp validate_modalities(_modalities), do: :ok

  defp validate_proof_specs([]) do
    {:error, {:missing_proof, "VQL-DT query requires at least one PROOF specification"}}
  end
  defp validate_proof_specs(specs) do
    Enum.reduce_while(specs, :ok, fn spec, _acc ->
      proof_type = normalize_proof_type(spec)
      cond do
        proof_type == :unknown ->
          raw = Map.get(spec, :raw, Map.get(spec, :proofType, inspect(spec)))
          {:halt, {:error, {:unknown_proof_type, "Unknown proof type: #{raw}"}}}

        needs_contract?(proof_type) and not has_contract?(spec) ->
          {:halt, {:error, {:missing_contract,
            "#{proof_type_name(proof_type)} proof requires a contract/entity reference"}}}

        true ->
          {:cont, :ok}
      end
    end)
  end

  defp validate_modality_compatibility(proof_specs, modalities) do
    # For each proof, check that required modalities are being queried
    # (or that :all is in the modality list)
    has_all = :all in modalities

    Enum.reduce_while(proof_specs, :ok, fn spec, _acc ->
      proof_type = normalize_proof_type(spec)
      required = Map.get(@proof_required_modalities, proof_type, [])

      if has_all or required == [] or Enum.any?(required, &(&1 in modalities)) do
        {:cont, :ok}
      else
        required_str = required |> Enum.map(&to_string/1) |> Enum.join(", ")
        {:halt, {:error, {:modality_mismatch,
          "#{proof_type_name(proof_type)} proof requires #{required_str} modality " <>
          "but query only selects #{inspect(modalities)}"}}}
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # Private: Obligation Generation
  # ---------------------------------------------------------------------------

  defp generate_obligations(proof_specs) do
    obligations = Enum.map(proof_specs, fn spec ->
      proof_type = normalize_proof_type(spec)
      contract = extract_contract(spec)

      %{
        type: proof_type,
        proofType: proof_type |> Atom.to_string() |> String.upcase(),
        contract: contract,
        contractName: contract,
        witness_fields: Map.get(@proof_witness_fields, proof_type, []),
        circuit: circuit_for(proof_type, spec),
        estimated_time_ms: Map.get(@proof_time_estimates_ms, proof_type, 200),
        required_modalities: Map.get(@proof_required_modalities, proof_type, [])
      }
    end)

    {:ok, obligations}
  end

  defp determine_composition([]), do: {:ok, :independent}
  defp determine_composition([_single]), do: {:ok, :independent}
  defp determine_composition(obligations) do
    types = Enum.map(obligations, & &1.type) |> MapSet.new()

    # Provenance + Citation must be sequential (citation validated first)
    if :provenance in types and :citation in types do
      {:ok, :sequential}
    else
      {:ok, :conjunction}
    end
  end

  # ---------------------------------------------------------------------------
  # Private: Proof spec parsing helpers
  # ---------------------------------------------------------------------------

  defp extract_and_split_proofs(query_ast) do
    proof = query_ast[:proof] || query_ast["proof"]
    parse_proof_specs(proof)
  end

  defp extract_modalities(query_ast) do
    query_ast[:modalities] || query_ast["modalities"] || [:all]
  end

  defp parse_single_proof_spec(spec_str) do
    # Handle "PROOF_TYPE(contract)" and "PROOF_TYPE contract" formats
    case Regex.run(~r/^([A-Z_]+)\(([^)]*)\)$/, String.trim(spec_str)) do
      [_, proof_type, contract] ->
        {proof_type, String.trim(contract)}
      _ ->
        # Try space-separated: "EXISTENCE entity-001"
        case String.split(String.trim(spec_str), ~r/\s+/, parts: 2) do
          [proof_type, contract] -> {proof_type, String.trim(contract)}
          [proof_type] -> {proof_type, nil}
          _ -> {spec_str, nil}
        end
    end
  end

  defp normalize_proof_type(%{proofType: type}), do: do_normalize(type)
  defp normalize_proof_type(%{TAG: tag}), do: do_normalize(tag)
  defp normalize_proof_type(%{type: type}) when is_atom(type), do: type
  defp normalize_proof_type(%{raw: raw}) when is_binary(raw) do
    raw
    |> String.split(~r/[\s(]/, parts: 2)
    |> List.first()
    |> do_normalize()
  end
  defp normalize_proof_type(_), do: :unknown

  defp do_normalize(str) when is_binary(str) do
    atom = str |> String.downcase() |> String.to_atom()
    if atom in @known_proof_types, do: atom, else: :unknown
  end
  defp do_normalize(atom) when is_atom(atom) do
    if atom in @known_proof_types, do: atom, else: :unknown
  end
  defp do_normalize(_), do: :unknown

  defp extract_contract(%{contractName: name}) when is_binary(name) and name != "", do: name
  defp extract_contract(%{contract: name}) when is_binary(name) and name != "", do: name
  defp extract_contract(%{raw: raw}) when is_binary(raw) do
    case Regex.run(~r/\(([^)]+)\)/, raw) do
      [_, name] -> String.trim(name)
      _ -> nil
    end
  end
  defp extract_contract(_), do: nil

  defp needs_contract?(type) when type in [:integrity, :citation, :custom, :sanctify], do: true
  defp needs_contract?(_), do: false

  defp has_contract?(spec) do
    contract = extract_contract(spec)
    is_binary(contract) and contract != ""
  end

  defp circuit_for(:custom, spec) do
    extract_contract(spec) || "custom-circuit"
  end
  defp circuit_for(type, _spec), do: Map.get(@proof_circuits, type)

  defp proof_type_name(type) do
    type |> Atom.to_string() |> String.upcase()
  end
end
