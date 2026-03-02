# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim.EntityServer do
  @moduledoc """
  GenServer representing a single Hexad entity.

  Each entity has its own process for isolation and fault tolerance.
  The EntityServer coordinates operations across all 6 modalities.

  ## Process-per-Entity Model

  Benefits:
  - Isolation: Entity failures don't cascade
  - Concurrency: Entities can be modified in parallel
  - State: Entity state is encapsulated
  - Supervision: OTP handles restarts

  ## State Structure

  ```elixir
  %{
    id: "entity-uuid",
    status: :active | :normalizing | :stale,
    modalities: %{
      graph: true | false,
      vector: true | false,
      tensor: true | false,
      semantic: true | false,
      document: true | false,
      temporal: true | false
    },
    version: 1,
    last_modified: ~U[2026-01-16 00:00:00Z],
    drift_score: 0.0
  }
  ```
  """

  use GenServer
  require Logger

  alias VeriSim.{DriftMonitor, RustClient}

  # Client API

  @doc """
  Start a new EntityServer for the given entity ID.
  """
  def start_link(entity_id) do
    GenServer.start_link(__MODULE__, entity_id, name: via_tuple(entity_id))
  end

  @doc """
  Get the current state of an entity.
  """
  def get(entity_id) do
    GenServer.call(via_tuple(entity_id), :get)
  end

  @doc """
  Update the entity with new data.
  """
  def update(entity_id, changes) do
    GenServer.call(via_tuple(entity_id), {:update, changes})
  end

  @doc """
  Trigger normalization for the entity.
  """
  def normalize(entity_id) do
    GenServer.cast(via_tuple(entity_id), :normalize)
  end

  @doc """
  Get the modality status for an entity.
  """
  def modality_status(entity_id) do
    GenServer.call(via_tuple(entity_id), :modality_status)
  end

  # Server Callbacks

  @impl true
  def init(entity_id) do
    Logger.info("Starting EntityServer for #{entity_id}")

    state = %{
      id: entity_id,
      status: :active,
      modalities: %{
        graph: false,
        vector: false,
        tensor: false,
        semantic: false,
        document: false,
        temporal: false
      },
      version: 0,
      last_modified: DateTime.utc_now(),
      drift_score: 0.0
    }

    # Schedule periodic drift check
    schedule_drift_check()

    {:ok, state}
  end

  @impl true
  def handle_call(:get, _from, state) do
    {:reply, {:ok, state}, state}
  end

  @impl true
  def handle_call({:update, changes}, _from, state) do
    new_state =
      state
      |> apply_changes(changes)
      |> bump_version()
      |> update_timestamp()

    # Notify drift monitor of change
    DriftMonitor.entity_changed(state.id)

    {:reply, {:ok, new_state}, new_state}
  end

  @impl true
  def handle_call(:modality_status, _from, state) do
    {:reply, {:ok, state.modalities}, state}
  end

  @impl true
  def handle_cast(:normalize, state) do
    Logger.info("Starting normalization for #{state.id}")

    # Snapshot current state via temporal store before normalization
    RustClient.post("/hexads/#{state.id}/versions", %{
      version: state.version,
      modalities: state.modalities,
      drift_score: state.drift_score,
      timestamp: DateTime.to_iso8601(DateTime.utc_now())
    })

    new_state = %{state | status: :normalizing}

    # Determine which modalities have drifted and need normalization
    drifted_modalities =
      case RustClient.get_drift_score(state.id) do
        {:ok, score} when is_map(score) ->
          score
          |> Enum.filter(fn {_k, v} -> is_number(v) and v > 0.3 end)
          |> Enum.map(fn {k, _v} -> k end)

        _ ->
          # If we can't determine drift per-modality, normalize all
          [:graph, :vector, :tensor, :semantic, :document, :temporal]
      end

    # Trigger async normalization via Rust core
    server_pid = self()

    Task.start(fn ->
      case RustClient.normalize(state.id) do
        {:ok, _result} ->
          send(server_pid, {:normalization_complete, :success, drifted_modalities})

        {:error, reason} ->
          Logger.error("Normalization failed for #{state.id}: #{inspect(reason)}")
          send(server_pid, {:normalization_complete, :failure, drifted_modalities})
      end
    end)

    {:noreply, new_state}
  end

  @impl true
  def handle_info(:check_drift, state) do
    new_state =
      case RustClient.get_drift_score(state.id) do
        {:ok, score} ->
          if score > 0.3 do
            Logger.warning("High drift detected for #{state.id}: #{score}")
            DriftMonitor.report_drift(state.id, score)
          end
          %{state | drift_score: score}
        {:error, _} ->
          state
      end

    schedule_drift_check()
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:normalization_complete, result, modalities}, state) do
    new_status = if result == :success, do: :active, else: :stale

    Logger.info(
      "Normalization #{result} for #{state.id}, modalities: #{inspect(modalities)}"
    )

    new_state =
      %{state | status: new_status}
      |> bump_version()
      |> update_timestamp()

    {:noreply, new_state}
  end

  # Backwards-compatible catch for old-format messages
  @impl true
  def handle_info({:normalization_complete, result}, state) do
    new_status = if result == :success, do: :active, else: :stale

    new_state =
      %{state | status: new_status}
      |> update_timestamp()

    {:noreply, new_state}
  end

  # Private Functions

  defp via_tuple(entity_id) do
    {:via, Registry, {VeriSim.EntityRegistry, entity_id}}
  end

  defp apply_changes(state, changes) do
    Enum.reduce(changes, state, fn
      {:modality, modality, value}, acc ->
        put_in(acc, [:modalities, modality], value)
      {key, value}, acc when is_atom(key) ->
        Map.put(acc, key, value)
      _, acc ->
        acc
    end)
  end

  defp bump_version(state) do
    %{state | version: state.version + 1}
  end

  defp update_timestamp(state) do
    %{state | last_modified: DateTime.utc_now()}
  end

  defp schedule_drift_check do
    # Check drift every 30 seconds
    Process.send_after(self(), :check_drift, 30_000)
  end
end
