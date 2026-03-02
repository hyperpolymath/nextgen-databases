# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim.Query.VQLTypeCheckerTest do
  @moduledoc """
  Tests for the Elixir-native VQL-DT type checker.

  Verifies that the type checker:
  1. Validates proof types are known
  2. Checks modality compatibility (proof requirements vs queried modalities)
  3. Splits multi-proof raw strings correctly
  4. Generates structured obligations with witness fields and circuits
  5. Determines correct composition strategies
  6. Rejects malformed queries with specific error reasons
  """

  use ExUnit.Case, async: true

  alias VeriSim.Query.VQLTypeChecker

  # ===========================================================================
  # parse_proof_specs/1 — multi-proof splitting
  # ===========================================================================

  describe "parse_proof_specs/1" do
    test "splits AND-connected proofs" do
      specs = VQLTypeChecker.parse_proof_specs(%{raw: "EXISTENCE(entity-001) AND PROVENANCE(entity-001)"})

      assert length(specs) == 2
      assert Enum.at(specs, 0).proofType == "EXISTENCE"
      assert Enum.at(specs, 0).contractName == "entity-001"
      assert Enum.at(specs, 1).proofType == "PROVENANCE"
      assert Enum.at(specs, 1).contractName == "entity-001"
    end

    test "splits OR-connected proofs" do
      specs = VQLTypeChecker.parse_proof_specs(%{raw: "EXISTENCE(a) OR INTEGRITY(b)"})

      assert length(specs) == 2
      assert Enum.at(specs, 0).proofType == "EXISTENCE"
      assert Enum.at(specs, 1).proofType == "INTEGRITY"
    end

    test "handles single proof spec" do
      specs = VQLTypeChecker.parse_proof_specs(%{raw: "INTEGRITY(my_contract)"})

      assert length(specs) == 1
      assert Enum.at(specs, 0).proofType == "INTEGRITY"
      assert Enum.at(specs, 0).contractName == "my_contract"
    end

    test "handles proof without parentheses" do
      specs = VQLTypeChecker.parse_proof_specs(%{raw: "EXISTENCE entity-001"})

      assert length(specs) == 1
      assert Enum.at(specs, 0).proofType == "EXISTENCE"
      assert Enum.at(specs, 0).contractName == "entity-001"
    end

    test "handles three proofs" do
      specs = VQLTypeChecker.parse_proof_specs(
        %{raw: "EXISTENCE(a) AND PROVENANCE(b) AND INTEGRITY(c)"}
      )

      assert length(specs) == 3
      assert Enum.map(specs, & &1.proofType) == ["EXISTENCE", "PROVENANCE", "INTEGRITY"]
    end

    test "passes through structured specs unchanged" do
      input = %{proofType: "EXISTENCE", contractName: "entity-001"}
      specs = VQLTypeChecker.parse_proof_specs(input)

      assert length(specs) == 1
      assert Enum.at(specs, 0) == input
    end

    test "handles nil" do
      assert VQLTypeChecker.parse_proof_specs(nil) == []
    end

    test "handles list of specs" do
      input = [
        %{proofType: "EXISTENCE", contractName: "a"},
        %{proofType: "INTEGRITY", contractName: "b"}
      ]
      specs = VQLTypeChecker.parse_proof_specs(input)

      assert length(specs) == 2
    end

    test "handles list containing raw specs" do
      input = [%{raw: "EXISTENCE(a) AND PROVENANCE(b)"}]
      specs = VQLTypeChecker.parse_proof_specs(input)

      assert length(specs) == 2
    end
  end

  # ===========================================================================
  # typecheck/1 — full type checking
  # ===========================================================================

  describe "typecheck/1 — valid queries" do
    test "accepts simple EXISTENCE proof" do
      ast = %{
        modalities: [:graph],
        proof: [%{proofType: "EXISTENCE", contractName: "entity-001"}]
      }

      assert {:ok, info} = VQLTypeChecker.typecheck(ast)
      assert length(info.proof_obligations) == 1
      assert Enum.at(info.proof_obligations, 0).type == :existence
      assert info.composition_strategy == :independent
    end

    test "accepts multi-proof conjunction" do
      ast = %{
        modalities: [:graph, :provenance],
        proof: [
          %{proofType: "EXISTENCE", contractName: "entity-001"},
          %{proofType: "PROVENANCE", contractName: "entity-001"}
        ]
      }

      assert {:ok, info} = VQLTypeChecker.typecheck(ast)
      assert length(info.proof_obligations) == 2
      assert info.composition_strategy == :conjunction
    end

    test "accepts PROVENANCE proof with provenance modality" do
      ast = %{
        modalities: [:provenance],
        proof: [%{proofType: "PROVENANCE", contractName: "entity-001"}]
      }

      assert {:ok, info} = VQLTypeChecker.typecheck(ast)
      assert Enum.at(info.proof_obligations, 0).type == :provenance
    end

    test "accepts any proof with :all modalities" do
      ast = %{
        modalities: [:all],
        proof: [%{proofType: "INTEGRITY", contractName: "contract-001"}]
      }

      assert {:ok, info} = VQLTypeChecker.typecheck(ast)
      assert Enum.at(info.proof_obligations, 0).type == :integrity
    end

    test "accepts CONSISTENCY proof" do
      ast = %{
        modalities: [:graph, :vector],
        proof: [%{proofType: "CONSISTENCY", contractName: "entity-001"}]
      }

      assert {:ok, info} = VQLTypeChecker.typecheck(ast)
      assert Enum.at(info.proof_obligations, 0).type == :consistency
    end

    test "accepts FRESHNESS proof with temporal modality" do
      ast = %{
        modalities: [:temporal],
        proof: [%{proofType: "FRESHNESS", contractName: "entity-001"}]
      }

      assert {:ok, info} = VQLTypeChecker.typecheck(ast)
      assert Enum.at(info.proof_obligations, 0).type == :freshness
    end

    test "accepts raw proof spec string" do
      ast = %{
        modalities: [:graph],
        proof: %{raw: "EXISTENCE(entity-001)"}
      }

      assert {:ok, info} = VQLTypeChecker.typecheck(ast)
      assert length(info.proof_obligations) == 1
    end

    test "accepts raw multi-proof string" do
      ast = %{
        modalities: [:graph, :provenance],
        proof: %{raw: "EXISTENCE(entity-001) AND PROVENANCE(entity-001)"}
      }

      assert {:ok, info} = VQLTypeChecker.typecheck(ast)
      assert length(info.proof_obligations) == 2
    end
  end

  describe "typecheck/1 — invalid queries" do
    test "rejects unknown proof type" do
      ast = %{
        modalities: [:graph],
        proof: [%{proofType: "BOGUS", contractName: "entity-001"}]
      }

      assert {:error, {:unknown_proof_type, msg}} = VQLTypeChecker.typecheck(ast)
      assert msg =~ "BOGUS"
    end

    test "rejects INTEGRITY proof without contract" do
      ast = %{
        modalities: [:semantic],
        proof: [%{proofType: "INTEGRITY"}]
      }

      assert {:error, {:missing_contract, _}} = VQLTypeChecker.typecheck(ast)
    end

    test "rejects CITATION proof without contract" do
      ast = %{
        modalities: [:document],
        proof: [%{proofType: "CITATION"}]
      }

      assert {:error, {:missing_contract, _}} = VQLTypeChecker.typecheck(ast)
    end

    test "rejects INTEGRITY proof with wrong modality" do
      ast = %{
        modalities: [:graph],
        proof: [%{proofType: "INTEGRITY", contractName: "contract-001"}]
      }

      assert {:error, {:modality_mismatch, msg}} = VQLTypeChecker.typecheck(ast)
      assert msg =~ "semantic"
    end

    test "rejects PROVENANCE proof without provenance modality" do
      ast = %{
        modalities: [:graph],
        proof: [%{proofType: "PROVENANCE", contractName: "entity-001"}]
      }

      assert {:error, {:modality_mismatch, msg}} = VQLTypeChecker.typecheck(ast)
      assert msg =~ "provenance"
    end

    test "rejects FRESHNESS proof without temporal modality" do
      ast = %{
        modalities: [:graph],
        proof: [%{proofType: "FRESHNESS", contractName: "entity-001"}]
      }

      assert {:error, {:modality_mismatch, msg}} = VQLTypeChecker.typecheck(ast)
      assert msg =~ "temporal"
    end

    test "rejects query with no proof specs" do
      ast = %{
        modalities: [:graph],
        proof: []
      }

      assert {:error, {:missing_proof, _}} = VQLTypeChecker.typecheck(ast)
    end

    test "rejects query with nil proof" do
      ast = %{
        modalities: [:graph],
        proof: nil
      }

      assert {:error, {:missing_proof, _}} = VQLTypeChecker.typecheck(ast)
    end
  end

  # ===========================================================================
  # Obligation structure
  # ===========================================================================

  describe "obligation structure" do
    test "obligations include witness fields" do
      ast = %{
        modalities: [:graph],
        proof: [%{proofType: "EXISTENCE", contractName: "entity-001"}]
      }

      {:ok, info} = VQLTypeChecker.typecheck(ast)
      obligation = Enum.at(info.proof_obligations, 0)

      assert is_list(obligation.witness_fields)
      assert "hexad_id" in obligation.witness_fields
      assert "timestamp" in obligation.witness_fields
    end

    test "obligations include circuit names" do
      ast = %{
        modalities: [:graph],
        proof: [%{proofType: "EXISTENCE", contractName: "entity-001"}]
      }

      {:ok, info} = VQLTypeChecker.typecheck(ast)
      obligation = Enum.at(info.proof_obligations, 0)

      assert obligation.circuit == "existence-proof-v1"
    end

    test "obligations include time estimates" do
      ast = %{
        modalities: [:graph, :provenance],
        proof: [
          %{proofType: "EXISTENCE", contractName: "entity-001"},
          %{proofType: "PROVENANCE", contractName: "entity-001"}
        ]
      }

      {:ok, info} = VQLTypeChecker.typecheck(ast)

      assert info.total_estimated_ms > 0
      assert info.total_estimated_ms ==
        Enum.at(info.proof_obligations, 0).estimated_time_ms +
        Enum.at(info.proof_obligations, 1).estimated_time_ms
    end

    test "provenance circuit is provenance-proof-v1" do
      ast = %{
        modalities: [:provenance],
        proof: [%{proofType: "PROVENANCE", contractName: "entity-001"}]
      }

      {:ok, info} = VQLTypeChecker.typecheck(ast)
      assert Enum.at(info.proof_obligations, 0).circuit == "provenance-proof-v1"
    end

    test "integrity circuit is integrity-proof-v1" do
      ast = %{
        modalities: [:semantic],
        proof: [%{proofType: "INTEGRITY", contractName: "contract-001"}]
      }

      {:ok, info} = VQLTypeChecker.typecheck(ast)
      assert Enum.at(info.proof_obligations, 0).circuit == "integrity-proof-v1"
    end
  end

  # ===========================================================================
  # Composition strategy
  # ===========================================================================

  describe "composition strategy" do
    test "single proof is independent" do
      ast = %{
        modalities: [:graph],
        proof: [%{proofType: "EXISTENCE", contractName: "entity-001"}]
      }

      {:ok, info} = VQLTypeChecker.typecheck(ast)
      assert info.composition_strategy == :independent
      assert info.is_parallelizable == true
    end

    test "provenance + citation is sequential" do
      ast = %{
        modalities: [:all],
        proof: [
          %{proofType: "PROVENANCE", contractName: "entity-001"},
          %{proofType: "CITATION", contractName: "ref-001"}
        ]
      }

      {:ok, info} = VQLTypeChecker.typecheck(ast)
      assert info.composition_strategy == :sequential
      assert info.is_parallelizable == false
    end

    test "existence + access is conjunction (parallelizable)" do
      ast = %{
        modalities: [:graph],
        proof: [
          %{proofType: "EXISTENCE", contractName: "entity-001"},
          %{proofType: "ACCESS", contractName: "entity-001"}
        ]
      }

      {:ok, info} = VQLTypeChecker.typecheck(ast)
      assert info.composition_strategy == :conjunction
    end
  end

  # ===========================================================================
  # All 11 proof types
  # ===========================================================================

  describe "all proof types" do
    @tag timeout: :infinity

    test "all known proof types are accepted with correct modalities" do
      test_cases = [
        {:existence, [:graph], "entity-001"},
        {:integrity, [:semantic], "contract-001"},
        {:consistency, [:graph, :vector], "entity-001"},
        {:provenance, [:provenance], "entity-001"},
        {:freshness, [:temporal], "entity-001"},
        {:access, [:graph], "entity-001"},
        {:citation, [:document], "ref-001"},
        {:custom, [:graph], "my-circuit"},
        {:zkp, [:graph], "claim-001"},
        {:proven, [:semantic], "cert-001"},
        {:sanctify, [:semantic], "contract-001"}
      ]

      for {type, modalities, contract} <- test_cases do
        proof_type_str = type |> Atom.to_string() |> String.upcase()
        ast = %{
          modalities: modalities,
          proof: [%{proofType: proof_type_str, contractName: contract}]
        }

        result = VQLTypeChecker.typecheck(ast)
        assert {:ok, info} = result,
          "#{proof_type_str} should be accepted, got: #{inspect(result)}"
        assert Enum.at(info.proof_obligations, 0).type == type
      end
    end
  end
end
