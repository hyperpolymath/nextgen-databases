# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim.Transport do
  @moduledoc """
  Transport selection for VeriSimDB Rust core communication.

  Selects between HTTP (verisim-api) and NIF (in-process) transports based on
  the `VERISIM_TRANSPORT` environment variable:

      VERISIM_TRANSPORT=http   # Default: HTTP via VeriSim.RustClient
      VERISIM_TRANSPORT=nif    # Direct NIF calls via VeriSim.NifBridge
      VERISIM_TRANSPORT=auto   # NIF if loaded, HTTP fallback

  ## Usage

  Higher-level modules (EntityServer, DriftMonitor, QueryRouter) should call
  `VeriSim.Transport` instead of `VeriSim.RustClient` directly. The transport
  module delegates to the appropriate backend transparently.

  ## Architecture

      ┌──────────────────────┐
      │  VeriSim.Transport   │   ← Unified interface
      ├──────────┬───────────┤
      │ NifBridge│ RustClient│   ← Backend selection
      │ (in-proc)│ (HTTP)    │
      └──────────┴───────────┘
  """

  require Logger

  alias VeriSim.{NifBridge, RustClient}

  @doc """
  Returns the active transport mode: `:http`, `:nif`, or `:auto`.
  """
  def mode do
    case System.get_env("VERISIM_TRANSPORT", "http") do
      "nif" -> :nif
      "auto" -> :auto
      _ -> :http
    end
  end

  @doc """
  Returns true if the NIF bridge is loaded and operational.
  """
  def nif_available? do
    try do
      NifBridge.loaded?()
    rescue
      _ -> false
    end
  end

  @doc """
  Determine whether to use NIF for this call based on the transport mode.
  """
  def use_nif? do
    case mode() do
      :nif -> true
      :auto -> nif_available?()
      :http -> false
    end
  end

  # ---------------------------------------------------------------------------
  # Delegated Operations
  # ---------------------------------------------------------------------------

  @doc """
  Check health of the Rust core.
  """
  def health do
    if use_nif?() do
      {:ok, %{"status" => "healthy", "transport" => "nif"}}
    else
      RustClient.health()
    end
  end

  @doc """
  Create a new hexad entity.
  """
  def create_hexad(input) do
    if use_nif?() do
      json = Jason.encode!(input)
      case NifBridge.create_hexad(json) do
        result when is_binary(result) -> {:ok, Jason.decode!(result)}
        {:error, reason} -> {:error, reason}
      end
    else
      RustClient.create_hexad(input)
    end
  end

  @doc """
  Get a hexad by ID.
  """
  def get_hexad(entity_id) do
    if use_nif?() do
      case NifBridge.get_hexad(entity_id) do
        result when is_binary(result) -> {:ok, Jason.decode!(result)}
        {:error, reason} -> {:error, reason}
      end
    else
      RustClient.get_hexad(entity_id)
    end
  end

  @doc """
  Delete a hexad entity.
  """
  def delete_hexad(entity_id) do
    if use_nif?() do
      case NifBridge.delete_hexad(entity_id) do
        result when is_binary(result) -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      RustClient.delete_hexad(entity_id)
    end
  end

  @doc """
  Full-text search across the document modality.
  """
  def search_text(query, limit \\ 10) do
    if use_nif?() do
      case NifBridge.search_text(query, limit) do
        result when is_binary(result) -> {:ok, Jason.decode!(result)}
        {:error, reason} -> {:error, reason}
      end
    else
      RustClient.search_text(query, limit)
    end
  end

  @doc """
  Vector similarity search.
  """
  def search_vector(vector, k \\ 10) do
    if use_nif?() do
      embedding_json = Jason.encode!(vector)
      case NifBridge.search_vector(embedding_json, k) do
        result when is_binary(result) -> {:ok, Jason.decode!(result)}
        {:error, reason} -> {:error, reason}
      end
    else
      RustClient.search_vector(vector, k)
    end
  end

  @doc """
  Paginated listing of hexad entities.
  """
  def list_hexads(limit \\ 50, offset \\ 0) do
    if use_nif?() do
      case NifBridge.list_hexads(limit, offset) do
        result when is_binary(result) -> {:ok, Jason.decode!(result)}
        {:error, reason} -> {:error, reason}
      end
    else
      RustClient.list_hexads(limit, offset)
    end
  end

  @doc """
  Get drift scores for a specific entity.
  """
  def get_drift_score(entity_id) do
    if use_nif?() do
      case NifBridge.get_drift_score(entity_id) do
        result when is_binary(result) -> {:ok, Jason.decode!(result)}
        {:error, reason} -> {:error, reason}
      end
    else
      RustClient.get_drift_score(entity_id)
    end
  end

  @doc """
  Trigger normalisation for a drifted entity.
  """
  def trigger_normalise(entity_id) do
    if use_nif?() do
      case NifBridge.trigger_normalise(entity_id) do
        result when is_binary(result) -> {:ok, Jason.decode!(result)}
        {:error, reason} -> {:error, reason}
      end
    else
      RustClient.trigger_normalization(entity_id)
    end
  end
end
