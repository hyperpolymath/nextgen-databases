# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim.QueryCache do
  @moduledoc """
  Multi-layer query caching for VeriSimDB.

  Caches:
  1. Query results (expensive ZKP-verified queries)
  2. Parsed ASTs (avoid re-parsing identical queries)
  3. Execution plans (avoid re-planning)
  4. ZKP proofs (expensive to generate)
  5. Store metadata (indexes, capabilities)
  6. Registry lookups (UUID → store mappings)
  7. Temporal versions (frequently accessed historical states)

  Cache Layers:
  - L1: In-memory ETS (hot data, <1ms access)
  - L2: Distributed cache across nodes (warm data, <10ms)
  - L3: Persistent cache in verisim-temporal (cold data, <100ms)

  Cache Policies:
  - TTL-based expiration
  - Drift-aware invalidation
  - Per-modality policies (Vector can be stale, Semantic cannot)
  - LRU eviction when memory limit reached
  """

  use GenServer
  require Logger

  @type cache_key :: String.t()
  @type cache_value :: any()
  @type cache_layer :: :l1 | :l2 | :l3
  @type cache_policy :: :strict | :relaxed | :aggressive

  @type cache_config :: %{
    max_memory_mb: integer(),
    default_ttl_seconds: integer(),
    enable_l2: boolean(),
    enable_l3: boolean(),
    policy: cache_policy(),
    modality_policies: %{String.t() => cache_policy()}
  }

  # Default configuration
  @default_config %{
    max_memory_mb: 1024,  # 1GB L1 cache
    default_ttl_seconds: 300,  # 5 minutes
    enable_l2: true,
    enable_l3: true,
    policy: :relaxed,
    modality_policies: %{
      "VECTOR" => :aggressive,    # Vector results rarely change
      "GRAPH" => :relaxed,        # Graph can be cached briefly
      "DOCUMENT" => :aggressive,  # Document rarely changes
      "SEMANTIC" => :strict,      # ZKP proofs must be fresh
      "TENSOR" => :relaxed,
      "TEMPORAL" => :aggressive   # Historical data immutable
    }
  }

  # Cache entry structure
  defmodule CacheEntry do
    @type t :: %__MODULE__{
      key: String.t(),
      value: any(),
      created_at: DateTime.t(),
      expires_at: DateTime.t(),
      access_count: integer(),
      last_accessed: DateTime.t(),
      size_bytes: integer(),
      layer: :l1 | :l2 | :l3,
      tags: [String.t()]  # For invalidation
    }

    defstruct [
      :key,
      :value,
      :created_at,
      :expires_at,
      access_count: 0,
      :last_accessed,
      :size_bytes,
      layer: :l1,
      tags: []
    ]
  end

  # === Public API ===

  @doc """
  Get cached value, checking all layers (L1 → L2 → L3).
  Returns {:ok, value} or {:error, :not_found}.
  """
  def get(key, opts \\ []) do
    start_time = System.monotonic_time(:microsecond)

    result = case get_from_l1(key) do
      {:ok, entry} ->
        record_hit(:l1, key, start_time)
        {:ok, entry.value}

      {:error, :not_found} ->
        # Try L2
        case get_config().enable_l2 && get_from_l2(key) do
          {:ok, entry} ->
            # Promote to L1
            put_in_l1(key, entry)
            record_hit(:l2, key, start_time)
            {:ok, entry.value}

          _ ->
            # Try L3
            case get_config().enable_l3 && get_from_l3(key) do
              {:ok, entry} ->
                # Promote to L1 and L2
                put_in_l1(key, entry)
                put_in_l2(key, entry)
                record_hit(:l3, key, start_time)
                {:ok, entry.value}

              _ ->
                record_miss(key, start_time)
                {:error, :not_found}
            end
        end
    end

    result
  end

  @doc """
  Put value in cache with optional TTL and tags.
  """
  def put(key, value, opts \\ []) do
    ttl = Keyword.get(opts, :ttl, get_config().default_ttl_seconds)
    tags = Keyword.get(opts, :tags, [])
    layer = Keyword.get(opts, :layer, :l1)

    entry = %CacheEntry{
      key: key,
      value: value,
      created_at: DateTime.utc_now(),
      expires_at: DateTime.add(DateTime.utc_now(), ttl, :second),
      last_accessed: DateTime.utc_now(),
      size_bytes: estimate_size(value),
      layer: layer,
      tags: tags
    }

    case layer do
      :l1 -> put_in_l1(key, entry)
      :l2 -> put_in_l2(key, entry)
      :l3 -> put_in_l3(key, entry)
      :all ->
        put_in_l1(key, entry)
        put_in_l2(key, entry)
        put_in_l3(key, entry)
    end

    :ok
  end

  @doc """
  Invalidate cache entry by key.
  """
  def invalidate(key) do
    GenServer.call(__MODULE__, {:invalidate, key})
  end

  @doc """
  Invalidate all cache entries with specific tag.
  Used for drift-aware invalidation.

  Examples:
    invalidate_by_tag("hexad:abc-123")  # Invalidate all queries for hexad
    invalidate_by_tag("modality:GRAPH") # Invalidate all graph queries
    invalidate_by_tag("federation:/universities/*") # Invalidate federation
  """
  def invalidate_by_tag(tag) do
    GenServer.call(__MODULE__, {:invalidate_by_tag, tag})
  end

  @doc """
  Clear entire cache (all layers).
  """
  def clear_all do
    GenServer.call(__MODULE__, :clear_all)
  end

  @doc """
  Get cache statistics.
  """
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  # === Cache Key Generation ===

  @doc """
  Generate cache key for query result.
  Includes query hash + modalities + source + conditions.
  """
  def query_result_key(query_ast) do
    query_hash = :crypto.hash(:blake3, :erlang.term_to_binary(query_ast))
                 |> Base.encode16(case: :lower)

    "query:result:#{query_hash}"
  end

  @doc """
  Generate cache key for parsed AST.
  """
  def parsed_ast_key(raw_query) do
    query_hash = :crypto.hash(:blake3, raw_query) |> Base.encode16(case: :lower)
    "query:ast:#{query_hash}"
  end

  @doc """
  Generate cache key for execution plan.
  """
  def execution_plan_key(query_ast, optimization_mode) do
    query_hash = :crypto.hash(:blake3, :erlang.term_to_binary(query_ast))
                 |> Base.encode16(case: :lower)

    "query:plan:#{optimization_mode}:#{query_hash}"
  end

  @doc """
  Generate cache key for ZKP proof.
  """
  def zkp_proof_key(contract_name, data_hash) do
    "zkp:proof:#{contract_name}:#{data_hash}"
  end

  @doc """
  Generate cache key for registry lookup.
  """
  def registry_key(hexad_id) do
    "registry:#{hexad_id}"
  end

  @doc """
  Generate cache key for temporal version.
  """
  def temporal_version_key(hexad_id, timestamp) do
    ts_str = DateTime.to_iso8601(timestamp)
    "temporal:#{hexad_id}:#{ts_str}"
  end

  # === Cache Policy Enforcement ===

  @doc """
  Check if value should be cached based on modality policy.
  """
  def should_cache?(modality, query_type) do
    policy = get_policy_for_modality(modality)

    case {policy, query_type} do
      {:strict, :dependent_type} -> true   # Always cache verified queries
      {:strict, :slipstream} -> false      # Never cache unverified
      {:relaxed, _} -> true                # Cache both
      {:aggressive, _} -> true             # Cache everything
    end
  end

  @doc """
  Get TTL for modality based on policy.
  """
  def get_ttl_for_modality(modality) do
    policy = get_policy_for_modality(modality)

    case policy do
      :strict -> 60         # 1 minute (short-lived)
      :relaxed -> 300       # 5 minutes (default)
      :aggressive -> 3600   # 1 hour (long-lived)
    end
  end

  defp get_policy_for_modality(modality) do
    config = get_config()
    Map.get(config.modality_policies, modality, config.policy)
  end

  # === GenServer Implementation ===

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Create ETS tables for L1 cache
    :ets.new(:cache_l1, [:set, :public, :named_table, read_concurrency: true])
    :ets.new(:cache_l2, [:set, :public, :named_table, read_concurrency: true])
    :ets.new(:cache_stats, [:set, :public, :named_table])
    :ets.new(:cache_tags, [:bag, :public, :named_table])  # key → tags mapping

    # Schedule periodic cleanup
    schedule_cleanup()

    state = %{
      config: @default_config,
      hits: %{l1: 0, l2: 0, l3: 0},
      misses: 0,
      evictions: 0,
      current_memory_bytes: 0
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:invalidate, key}, _from, state) do
    invalidate_key(key)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:invalidate_by_tag, tag}, _from, state) do
    # Find all keys with this tag
    keys = :ets.match(:cache_tags, {:"$1", tag})
           |> Enum.map(fn [key] -> key end)

    # Invalidate each
    Enum.each(keys, &invalidate_key/1)

    Logger.info("Invalidated #{length(keys)} cache entries with tag: #{tag}")

    {:reply, {:ok, length(keys)}, state}
  end

  @impl true
  def handle_call(:clear_all, _from, state) do
    :ets.delete_all_objects(:cache_l1)
    :ets.delete_all_objects(:cache_tags)

    if state.config.enable_l2, do: clear_l2()
    if state.config.enable_l3, do: clear_l3()

    new_state = %{state | current_memory_bytes: 0}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    total_requests = state.hits.l1 + state.hits.l2 + state.hits.l3 + state.misses
    hit_rate = if total_requests > 0 do
      (state.hits.l1 + state.hits.l2 + state.hits.l3) / total_requests * 100
    else
      0.0
    end

    l1_count = :ets.info(:cache_l1, :size)

    stats = %{
      hit_rate: Float.round(hit_rate, 2),
      hits: state.hits,
      misses: state.misses,
      evictions: state.evictions,
      l1_entries: l1_count,
      memory_mb: Float.round(state.current_memory_bytes / 1_000_000, 2),
      memory_limit_mb: state.config.max_memory_mb
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    # Remove expired entries
    now = DateTime.utc_now()

    expired_keys = :ets.match(:cache_l1, {:"$1", %{expires_at: :"$2"}})
                   |> Enum.filter(fn [_key, expires_at] ->
                     DateTime.compare(expires_at, now) == :lt
                   end)
                   |> Enum.map(fn [key, _] -> key end)

    Enum.each(expired_keys, &invalidate_key/1)

    # Check memory limit and evict if needed
    new_state = if state.current_memory_bytes > state.config.max_memory_mb * 1_000_000 do
      evict_lru_entries(state)
    else
      state
    end

    # Schedule next cleanup
    schedule_cleanup()

    {:noreply, new_state}
  end

  # === Private Helpers ===

  defp get_from_l1(key) do
    case :ets.lookup(:cache_l1, key) do
      [{^key, entry}] ->
        # Check if expired
        if DateTime.compare(entry.expires_at, DateTime.utc_now()) == :gt do
          # Update access count and time
          updated_entry = %{entry |
            access_count: entry.access_count + 1,
            last_accessed: DateTime.utc_now()
          }
          :ets.insert(:cache_l1, {key, updated_entry})
          {:ok, updated_entry}
        else
          :ets.delete(:cache_l1, key)
          {:error, :expired}
        end

      [] ->
        {:error, :not_found}
    end
  end

  defp put_in_l1(key, entry) do
    :ets.insert(:cache_l1, {key, entry})

    # Store tag mappings
    Enum.each(entry.tags, fn tag ->
      :ets.insert(:cache_tags, {key, tag})
    end)

    :ok
  end

  defp get_from_l2(key) do
    case :ets.lookup(:cache_l2, key) do
      [{^key, entry}] ->
        if DateTime.compare(entry.expires_at, DateTime.utc_now()) == :gt do
          updated_entry = %{entry |
            access_count: entry.access_count + 1,
            last_accessed: DateTime.utc_now()
          }
          :ets.insert(:cache_l2, {key, updated_entry})
          {:ok, updated_entry}
        else
          :ets.delete(:cache_l2, key)
          {:error, :expired}
        end
      [] ->
        {:error, :not_found}
    end
  end

  defp put_in_l2(key, entry) do
    # L2 entries get 3x the TTL of L1
    extended_entry = %{entry |
      layer: :l2,
      expires_at: DateTime.add(entry.expires_at, entry.expires_at |> DateTime.diff(entry.created_at, :second) |> Kernel.*(2), :second)
    }
    :ets.insert(:cache_l2, {key, extended_entry})
    :ok
  end

  defp get_from_l3(key) do
    path = l3_cache_path(key)
    case File.read(path) do
      {:ok, content} ->
        case :erlang.binary_to_term(content) do
          %CacheEntry{} = entry ->
            if DateTime.compare(entry.expires_at, DateTime.utc_now()) == :gt do
              {:ok, entry}
            else
              File.rm(path)
              {:error, :expired}
            end
          _ ->
            {:error, :not_found}
        end
      {:error, _} ->
        {:error, :not_found}
    end
  end

  defp put_in_l3(key, entry) do
    path = l3_cache_path(key)
    File.mkdir_p!(Path.dirname(path))
    l3_entry = %{entry | layer: :l3}
    File.write!(path, :erlang.term_to_binary(l3_entry))
    :ok
  end

  defp clear_l2 do
    :ets.delete_all_objects(:cache_l2)
    :ok
  end

  defp clear_l3 do
    l3_dir = l3_cache_dir()
    if File.exists?(l3_dir) do
      File.rm_rf!(l3_dir)
      File.mkdir_p!(l3_dir)
    end
    :ok
  end

  defp invalidate_key(key) do
    :ets.delete(:cache_l1, key)
    :ets.delete(:cache_l2, key)
    :ets.match_delete(:cache_tags, {key, :_})

    # Invalidate L3
    path = l3_cache_path(key)
    File.rm(path)

    :ok
  end

  defp evict_lru_entries(state) do
    # Get all entries sorted by last_accessed
    entries = :ets.tab2list(:cache_l1)
              |> Enum.sort_by(fn {_key, entry} -> entry.last_accessed end)

    # Evict oldest 10%
    evict_count = div(length(entries), 10)
    to_evict = Enum.take(entries, evict_count)

    Enum.each(to_evict, fn {key, _entry} ->
      invalidate_key(key)
    end)

    Logger.info("Evicted #{evict_count} LRU cache entries")

    %{state | evictions: state.evictions + evict_count}
  end

  defp record_hit(layer, _key, start_time) do
    duration = System.monotonic_time(:microsecond) - start_time
    Logger.debug("Cache hit (#{layer}): #{duration}μs")
    GenServer.cast(__MODULE__, {:record_hit, layer})
  end

  defp record_miss(_key, start_time) do
    duration = System.monotonic_time(:microsecond) - start_time
    Logger.debug("Cache miss: #{duration}μs")
    GenServer.cast(__MODULE__, :record_miss)
  end

  @impl true
  def handle_cast({:record_hit, layer}, state) do
    new_hits = Map.update!(state.hits, layer, &(&1 + 1))
    {:noreply, %{state | hits: new_hits}}
  end

  @impl true
  def handle_cast(:record_miss, state) do
    {:noreply, %{state | misses: state.misses + 1}}
  end

  defp estimate_size(value) do
    # Rough estimate of term size in bytes
    :erlang.external_size(value)
  end

  defp schedule_cleanup do
    # Run cleanup every 60 seconds
    Process.send_after(self(), :cleanup, 60_000)
  end

  defp l3_cache_dir do
    Path.join(System.tmp_dir!(), "verisimdb_cache_l3")
  end

  defp l3_cache_path(key) do
    safe_key = key |> :erlang.phash2() |> Integer.to_string()
    Path.join(l3_cache_dir(), "#{safe_key}.cache")
  end

  defp get_config do
    # TODO: Make this configurable
    @default_config
  end
end
