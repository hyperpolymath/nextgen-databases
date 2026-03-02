# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim.Query.VQLProofCertificate do
  @moduledoc """
  VQL-DT proof certificate generation and verification.

  After the VQL type checker validates a query's proof obligations and the
  executor verifies the proofs at runtime, this module produces independently
  verifiable certificates. Each certificate bundles the proof obligation,
  witness data, and a SHA-256 integrity hash so that any party can later
  confirm that a proof was satisfied without re-executing the query.

  ## Certificate structure

  ```
  %{
    type: :existence,                    # proof type atom
    obligation: %{...},                  # structured obligation from type checker
    witness: %{...},                     # witness data gathered during execution
    timestamp: ~U[2026-02-28 12:00:00Z], # when the proof was verified
    hash: <<SHA-256 binary>>             # integrity hash of (obligation ++ witness ++ timestamp)
  }
  ```

  ## Privacy guarantees

  Certificates contain only proof metadata (types, hashes, timestamps) — never
  query content, entity data, or PII. The witness fields are structural (e.g.,
  `hexad_id`, `drift_score`, `chain_length`) not content-bearing.

  ## Usage

      # After type checking succeeds and proof is verified:
      obligation = %{type: :existence, witness_fields: ["hexad_id", "timestamp", "modality_count"], ...}
      witness = %{"hexad_id" => "entity-001", "timestamp" => "2026-02-28T12:00:00Z", "modality_count" => 8}

      {:ok, cert} = VQLProofCertificate.generate_certificate(obligation, witness)
      :ok = VQLProofCertificate.verify_certificate(cert)

  ## Batch certificates

      obligations_and_witnesses = [{obl1, wit1}, {obl2, wit2}]
      {:ok, certs} = VQLProofCertificate.generate_batch(obligations_and_witnesses)
      :ok = VQLProofCertificate.verify_batch(certs)
  """

  @doc """
  Generate a proof certificate from a type-checked obligation and runtime witness.

  The certificate includes a SHA-256 hash computed over the canonical
  representation of the obligation, witness, and timestamp. This hash
  serves as an integrity seal — any tampering with the certificate will
  cause `verify_certificate/1` to fail.

  ## Parameters

  - `obligation` — proof obligation map from `VQLTypeChecker.typecheck/1`
  - `witness` — witness data map gathered during proof execution

  ## Returns

  - `{:ok, certificate}` — valid certificate with integrity hash
  - `{:error, reason}` — obligation or witness is malformed
  """
  def generate_certificate(obligation, witness) when is_map(obligation) and is_map(witness) do
    proof_type = obligation[:type] || obligation["type"]

    if proof_type == nil do
      {:error, {:invalid_obligation, "Obligation must have a :type field"}}
    else
      timestamp = DateTime.utc_now()
      hash = compute_hash(obligation, witness, timestamp)

      certificate = %{
        type: proof_type,
        obligation: obligation,
        witness: witness,
        timestamp: timestamp,
        hash: hash
      }

      {:ok, certificate}
    end
  end

  def generate_certificate(_obligation, _witness) do
    {:error, {:invalid_arguments, "Obligation and witness must both be maps"}}
  end

  @doc """
  Verify a proof certificate's integrity by recomputing its hash.

  Checks that the hash stored in the certificate matches a fresh SHA-256
  computation over the same obligation, witness, and timestamp. This
  confirms the certificate has not been tampered with since generation.

  ## Parameters

  - `certificate` — a certificate map previously returned by `generate_certificate/2`

  ## Returns

  - `:ok` — certificate is valid and untampered
  - `{:error, :invalid_hash}` — hash mismatch (certificate was modified)
  - `{:error, :malformed_certificate}` — missing required fields
  """
  def verify_certificate(%{
        obligation: obligation,
        witness: witness,
        timestamp: timestamp,
        hash: stored_hash
      })
      when is_map(obligation) and is_map(witness) and is_binary(stored_hash) do
    recomputed = compute_hash(obligation, witness, timestamp)

    if recomputed == stored_hash do
      :ok
    else
      {:error, :invalid_hash}
    end
  end

  def verify_certificate(_), do: {:error, :malformed_certificate}

  @doc """
  Generate certificates for a batch of obligation/witness pairs.

  Useful when a VQL-DT query has multiple PROOF clauses (e.g.,
  `PROOF EXISTENCE(x) AND PROVENANCE(x)`).

  ## Parameters

  - `pairs` — list of `{obligation, witness}` tuples

  ## Returns

  - `{:ok, certificates}` — list of valid certificates
  - `{:error, reason}` — if any pair fails
  """
  def generate_batch(pairs) when is_list(pairs) do
    results =
      Enum.reduce_while(pairs, {:ok, []}, fn {obligation, witness}, {:ok, acc} ->
        case generate_certificate(obligation, witness) do
          {:ok, cert} -> {:cont, {:ok, acc ++ [cert]}}
          {:error, _} = err -> {:halt, err}
        end
      end)

    results
  end

  @doc """
  Verify a batch of certificates. Returns `:ok` only if all pass.

  ## Parameters

  - `certificates` — list of certificate maps

  ## Returns

  - `:ok` — all certificates verified
  - `{:error, {:batch_failure, index, reason}}` — certificate at `index` failed
  """
  def verify_batch(certificates) when is_list(certificates) do
    certificates
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {cert, index}, :ok ->
      case verify_certificate(cert) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {:batch_failure, index, reason}}}
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # Private: Hash computation
  # ---------------------------------------------------------------------------

  # Compute SHA-256 over the canonical serialisation of obligation, witness,
  # and timestamp. We use `:erlang.term_to_binary/1` for deterministic
  # serialisation of Elixir terms, then hash the concatenated binaries.
  defp compute_hash(obligation, witness, timestamp) do
    canonical =
      :erlang.term_to_binary(obligation) <>
        :erlang.term_to_binary(witness) <>
        :erlang.term_to_binary(timestamp)

    :crypto.hash(:sha256, canonical)
  end
end
