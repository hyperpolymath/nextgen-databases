# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim.Query.VQLProofCertificateTest do
  @moduledoc """
  Tests for VQL-DT proof certificate generation and verification.

  Verifies that:
  1. Certificates are generated with correct structure and SHA-256 hash
  2. Valid certificates pass verification
  3. Tampered certificates fail verification
  4. Batch generation and verification work correctly
  5. Edge cases (missing type, non-map args) are handled gracefully
  """

  use ExUnit.Case, async: true

  alias VeriSim.Query.VQLProofCertificate

  # ---------------------------------------------------------------------------
  # Fixtures
  # ---------------------------------------------------------------------------

  defp existence_obligation do
    %{
      type: :existence,
      proofType: "EXISTENCE",
      contract: "entity-001",
      contractName: "entity-001",
      witness_fields: ["hexad_id", "timestamp", "modality_count"],
      circuit: "existence-proof-v1",
      estimated_time_ms: 50,
      required_modalities: []
    }
  end

  defp existence_witness do
    %{
      "hexad_id" => "entity-001",
      "timestamp" => "2026-02-28T12:00:00Z",
      "modality_count" => 8
    }
  end

  defp provenance_obligation do
    %{
      type: :provenance,
      proofType: "PROVENANCE",
      contract: "entity-002",
      contractName: "entity-002",
      witness_fields: ["chain_hash", "chain_length", "origin", "actor_trail"],
      circuit: "provenance-proof-v1",
      estimated_time_ms: 300,
      required_modalities: [:provenance]
    }
  end

  defp provenance_witness do
    %{
      "chain_hash" => "abc123def456",
      "chain_length" => 5,
      "origin" => "import-pipeline",
      "actor_trail" => ["ingester", "normalizer", "validator"]
    }
  end

  # ---------------------------------------------------------------------------
  # Test: Certificate generation
  # ---------------------------------------------------------------------------

  describe "generate_certificate/2" do
    test "produces a certificate with all required fields" do
      {:ok, cert} = VQLProofCertificate.generate_certificate(existence_obligation(), existence_witness())

      assert cert.type == :existence
      assert cert.obligation == existence_obligation()
      assert cert.witness == existence_witness()
      assert %DateTime{} = cert.timestamp
      assert is_binary(cert.hash)
      assert byte_size(cert.hash) == 32  # SHA-256 = 32 bytes
    end

    test "rejects obligation without :type field" do
      bad_obligation = %{proofType: "EXISTENCE", contract: "x"}
      assert {:error, {:invalid_obligation, _}} = VQLProofCertificate.generate_certificate(bad_obligation, %{})
    end

    test "rejects non-map arguments" do
      assert {:error, {:invalid_arguments, _}} = VQLProofCertificate.generate_certificate("not a map", %{})
      assert {:error, {:invalid_arguments, _}} = VQLProofCertificate.generate_certificate(%{type: :existence}, "not a map")
    end
  end

  # ---------------------------------------------------------------------------
  # Test: Certificate verification
  # ---------------------------------------------------------------------------

  describe "verify_certificate/1" do
    test "valid certificate passes verification" do
      {:ok, cert} = VQLProofCertificate.generate_certificate(existence_obligation(), existence_witness())
      assert :ok = VQLProofCertificate.verify_certificate(cert)
    end

    test "tampered obligation causes hash mismatch" do
      {:ok, cert} = VQLProofCertificate.generate_certificate(existence_obligation(), existence_witness())

      tampered = %{cert | obligation: %{cert.obligation | type: :integrity}}
      assert {:error, :invalid_hash} = VQLProofCertificate.verify_certificate(tampered)
    end

    test "tampered witness causes hash mismatch" do
      {:ok, cert} = VQLProofCertificate.generate_certificate(existence_obligation(), existence_witness())

      tampered = %{cert | witness: %{"hexad_id" => "evil-entity"}}
      assert {:error, :invalid_hash} = VQLProofCertificate.verify_certificate(tampered)
    end

    test "malformed certificate returns error" do
      assert {:error, :malformed_certificate} = VQLProofCertificate.verify_certificate(%{})
      assert {:error, :malformed_certificate} = VQLProofCertificate.verify_certificate(nil)
      assert {:error, :malformed_certificate} = VQLProofCertificate.verify_certificate("not a cert")
    end
  end

  # ---------------------------------------------------------------------------
  # Test: Batch operations
  # ---------------------------------------------------------------------------

  describe "generate_batch/1 and verify_batch/1" do
    test "batch generation produces certificates for all pairs" do
      pairs = [
        {existence_obligation(), existence_witness()},
        {provenance_obligation(), provenance_witness()}
      ]

      {:ok, certs} = VQLProofCertificate.generate_batch(pairs)
      assert length(certs) == 2
      assert Enum.at(certs, 0).type == :existence
      assert Enum.at(certs, 1).type == :provenance

      # All certificates should verify
      assert :ok = VQLProofCertificate.verify_batch(certs)
    end

    test "batch verification fails with index on tampered certificate" do
      pairs = [
        {existence_obligation(), existence_witness()},
        {provenance_obligation(), provenance_witness()}
      ]

      {:ok, certs} = VQLProofCertificate.generate_batch(pairs)

      # Tamper with the second certificate
      tampered_second = %{Enum.at(certs, 1) | witness: %{"chain_hash" => "tampered"}}
      tampered_batch = List.replace_at(certs, 1, tampered_second)

      assert {:error, {:batch_failure, 1, :invalid_hash}} =
               VQLProofCertificate.verify_batch(tampered_batch)
    end
  end
end
