# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim.Query.VQLPropertyTest do
  @moduledoc """
  Property-based tests for the VQL type checker using StreamData.

  Generates random valid proof specifications and verifies that the type
  checker handles them correctly — no crashes, proper error messages for
  invalid inputs, and structural invariants on output.
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias VeriSim.Query.VQLTypeChecker

  # ---------------------------------------------------------------------------
  # Generators
  # ---------------------------------------------------------------------------

  defp valid_proof_type do
    member_of(~w(existence integrity consistency provenance freshness access citation custom zkp proven sanctify))
  end

  defp valid_modality do
    member_of(~w(graph vector tensor semantic document temporal provenance spatial)a)
  end

  defp valid_contract_name do
    string(:alphanumeric, min_length: 3, max_length: 20)
    |> map(fn s -> "entity-#{s}" end)
  end

  defp proof_spec_raw do
    gen all proof_type <- valid_proof_type(),
            contract <- valid_contract_name() do
      %{raw: "#{String.upcase(proof_type)}(#{contract})"}
    end
  end

  defp valid_query_ast do
    gen all modalities <- list_of(valid_modality(), min_length: 1, max_length: 4),
            proof_specs <- list_of(proof_spec_raw(), min_length: 1, max_length: 3) do
      %{
        modalities: Enum.uniq(modalities),
        proof: proof_specs
      }
    end
  end

  # ---------------------------------------------------------------------------
  # Properties
  # ---------------------------------------------------------------------------

  property "type checker never crashes on valid proof specs" do
    check all query_ast <- valid_query_ast() do
      result = VQLTypeChecker.typecheck(query_ast)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  property "type checker output has required fields when successful" do
    check all query_ast <- valid_query_ast() do
      case VQLTypeChecker.typecheck(query_ast) do
        {:ok, info} ->
          assert is_list(info.proof_obligations)
          assert info.composition_strategy in [:independent, :conjunction, :sequential]
          assert is_map(info.inferred_types)
          assert is_number(info.total_estimated_ms)
          assert is_boolean(info.is_parallelizable)

        {:error, _} ->
          # Modality mismatch or other valid rejection — that's fine
          :ok
      end
    end
  end

  property "parse_proof_specs round-trips without data loss" do
    check all proof_type <- valid_proof_type(),
              contract <- valid_contract_name() do
      raw = "#{String.upcase(proof_type)}(#{contract})"
      specs = VQLTypeChecker.parse_proof_specs(%{raw: raw})

      assert length(specs) == 1
      [spec] = specs
      assert spec.proofType == String.upcase(proof_type)
      assert spec.contractName == contract
    end
  end

  property "multi-proof specs split correctly on AND/OR" do
    check all types <- list_of(valid_proof_type(), min_length: 2, max_length: 4),
              contracts <- list_of(valid_contract_name(), length: length(types)) do
      parts = Enum.zip(types, contracts) |> Enum.map(fn {t, c} -> "#{String.upcase(t)}(#{c})" end)
      raw = Enum.join(parts, " AND ")

      specs = VQLTypeChecker.parse_proof_specs(%{raw: raw})
      assert length(specs) == length(types)
    end
  end

  property "unknown proof types always rejected" do
    # Prefix with "XBOGUS" to guarantee the generated string never collides
    # with a known proof type (existence, integrity, consistency, etc.)
    check all suffix <- string(:alphanumeric, min_length: 3, max_length: 10) do
      bad_type = "XBOGUS#{suffix}"

      query_ast = %{
        modalities: [:all],
        proof: [%{raw: "#{bad_type}(test)"}]
      }

      assert {:error, {:unknown_proof_type, _}} = VQLTypeChecker.typecheck(query_ast)
    end
  end
end
