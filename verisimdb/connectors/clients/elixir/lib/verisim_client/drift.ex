# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

defmodule VeriSimClient.Drift do
  @moduledoc """
  Drift detection and normalization operations for VeriSimDB.

  VeriSimDB continuously monitors how far each hexad's modality data has
  diverged from its normalised baseline. When drift exceeds a configurable
  threshold the entity is flagged for re-normalisation. This module exposes
  drift score retrieval, system-wide status, and manual normalization triggers.

  ## Examples

      {:ok, client} = VeriSimClient.new("http://localhost:8080")

      {:ok, score} = VeriSimClient.Drift.score(client, "entity-uuid")
      IO.puts("Overall drift: \#{score["overall_score"]}")

      {:ok, status} = VeriSimClient.Drift.status(client)
  """

  alias VeriSimClient.Types

  @doc """
  Retrieve the drift score for a single hexad entity.

  The score aggregates per-modality drift metrics into an overall value
  (0.0 = perfectly normalised, higher = more drift).

  ## Parameters

    * `client` — A `VeriSimClient.t()` connection.
    * `id`     — The hexad entity identifier.
  """
  @spec score(VeriSimClient.t(), String.t()) ::
          {:ok, Types.drift_score()} | {:error, term()}
  def score(%VeriSimClient{} = client, id) when is_binary(id) do
    VeriSimClient.do_get(client, "/api/v1/drift/#{id}")
  end

  @doc """
  Retrieve system-wide drift status.

  Returns a map summarising total entities monitored, number exceeding drift
  threshold, average drift, and last sweep timestamp.

  ## Parameters

    * `client` — A `VeriSimClient.t()` connection.
  """
  @spec status(VeriSimClient.t()) :: {:ok, map()} | {:error, term()}
  def status(%VeriSimClient{} = client) do
    VeriSimClient.do_get(client, "/api/v1/drift/status")
  end

  @doc """
  Trigger re-normalisation for a specific hexad entity.

  This enqueues the entity for the normaliser pipeline, which will recompute
  cross-modality consistency and update the baseline.

  ## Parameters

    * `client` — A `VeriSimClient.t()` connection.
    * `id`     — The hexad entity identifier.
  """
  @spec normalize(VeriSimClient.t(), String.t()) :: :ok | {:error, term()}
  def normalize(%VeriSimClient{} = client, id) when is_binary(id) do
    case VeriSimClient.do_post(client, "/api/v1/drift/#{id}/normalize", %{}) do
      {:ok, _body} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Retrieve the normaliser pipeline status.

  Returns a map with queue depth, active workers, throughput metrics, and last
  error (if any).

  ## Parameters

    * `client` — A `VeriSimClient.t()` connection.
  """
  @spec normalizer_status(VeriSimClient.t()) :: {:ok, map()} | {:error, term()}
  def normalizer_status(%VeriSimClient{} = client) do
    VeriSimClient.do_get(client, "/api/v1/drift/normalizer/status")
  end
end
