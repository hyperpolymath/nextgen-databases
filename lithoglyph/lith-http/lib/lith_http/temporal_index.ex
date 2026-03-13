# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule LithHttp.TemporalIndex do
  @moduledoc """
  B-tree temporal index for efficient time-series queries.

  Provides O(log n + k) query performance where k = number of results.
  Uses ETS with ordered_set for range queries.

  Features:
  - Timestamp-based indexing (Unix seconds)
  - Fast range queries
  - Per-series indexes
  - Automatic index updates

  Based on B-tree algorithm with ETS ordered_set.
  """

  use GenServer
  require Logger

  @table_prefix :temporal_index_

  # Maximum number of temporal indexes to prevent atom table exhaustion.
  # Each index creates one atom for the ETS named table.
  @max_indexes 10_000

  # Client API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc """
  Create a temporal index for a database + series.
  """
  def create_index(db_id, series_id) do
    GenServer.call(__MODULE__, {:create_index, db_id, series_id})
  end

  @doc """
  Insert a time-series point into the index.
  """
  def insert(db_id, series_id, point_id, timestamp_unix) do
    GenServer.call(__MODULE__, {:insert, db_id, series_id, point_id, timestamp_unix})
  end

  @doc """
  Query points in a time range.
  Returns list of point IDs in chronological order.
  """
  def range_query(db_id, series_id, start_unix, end_unix, limit \\ 1000) do
    GenServer.call(__MODULE__, {:range_query, db_id, series_id, start_unix, end_unix, limit})
  end

  @doc """
  Delete a point from the index.
  """
  def delete(db_id, series_id, point_id, timestamp_unix) do
    GenServer.call(__MODULE__, {:delete, db_id, series_id, point_id, timestamp_unix})
  end

  @doc """
  Drop the temporal index for a database + series.
  """
  def drop_index(db_id, series_id) do
    GenServer.call(__MODULE__, {:drop_index, db_id, series_id})
  end

  @doc """
  Get index statistics (count, time range).
  """
  def stats(db_id, series_id) do
    GenServer.call(__MODULE__, {:stats, db_id, series_id})
  end

  # Server callbacks

  @impl true
  def init(:ok) do
    Logger.info("Temporal index manager started")
    {:ok, %{indexes: %{}}}
  end

  @impl true
  def handle_call({:create_index, db_id, series_id}, _from, state) do
    if map_size(state.indexes) >= @max_indexes do
      {:reply, {:error, :max_indexes_reached}, state}
    else
      # create_table_name_atom/2 is the ONLY path that calls String.to_atom/1,
      # and it is guarded by the @max_indexes check above.
      tbl = create_table_name_atom(db_id, series_id)

      case :ets.info(tbl) do
        :undefined ->
          # Create ordered_set table for efficient range queries
          :ets.new(tbl, [:ordered_set, :named_table, :public, {:write_concurrency, true}])
          new_indexes = Map.put(state.indexes, {db_id, series_id}, tbl)
          {:reply, :ok, %{state | indexes: new_indexes}}

        _ ->
          {:reply, {:error, :index_already_exists}, state}
      end
    end
  end

  @impl true
  def handle_call({:insert, db_id, series_id, point_id, timestamp_unix}, _from, state) do
    case table_name(db_id, series_id) do
      :error ->
        {:reply, {:error, :index_not_found}, state}

      {:ok, tbl} ->
        case :ets.info(tbl) do
          :undefined ->
            {:reply, {:error, :index_not_found}, state}

          _ ->
            # Insert with composite key: {timestamp, point_id}
            # This ensures uniqueness and chronological ordering
            :ets.insert(tbl, {{timestamp_unix, point_id}, %{
              point_id: point_id,
              timestamp_unix: timestamp_unix,
              indexed_at: System.system_time(:second)
            }})
            {:reply, :ok, state}
        end
    end
  end

  @impl true
  def handle_call({:range_query, db_id, series_id, start_unix, end_unix, limit}, _from, state) do
    case table_name(db_id, series_id) do
      :error ->
        {:reply, {:error, :index_not_found}, state}

      {:ok, tbl} ->
        case :ets.info(tbl) do
          :undefined ->
            {:reply, {:error, :index_not_found}, state}

          _ ->
            # Use ETS ordered_set range select
            results = range_select(tbl, start_unix, end_unix, limit)
            {:reply, {:ok, results}, state}
        end
    end
  end

  @impl true
  def handle_call({:delete, db_id, series_id, point_id, timestamp_unix}, _from, state) do
    case table_name(db_id, series_id) do
      :error ->
        {:reply, {:error, :index_not_found}, state}

      {:ok, tbl} ->
        case :ets.info(tbl) do
          :undefined ->
            {:reply, {:error, :index_not_found}, state}

          _ ->
            :ets.delete(tbl, {timestamp_unix, point_id})
            {:reply, :ok, state}
        end
    end
  end

  @impl true
  def handle_call({:drop_index, db_id, series_id}, _from, state) do
    case table_name(db_id, series_id) do
      :error ->
        {:reply, {:error, :index_not_found}, state}

      {:ok, tbl} ->
        case :ets.info(tbl) do
          :undefined ->
            {:reply, {:error, :index_not_found}, state}

          _ ->
            :ets.delete(tbl)
            new_indexes = Map.delete(state.indexes, {db_id, series_id})
            {:reply, :ok, %{state | indexes: new_indexes}}
        end
    end
  end

  @impl true
  def handle_call({:stats, db_id, series_id}, _from, state) do
    case table_name(db_id, series_id) do
      :error ->
        {:reply, {:error, :index_not_found}, state}

      {:ok, tbl} ->
        case :ets.info(tbl) do
          :undefined ->
            {:reply, {:error, :index_not_found}, state}

          _ ->
            count = :ets.info(tbl, :size)

            {min_ts, max_ts} =
              case {:ets.first(tbl), :ets.last(tbl)} do
                {:"$end_of_table", _} -> {nil, nil}
                {_, :"$end_of_table"} -> {nil, nil}
                {{first_ts, _}, {last_ts, _}} -> {first_ts, last_ts}
              end

            stats = %{
              count: count,
              min_timestamp: min_ts,
              max_timestamp: max_ts,
              time_range_seconds: if(min_ts && max_ts, do: max_ts - min_ts, else: 0)
            }

            {:reply, {:ok, stats}, state}
        end
    end
  end

  # Private functions

  @doc false
  # Build table name string from db_id and series_id (always safe, no atom creation).
  defp table_name_string(db_id, series_id) do
    db_hash = :crypto.hash(:md5, db_id) |> Base.encode16(case: :lower) |> String.slice(0..7)
    series_hash = :crypto.hash(:md5, series_id) |> Base.encode16(case: :lower) |> String.slice(0..7)

    "#{@table_prefix}#{db_hash}_#{series_hash}"
  end

  # Create a new atom for an ETS table name. Only called from create_index/2
  # after verifying the index count is below @max_indexes.
  # This is the ONLY place where String.to_atom/1 is permitted.
  defp create_table_name_atom(db_id, series_id) do
    table_name_string(db_id, series_id) |> String.to_atom()
  end

  # Look up an existing table name atom. Used by all operations except create_index.
  # Returns {:ok, atom} if the atom already exists, or :error if it does not.
  # Uses String.to_existing_atom/1 so user input can never exhaust the atom table.
  defp table_name(db_id, series_id) do
    name_str = table_name_string(db_id, series_id)

    try do
      {:ok, String.to_existing_atom(name_str)}
    rescue
      ArgumentError -> :error
    end
  end

  defp range_select(table_name, start_unix, end_unix, limit) do
    # ETS ordered_set allows efficient range iteration
    # Start from first key >= start_unix
    range_select_loop(table_name, {start_unix, ""}, end_unix, limit, [])
  end

  defp range_select_loop(_table, _current_key, _end_unix, 0, acc) do
    # Limit reached
    Enum.reverse(acc)
  end

  defp range_select_loop(table_name, current_key, end_unix, remaining, acc) do
    # Find next key >= current_key
    case find_next_key(table_name, current_key) do
      :"$end_of_table" ->
        Enum.reverse(acc)

      {timestamp_unix, point_id} = next_key ->
        if timestamp_unix > end_unix do
          # Exceeded range
          Enum.reverse(acc)
        else
          # Add to results
          range_select_loop(table_name, next_key, end_unix, remaining - 1, [point_id | acc])
        end
    end
  end

  defp find_next_key(table_name, {target_ts, _target_id}) do
    # Find smallest key >= {target_ts, _target_id}
    case :ets.next(table_name, {target_ts - 1, "~"}) do
      :"$end_of_table" ->
        :"$end_of_table"

      key ->
        key
    end
  end
end
