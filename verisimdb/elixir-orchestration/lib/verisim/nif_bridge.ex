# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim.NifBridge do
  @moduledoc """
  NIF bridge to the Rust core via Rustler.

  Provides direct in-process calls to VeriSimDB's Rust engine, bypassing HTTP
  for same-node deployments. When the NIF is loaded, operations execute ~10-100x
  faster than the HTTP transport.

  ## Loading

  The NIF shared library is loaded from `priv/native/libverisim_nif.so` (Linux)
  or `priv/native/libverisim_nif.dylib` (macOS). If the library is not present
  (e.g., in a pure-Elixir development setup), all functions return
  `{:error, :nif_not_loaded}`.

  ## Transport Selection

  This module is not called directly. Instead, `VeriSim.Transport` selects the
  transport based on `VERISIM_TRANSPORT`:

      VERISIM_TRANSPORT=http   # Default: HTTP via VeriSim.RustClient
      VERISIM_TRANSPORT=nif    # Direct NIF calls (this module)
      VERISIM_TRANSPORT=auto   # NIF if loaded, HTTP fallback

  ## Functions

  All functions accept and return JSON strings for compatibility with the HTTP
  transport (same serialisation format).
  """

  @on_load :load_nif

  @doc false
  def load_nif do
    nif_path =
      :verisim
      |> :code.priv_dir()
      |> Path.join("native/libverisim_nif")

    case :erlang.load_nif(String.to_charlist(nif_path), 0) do
      :ok -> :ok
      {:error, {:load_failed, _}} -> :ok  # NIF not available — stubs will be used
      {:error, {:reload, _}} -> :ok        # Already loaded
      {:error, reason} ->
        require Logger
        Logger.debug("VeriSim.NifBridge: NIF not loaded (#{inspect(reason)})")
        :ok
    end
  end

  @doc """
  Create a new hexad entity from a JSON string.

  Returns `{:ok, json}` on success, `{:error, reason}` on failure.
  """
  def create_hexad(_json_input), do: {:error, :nif_not_loaded}

  @doc """
  Retrieve a hexad by ID.

  Returns the full hexad JSON with all 8 octad modalities.
  """
  def get_hexad(_hexad_id), do: {:error, :nif_not_loaded}

  @doc """
  Delete a hexad entity by ID.
  """
  def delete_hexad(_hexad_id), do: {:error, :nif_not_loaded}

  @doc """
  Full-text search across the document modality.
  """
  def search_text(_query, _limit), do: {:error, :nif_not_loaded}

  @doc """
  Vector similarity search.

  Accepts a JSON-encoded embedding vector and a k parameter.
  """
  def search_vector(_embedding_json, _k), do: {:error, :nif_not_loaded}

  @doc """
  Paginated listing of hexad entities.
  """
  def list_hexads(_limit, _offset), do: {:error, :nif_not_loaded}

  @doc """
  Get drift detection scores for a specific entity.

  Returns drift scores across all 8 octad modalities.
  """
  def get_drift_score(_hexad_id), do: {:error, :nif_not_loaded}

  @doc """
  Trigger normalisation (self-repair) for a drifted entity.
  """
  def trigger_normalise(_hexad_id), do: {:error, :nif_not_loaded}

  @doc """
  Check whether the NIF bridge is loaded and operational.
  """
  def loaded? do
    case get_hexad("__health_check__") do
      {:error, :nif_not_loaded} -> false
      _ -> true
    end
  end
end
