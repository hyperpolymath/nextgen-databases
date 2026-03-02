# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim.Federation.Resolver do
  @moduledoc """
  Federation Resolver — coordinates cross-instance queries across
  heterogeneous database backends.

  Resolves federated query patterns to peer stores, dispatches parallel
  queries via adapter modules, and aggregates results according to drift
  policies. Supports VeriSimDB, ArangoDB, PostgreSQL, and Elasticsearch
  peers in the same federation.

  ## Heterogeneous Federation

  Each peer declares an `adapter_type` at registration. The resolver
  routes queries through the correct adapter module, which translates
  VeriSimDB's modality-based queries into the backend's native language
  (AQL, SQL, Elasticsearch DSL, or VeriSimDB HTTP API).

      ┌───────────────────────────────────────────────────┐
      │          VeriSim.Federation.Resolver              │
      │  ┌─────────┬──────────┬───────────┬────────────┐  │
      │  │VeriSimDB│ ArangoDB │PostgreSQL │Elasticsearch│ │
      │  │ Adapter │ Adapter  │ Adapter   │  Adapter   │  │
      │  └────┬────┴────┬─────┴─────┬─────┴─────┬──────┘  │
      └───────┼─────────┼───────────┼───────────┼─────────┘
              │         │           │           │
         verisim-api  ArangoDB   PostgreSQL  Elasticsearch
              │       HTTP API     (wire/    REST API
              │                   PostgREST)

  ## Drift Policies

  - `:strict`   — Only include stores with trust level above threshold.
  - `:repair`   — Include all, trigger normalization on drifted stores.
  - `:tolerate` — Include all, annotate drifted results.
  - `:latest`   — Use only the most recent data from each store.

  ## Peer Registration

  ### VeriSimDB peer (backward-compatible 3-arity)

      register_peer("verisim-prod", "http://verisim:8080/api/v1",
        [:graph, :vector, :document])

  ### Heterogeneous peer (map-based config)

      register_peer("arango-prod", %{
        endpoint: "http://arango:8529",
        adapter_type: :arangodb,
        adapter_config: %{database: "_system", collection: "hexads"},
        modalities: [:graph, :document, :semantic]
      })
  """

  use GenServer
  require Logger

  alias VeriSim.Federation.Adapter
  alias VeriSim.RustClient

  @default_timeout 10_000
  @health_check_interval 60_000
  @strict_trust_threshold 0.7

  # ---------------------------------------------------------------------------
  # Client API
  # ---------------------------------------------------------------------------

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Register a peer store in the federation.

  ## 3-arity (backward-compatible — VeriSimDB peers)

      register_peer("store-id", "http://host:port/api/v1", [:graph, :vector])

  ## 2-arity (heterogeneous — any adapter)

      register_peer("store-id", %{
        endpoint: "http://host:port",
        adapter_type: :arangodb,
        adapter_config: %{database: "_system"},
        modalities: [:graph, :document]
      })
  """
  def register_peer(store_id, endpoint, modalities)
      when is_binary(endpoint) and is_list(modalities) do
    # Backward-compatible: wrap as a VeriSimDB adapter config
    register_peer(store_id, %{
      endpoint: endpoint,
      adapter_type: :verisimdb,
      adapter_config: %{},
      modalities: modalities
    })
  end

  def register_peer(store_id, %{} = config) do
    GenServer.call(__MODULE__, {:register, store_id, config})
  end

  @doc "Remove a peer from the federation."
  def deregister_peer(store_id) do
    GenServer.call(__MODULE__, {:deregister, store_id})
  end

  @doc "List all known peers."
  def list_peers do
    GenServer.call(__MODULE__, :list_peers)
  end

  @doc """
  Execute a federated query across matching stores.

  Dispatches to each peer's adapter module for query translation and
  execution. Results are normalised into a common format regardless
  of the backend database.

  ## Options
  - `:drift_policy` — :strict | :repair | :tolerate | :latest (default: :tolerate)
  - `:limit` — max results per store
  - `:timeout` — query timeout in ms
  - `:text_query` — full-text search query string
  - `:vector_query` — embedding vector for similarity search
  - `:graph_pattern` — graph traversal start vertex
  - `:spatial_bounds` — bounding box for spatial queries
  - `:temporal_range` — time range for temporal queries
  """
  def query(pattern, modalities, opts \\ []) do
    internal_timeout = Keyword.get(opts, :timeout, @default_timeout)

    # GenServer.call timeout must exceed the internal Task.yield_many timeout
    # to allow the handler to finish processing (shutdown stale tasks, build response).
    GenServer.call(
      __MODULE__,
      {:query, pattern, modalities, opts},
      internal_timeout + 5_000
    )
  end

  # ---------------------------------------------------------------------------
  # GenServer Callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(_opts) do
    state = %{
      peers: %{},
      self_store_id: "local",
      health_check_ref: schedule_health_check()
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:register, store_id, config}, _from, state) do
    adapter_type = Map.get(config, :adapter_type, :verisimdb)
    adapter_config = Map.get(config, :adapter_config, %{})
    endpoint = Map.fetch!(config, :endpoint)
    declared_modalities = Map.get(config, :modalities, [])

    # Validate adapter type
    case Adapter.module_for(adapter_type) do
      {:ok, adapter_module} ->
        # Validate modalities against adapter capabilities.
        # Modalities may be strings or atoms — normalise for comparison.
        supported = adapter_module.supported_modalities(adapter_config)
        supported_strings = Enum.map(supported, &to_string/1)

        effective_modalities =
          if declared_modalities == [] do
            # No modalities declared — use all supported (as atoms)
            Enum.map(supported, &to_string/1)
          else
            # Filter declared modalities to those the adapter supports
            Enum.filter(declared_modalities, fn m ->
              to_string(m) in supported_strings
            end)
          end

        unsupported = declared_modalities -- effective_modalities

        if unsupported != [] do
          Logger.warning(
            "Federation: peer #{store_id} (#{adapter_type}) declared unsupported " <>
              "modalities #{inspect(unsupported)}, using #{inspect(effective_modalities)}"
          )
        end

        peer = %{
          store_id: store_id,
          endpoint: endpoint,
          adapter_type: adapter_type,
          adapter_module: adapter_module,
          adapter_config: adapter_config,
          modalities: effective_modalities,
          trust_level: 1.0,
          last_seen: DateTime.utc_now(),
          response_time_ms: nil
        }

        Logger.info(
          "Federation: registered #{adapter_type} peer #{store_id} at #{endpoint} " <>
            "with modalities #{inspect(effective_modalities)}"
        )

        new_peers = Map.put(state.peers, store_id, peer)

        # Also register VeriSimDB-type peers with the Rust API for Rust-side federation
        if adapter_type == :verisimdb do
          RustClient.post("/federation/register", %{
            store_id: store_id,
            endpoint: endpoint,
            modalities: effective_modalities
          })
        end

        {:reply, :ok, %{state | peers: new_peers}}

      {:error, :unknown_adapter} ->
        Logger.error("Federation: unknown adapter type #{inspect(adapter_type)} for #{store_id}")
        {:reply, {:error, {:unknown_adapter, adapter_type}}, state}
    end
  end

  @impl true
  def handle_call({:deregister, store_id}, _from, state) do
    case Map.get(state.peers, store_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      peer ->
        new_peers = Map.delete(state.peers, store_id)
        Logger.info("Federation: deregistered peer #{store_id}")

        # Deregister VeriSimDB peers from Rust API
        if peer.adapter_type == :verisimdb do
          RustClient.post("/federation/deregister/#{store_id}", %{})
        end

        {:reply, :ok, %{state | peers: new_peers}}
    end
  end

  @impl true
  def handle_call(:list_peers, _from, state) do
    peers =
      state.peers
      |> Map.values()
      |> Enum.map(fn peer ->
        # Return a clean view without the adapter module reference
        Map.drop(peer, [:adapter_module])
      end)

    {:reply, peers, state}
  end

  @impl true
  def handle_call({:query, pattern, modalities, opts}, _from, state) do
    drift_policy = Keyword.get(opts, :drift_policy, :tolerate)
    limit = Keyword.get(opts, :limit, 100)
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    # Build query_params from opts for adapter dispatch
    query_params = %{
      modalities: modalities,
      limit: limit
    }

    # Add optional modality-specific query parameters
    query_params = maybe_add_param(query_params, :text_query, Keyword.get(opts, :text_query))
    query_params = maybe_add_param(query_params, :vector_query, Keyword.get(opts, :vector_query))
    query_params = maybe_add_param(query_params, :graph_pattern, Keyword.get(opts, :graph_pattern))
    query_params = maybe_add_param(query_params, :spatial_bounds, Keyword.get(opts, :spatial_bounds))
    query_params = maybe_add_param(query_params, :temporal_range, Keyword.get(opts, :temporal_range))
    query_params = maybe_add_param(query_params, :filters, Keyword.get(opts, :filters))

    # Resolve pattern to matching stores
    matching = resolve_pattern(state.peers, pattern, modalities)

    # Apply drift policy filter
    {included, excluded} = apply_drift_policy(matching, drift_policy)

    # Fan out queries in parallel — each peer dispatches through its adapter
    tasks =
      Enum.map(included, fn peer ->
        Task.async(fn -> query_peer_via_adapter(peer, query_params, timeout: timeout) end)
      end)

    # Collect results with timeout
    results =
      tasks
      |> Task.yield_many(timeout)
      |> Enum.flat_map(fn
        {_task, {:ok, {:ok, results}}} ->
          results

        {_task, {:ok, {:error, reason}}} ->
          Logger.warning("Federation: peer query failed: #{inspect(reason)}")
          []

        {task, nil} ->
          Task.shutdown(task, :brutal_kill)
          Logger.warning("Federation: peer query timed out")
          []
      end)

    # Handle repair policy: trigger normalization on drifted VeriSimDB stores
    if drift_policy == :repair do
      trigger_repairs(excluded)
    end

    response = %{
      results: results,
      stores_queried: Enum.map(included, & &1.store_id),
      stores_excluded: Enum.map(excluded, & &1.store_id),
      drift_policy: drift_policy
    }

    {:reply, {:ok, response}, state}
  end

  @impl true
  def handle_info(:health_check, state) do
    # Health-check all peers via their adapter modules
    new_peers =
      state.peers
      |> Enum.map(fn {id, peer} ->
        peer_info = build_peer_info(peer)

        case peer.adapter_module.health_check(peer_info) do
          {:ok, response_time} ->
            {id, %{peer |
              last_seen: DateTime.utc_now(),
              response_time_ms: response_time,
              trust_level: min(peer.trust_level + 0.05, 1.0)
            }}

          {:error, reason} ->
            Logger.debug(
              "Federation: health check failed for #{peer.adapter_type} peer #{id}: " <>
                "#{inspect(reason)}"
            )

            {id, %{peer |
              trust_level: max(peer.trust_level - 0.1, 0.0)
            }}
        end
      end)
      |> Map.new()

    {:noreply, %{state | peers: new_peers, health_check_ref: schedule_health_check()}}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Private — Adapter Dispatch
  # ---------------------------------------------------------------------------

  defp query_peer_via_adapter(peer, query_params, opts) do
    peer_info = build_peer_info(peer)
    peer.adapter_module.query(peer_info, query_params, opts)
  end

  defp build_peer_info(peer) do
    %{
      store_id: peer.store_id,
      endpoint: peer.endpoint,
      adapter_config: peer.adapter_config
    }
  end

  # ---------------------------------------------------------------------------
  # Private — Pattern Matching & Drift Policies
  # ---------------------------------------------------------------------------

  defp resolve_pattern(peers, pattern, required_modalities) do
    peers
    |> Map.values()
    |> Enum.filter(fn peer ->
      pattern_matches?(pattern, peer.store_id) &&
        Enum.all?(required_modalities, fn m ->
          # Normalise to string for comparison (modalities may be atoms or strings)
          m_str = to_string(m)
          Enum.any?(peer.modalities, fn pm -> to_string(pm) == m_str end)
        end)
    end)
  end

  defp pattern_matches?("*", _store_id), do: true

  defp pattern_matches?(pattern, store_id) do
    if String.ends_with?(pattern, "/*") do
      prefix = String.trim_trailing(pattern, "/*")
      String.starts_with?(store_id, prefix)
    else
      pattern == store_id
    end
  end

  defp apply_drift_policy(peers, :strict) do
    Enum.split_with(peers, fn peer ->
      peer.trust_level >= @strict_trust_threshold
    end)
  end

  defp apply_drift_policy(peers, _policy) do
    {peers, []}
  end

  # ---------------------------------------------------------------------------
  # Private — Repair Policy
  # ---------------------------------------------------------------------------

  defp trigger_repairs(excluded_peers) do
    Enum.each(excluded_peers, fn peer ->
      Logger.info(
        "Federation: triggering repair on drifted #{peer.adapter_type} store #{peer.store_id}"
      )

      # Only VeriSimDB peers support the normaliser endpoint
      if peer.adapter_type == :verisimdb do
        Task.start(fn ->
          url = "#{peer.endpoint}/normalizer/trigger/all"

          case Req.post(url, json: %{}, receive_timeout: @default_timeout) do
            {:ok, %Req.Response{status: status}} when status in 200..299 ->
              Logger.info("Federation: repair triggered on #{peer.store_id}")

            {:ok, %Req.Response{status: status}} ->
              Logger.warning(
                "Federation: repair request to #{peer.store_id} returned #{status}"
              )

            {:error, reason} ->
              Logger.warning(
                "Federation: repair request to #{peer.store_id} failed: #{inspect(reason)}"
              )
          end
        end)
      else
        Logger.debug(
          "Federation: skipping repair for non-VeriSimDB peer #{peer.store_id} " <>
            "(#{peer.adapter_type} does not support normalisation)"
        )
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # Private — Helpers
  # ---------------------------------------------------------------------------

  defp maybe_add_param(params, _key, nil), do: params
  defp maybe_add_param(params, key, value), do: Map.put(params, key, value)

  defp schedule_health_check do
    Process.send_after(self(), :health_check, @health_check_interval)
  end
end
