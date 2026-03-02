# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim.QueryRouter do
  @moduledoc """
  Query Router - Distributes queries across modalities and nodes.

  Routes queries to the appropriate modality store based on query type,
  and aggregates results from multiple sources when needed.

  ## Query Types

  - `:text` - Full-text search (Document modality)
  - `:vector` - Similarity search (Vector modality)
  - `:graph` - Relationship traversal (Graph modality)
  - `:semantic` - Type-based queries (Semantic modality)
  - `:temporal` - Time-based queries (Temporal modality)
  - `:multi` - Cross-modal queries (multiple modalities)
  """

  use GenServer
  require Logger

  alias VeriSim.RustClient

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Execute a query.

  ## Examples

      # Text search
      QueryRouter.query(:text, "machine learning", limit: 10)

      # Vector similarity
      QueryRouter.query(:vector, [0.1, 0.2, ...], k: 5)

      # Graph traversal
      QueryRouter.query(:graph, %{start: "entity-1", predicate: "relates_to"})

      # Multi-modal
      QueryRouter.query(:multi, %{text: "AI", types: ["https://example.org/Paper"]})
  """
  def query(type, params, opts \\ []) do
    GenServer.call(__MODULE__, {:query, type, params, opts})
  end

  @doc """
  Get query statistics.
  """
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    state = %{
      query_count: 0,
      query_by_type: %{},
      avg_latency_ms: 0.0,
      total_latency_ms: 0
    }
    {:ok, state}
  end

  @impl true
  def handle_call({:query, type, params, opts}, _from, state) do
    start_time = System.monotonic_time(:millisecond)

    result = execute_query(type, params, opts)

    end_time = System.monotonic_time(:millisecond)
    latency = end_time - start_time

    new_state = update_stats(state, type, latency)

    {:reply, result, new_state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    stats = %{
      total_queries: state.query_count,
      queries_by_type: state.query_by_type,
      avg_latency_ms: state.avg_latency_ms
    }
    {:reply, stats, state}
  end

  # Private Functions

  defp execute_query(:text, query, opts) when is_binary(query) do
    limit = Keyword.get(opts, :limit, 10)
    RustClient.search_text(query, limit)
  end

  defp execute_query(:vector, vector, opts) when is_list(vector) do
    k = Keyword.get(opts, :k, 10)
    RustClient.search_vector(vector, k)
  end

  defp execute_query(:graph, %{start: entity_id}, _opts) do
    RustClient.get_related(entity_id)
  end

  defp execute_query(:semantic, %{types: types}, opts) do
    # Type-based query: search for entities matching a type IRI via text search
    limit = Keyword.get(opts, :limit, 10)

    types
    |> List.wrap()
    |> Enum.flat_map(fn type_iri ->
      case RustClient.search_text("type:#{type_iri}", limit) do
        {:ok, results} -> results
        {:error, _} -> []
      end
    end)
    |> Enum.uniq_by(& &1["id"])
    |> Enum.take(limit)
    |> then(&{:ok, &1})
  end

  defp execute_query(:temporal, %{entity_id: entity_id} = params, _opts) do
    # Get entity version at a specific timestamp
    query_params =
      case Map.get(params, :time) do
        nil -> []
        time -> [at: to_string(time)]
      end

    RustClient.get("/hexads/#{entity_id}/versions", query_params)
  end

  defp execute_query(:multi, params, opts) do
    # Multi-modal query - combine results from multiple modalities
    results = []

    results =
      if text = Map.get(params, :text) do
        case execute_query(:text, text, opts) do
          {:ok, text_results} -> results ++ text_results
          _ -> results
        end
      else
        results
      end

    results =
      if vector = Map.get(params, :vector) do
        case execute_query(:vector, vector, opts) do
          {:ok, vector_results} -> results ++ vector_results
          _ -> results
        end
      else
        results
      end

    # Deduplicate and rank
    {:ok, Enum.uniq_by(results, & &1["id"])}
  end

  defp execute_query(type, _params, _opts) do
    {:error, {:unknown_query_type, type}}
  end

  defp update_stats(state, type, latency) do
    new_count = state.query_count + 1
    new_total = state.total_latency_ms + latency
    new_avg = new_total / new_count

    new_by_type = Map.update(state.query_by_type, type, 1, &(&1 + 1))

    %{state |
      query_count: new_count,
      query_by_type: new_by_type,
      avg_latency_ms: new_avg,
      total_latency_ms: new_total
    }
  end
end
