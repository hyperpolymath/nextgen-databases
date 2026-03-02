# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim.Consensus.KRaftWAL do
  @moduledoc """
  Write-Ahead Log for the KRaft Raft consensus implementation.

  Persists Raft log entries as newline-delimited JSON (JSONL) for crash recovery.
  Also persists durable state (currentTerm, votedFor) which MUST survive restarts
  to maintain Raft's safety guarantees.

  ## File Layout

  Given `wal_path = "/data/raft/node-1"`, the WAL creates:

  ```
  /data/raft/node-1/
  ├── wal.jsonl          # Append-only log entries
  ├── state.json         # currentTerm + votedFor (overwritten atomically)
  └── snapshot.json      # Registry state at snapshot index (overwritten)
  ```

  ## WAL Format (wal.jsonl)

  Each line is a JSON object:
  ```json
  {"term":1,"index":1,"command":{"type":"register_store","store_id":"s1","endpoint":"http://...","modalities":["graph"]},"timestamp":1234567890}
  ```

  ## Recovery

  On startup:
  1. Read `state.json` to restore currentTerm and votedFor
  2. Read `snapshot.json` to restore registry state + last included index
  3. Read `wal.jsonl` to replay log entries after the snapshot index
  """

  require Logger

  @state_file "state.json"
  @wal_file "wal.jsonl"
  @snapshot_file "snapshot.json"

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Initialize the WAL directory. Creates the directory if needed.
  Returns `:ok` or `{:error, reason}`.
  """
  def init(wal_path) when is_binary(wal_path) do
    case File.mkdir_p(wal_path) do
      :ok -> :ok
      {:error, reason} -> {:error, {:wal_init_failed, reason}}
    end
  end
  def init(nil), do: :ok

  @doc """
  Persist the durable Raft state (currentTerm, votedFor).

  MUST be called before responding to any RPC that changes these values.
  Uses atomic write (write to .tmp, then rename) to prevent corruption.
  """
  def persist_state(wal_path, current_term, voted_for) when is_binary(wal_path) do
    state = %{
      "current_term" => current_term,
      "voted_for" => voted_for
    }

    path = Path.join(wal_path, @state_file)
    tmp_path = path <> ".tmp"

    case File.write(tmp_path, Jason.encode!(state)) do
      :ok ->
        File.rename(tmp_path, path)
      {:error, reason} ->
        Logger.error("KRaft WAL: failed to persist state: #{inspect(reason)}")
        {:error, reason}
    end
  end
  def persist_state(nil, _term, _voted_for), do: :ok

  @doc """
  Append a log entry to the WAL. The entry is fsync'd to ensure durability.
  """
  def append_entry(wal_path, entry) when is_binary(wal_path) do
    path = Path.join(wal_path, @wal_file)
    json_line = Jason.encode!(serialize_entry(entry)) <> "\n"

    case File.write(path, json_line, [:append, :sync]) do
      :ok -> :ok
      {:error, reason} ->
        Logger.error("KRaft WAL: failed to append entry: #{inspect(reason)}")
        {:error, reason}
    end
  end
  def append_entry(nil, _entry), do: :ok

  @doc """
  Append multiple log entries to the WAL in a single write.
  """
  def append_entries(wal_path, entries) when is_binary(wal_path) and is_list(entries) do
    if entries == [] do
      :ok
    else
      path = Path.join(wal_path, @wal_file)
      lines = Enum.map_join(entries, fn entry ->
        Jason.encode!(serialize_entry(entry)) <> "\n"
      end)

      case File.write(path, lines, [:append, :sync]) do
        :ok -> :ok
        {:error, reason} ->
          Logger.error("KRaft WAL: failed to append entries: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end
  def append_entries(nil, _entries), do: :ok

  @doc """
  Save a snapshot of the registry state at a given index.

  After saving, truncates the WAL to remove entries at or before the snapshot index.
  """
  def save_snapshot(wal_path, registry, last_included_index, last_included_term) when is_binary(wal_path) do
    snapshot = %{
      "registry" => serialize_registry(registry),
      "last_included_index" => last_included_index,
      "last_included_term" => last_included_term,
      "timestamp" => System.system_time(:millisecond)
    }

    path = Path.join(wal_path, @snapshot_file)
    tmp_path = path <> ".tmp"

    case File.write(tmp_path, Jason.encode!(snapshot, pretty: true)) do
      :ok ->
        File.rename(tmp_path, path)
        # Truncate WAL to only contain entries after the snapshot
        truncate_wal(wal_path, last_included_index)
      {:error, reason} ->
        Logger.error("KRaft WAL: failed to save snapshot: #{inspect(reason)}")
        {:error, reason}
    end
  end
  def save_snapshot(nil, _registry, _index, _term), do: :ok

  @doc """
  Recover Raft state from the WAL directory.

  Returns `{:ok, recovered_state}` where recovered_state contains:
  - `:current_term` — persisted term
  - `:voted_for` — persisted vote
  - `:log` — recovered log entries (after snapshot)
  - `:registry` — snapshot registry state (or empty)
  - `:snapshot_index` — last included index from snapshot
  - `:snapshot_term` — last included term from snapshot

  Returns `{:ok, nil}` if no WAL exists (fresh start).
  """
  def recover(wal_path) when is_binary(wal_path) do
    if File.dir?(wal_path) do
      state = recover_state(wal_path)
      {registry, snap_index, snap_term} = recover_snapshot(wal_path)
      log = recover_log(wal_path, snap_index)

      {:ok, %{
        current_term: state[:current_term] || 0,
        voted_for: state[:voted_for],
        log: log,
        registry: registry,
        snapshot_index: snap_index,
        snapshot_term: snap_term
      }}
    else
      {:ok, nil}
    end
  end
  def recover(nil), do: {:ok, nil}

  # ---------------------------------------------------------------------------
  # Private: Recovery
  # ---------------------------------------------------------------------------

  defp recover_state(wal_path) do
    path = Path.join(wal_path, @state_file)

    case File.read(path) do
      {:ok, data} ->
        case Jason.decode(data) do
          {:ok, %{"current_term" => term, "voted_for" => voted_for}} ->
            %{current_term: term, voted_for: voted_for}
          _ ->
            %{}
        end
      {:error, _} ->
        %{}
    end
  end

  defp recover_snapshot(wal_path) do
    path = Path.join(wal_path, @snapshot_file)

    case File.read(path) do
      {:ok, data} ->
        case Jason.decode(data) do
          {:ok, %{"registry" => reg, "last_included_index" => idx, "last_included_term" => term}} ->
            {deserialize_registry(reg), idx, term}
          _ ->
            {nil, 0, 0}
        end
      {:error, _} ->
        {nil, 0, 0}
    end
  end

  defp recover_log(wal_path, after_index) do
    path = Path.join(wal_path, @wal_file)

    case File.read(path) do
      {:ok, data} ->
        data
        |> String.split("\n", trim: true)
        |> Enum.flat_map(fn line ->
          case Jason.decode(line) do
            {:ok, entry_map} ->
              entry = deserialize_entry(entry_map)
              if entry.index > after_index, do: [entry], else: []
            _ ->
              Logger.warning("KRaft WAL: skipping corrupt line: #{String.slice(line, 0, 100)}")
              []
          end
        end)
      {:error, _} ->
        []
    end
  end

  @doc """
  Truncate the WAL, keeping only entries with index <= `keep_up_to_index`.

  Used when a follower's log is truncated due to receiving conflicting entries
  from a new leader. After calling this, `append_entries/2` can be used to
  write the correct entries from the leader.
  """
  def truncate_after(wal_path, keep_up_to_index) when is_binary(wal_path) do
    path = Path.join(wal_path, @wal_file)

    case File.read(path) do
      {:ok, data} ->
        remaining = data
          |> String.split("\n", trim: true)
          |> Enum.filter(fn line ->
            case Jason.decode(line) do
              {:ok, %{"index" => idx}} -> idx <= keep_up_to_index
              _ -> false
            end
          end)
          |> Enum.join("\n")

        remaining = if remaining != "", do: remaining <> "\n", else: ""
        File.write(path, remaining, [:sync])

      {:error, _} -> :ok
    end
  end
  def truncate_after(nil, _index), do: :ok

  # ---------------------------------------------------------------------------
  # Private: Truncation (used by snapshotting)
  # ---------------------------------------------------------------------------

  defp truncate_wal(wal_path, up_to_index) do
    path = Path.join(wal_path, @wal_file)

    case File.read(path) do
      {:ok, data} ->
        remaining = data
          |> String.split("\n", trim: true)
          |> Enum.filter(fn line ->
            case Jason.decode(line) do
              {:ok, %{"index" => idx}} -> idx > up_to_index
              _ -> false
            end
          end)
          |> Enum.join("\n")

        remaining = if remaining != "", do: remaining <> "\n", else: ""
        File.write(path, remaining)

      {:error, _} -> :ok
    end
  end

  # ---------------------------------------------------------------------------
  # Private: Serialization
  # ---------------------------------------------------------------------------

  defp serialize_entry(entry) do
    %{
      "term" => entry.term,
      "index" => entry.index,
      "command" => serialize_command(entry.command),
      "timestamp" => entry[:timestamp] || System.system_time(:millisecond)
    }
  end

  defp serialize_command(:noop), do: %{"type" => "noop"}
  defp serialize_command({:register_store, store_id, endpoint, modalities}) do
    %{"type" => "register_store", "store_id" => store_id,
      "endpoint" => endpoint, "modalities" => modalities}
  end
  defp serialize_command({:unregister_store, store_id}) do
    %{"type" => "unregister_store", "store_id" => store_id}
  end
  defp serialize_command({:map_hexad, hexad_id, locations}) do
    %{"type" => "map_hexad", "hexad_id" => hexad_id,
      "locations" => locations}
  end
  defp serialize_command({:unmap_hexad, hexad_id}) do
    %{"type" => "unmap_hexad", "hexad_id" => hexad_id}
  end
  defp serialize_command({:update_trust, store_id, new_trust}) do
    %{"type" => "update_trust", "store_id" => store_id,
      "new_trust" => new_trust}
  end
  defp serialize_command(other) do
    %{"type" => "unknown", "data" => inspect(other)}
  end

  defp deserialize_entry(map) do
    %{
      term: map["term"],
      index: map["index"],
      command: deserialize_command(map["command"]),
      timestamp: map["timestamp"]
    }
  end

  defp deserialize_command(%{"type" => "noop"}), do: :noop
  defp deserialize_command(%{"type" => "register_store"} = cmd) do
    {:register_store, cmd["store_id"], cmd["endpoint"], cmd["modalities"]}
  end
  defp deserialize_command(%{"type" => "unregister_store"} = cmd) do
    {:unregister_store, cmd["store_id"]}
  end
  defp deserialize_command(%{"type" => "map_hexad"} = cmd) do
    {:map_hexad, cmd["hexad_id"], cmd["locations"]}
  end
  defp deserialize_command(%{"type" => "unmap_hexad"} = cmd) do
    {:unmap_hexad, cmd["hexad_id"]}
  end
  defp deserialize_command(%{"type" => "update_trust"} = cmd) do
    {:update_trust, cmd["store_id"], cmd["new_trust"]}
  end
  defp deserialize_command(_), do: :noop

  defp serialize_registry(registry) do
    %{
      "stores" => Map.new(registry[:stores] || %{}, fn {k, v} ->
        {k, %{
          "store_id" => v[:store_id] || k,
          "endpoint" => v[:endpoint],
          "modalities" => v[:modalities],
          "trust_level" => v[:trust_level]
        }}
      end),
      "mappings" => Map.new(registry[:mappings] || %{}, fn {k, v} ->
        {k, %{
          "hexad_id" => v[:hexad_id] || k,
          "locations" => v[:locations],
          "primary_store" => v[:primary_store]
        }}
      end)
    }
  end

  defp deserialize_registry(nil), do: nil
  defp deserialize_registry(map) do
    %{
      stores: Map.new(map["stores"] || %{}, fn {k, v} ->
        {k, %{
          store_id: v["store_id"] || k,
          endpoint: v["endpoint"],
          modalities: v["modalities"] || [],
          trust_level: v["trust_level"] || 1.0,
          last_seen: nil,
          response_time_ms: nil
        }}
      end),
      mappings: Map.new(map["mappings"] || %{}, fn {k, v} ->
        {k, %{
          hexad_id: v["hexad_id"] || k,
          locations: v["locations"],
          primary_store: v["primary_store"],
          created: nil,
          modified: nil
        }}
      end),
      config: %{
        min_trust_level: 0.5,
        max_store_downtime_ms: 300_000,
        replication_factor: 3,
        consistency_mode: :quorum
      }
    }
  end
end
