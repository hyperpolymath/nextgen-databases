# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim.CircuitBreaker do
  @moduledoc """
  Circuit breaker implementation to prevent cascading failures.

  States:
  - :closed - Normal operation, requests pass through
  - :open - Too many failures, requests fail fast
  - :half_open - Testing if service recovered

  Transitions:
  - :closed → :open when failure_count >= threshold
  - :open → :half_open after timeout expires
  - :half_open → :closed on successful request
  - :half_open → :open on failed request
  """

  use GenServer
  require Logger

  @type state :: :closed | :open | :half_open

  defmodule State do
    @type t :: %__MODULE__{
            store_id: String.t(),
            state: :closed | :open | :half_open,
            failure_count: non_neg_integer(),
            failure_threshold: pos_integer(),
            timeout_ms: pos_integer(),
            last_failure_time: DateTime.t() | nil,
            success_count: non_neg_integer(),
            total_requests: non_neg_integer()
          }

    defstruct store_id: nil,
              state: :closed,
              failure_count: 0,
              failure_threshold: 5,
              timeout_ms: 60_000,
              # 1 minute
              last_failure_time: nil,
              success_count: 0,
              total_requests: 0
  end

  # ============================================================================
  # Client API
  # ============================================================================

  @doc """
  Start circuit breaker for a store.
  """
  def start_link(store_id, opts \\ []) do
    GenServer.start_link(__MODULE__, {store_id, opts}, name: via_tuple(store_id))
  end

  @doc """
  Call function with circuit breaker protection.

  Returns:
  - {:ok, result} if function succeeds
  - {:error, {:circuit_open, msg}} if circuit is open
  - {:error, reason} if function fails
  """
  def call_with_breaker(store_id, func, opts \\ []) do
    ensure_started(store_id, opts)

    case get_state(store_id) do
      :open ->
        Logger.warn("Circuit breaker open for store #{store_id}, failing fast")
        {:error, {:circuit_open, "Circuit breaker is open for store #{store_id}"}}

      :half_open ->
        # Try one request to test recovery
        execute_and_record(store_id, func)

      :closed ->
        # Normal operation
        execute_and_record(store_id, func)
    end
  end

  @doc """
  Get current circuit breaker state for a store.
  """
  def get_state(store_id) do
    GenServer.call(via_tuple(store_id), :get_state)
  end

  @doc """
  Get circuit breaker statistics.
  """
  def get_stats(store_id) do
    GenServer.call(via_tuple(store_id), :get_stats)
  end

  @doc """
  Manually reset circuit breaker (force close).
  """
  def reset(store_id) do
    GenServer.call(via_tuple(store_id), :reset)
  end

  # ============================================================================
  # Server Callbacks
  # ============================================================================

  @impl true
  def init({store_id, opts}) do
    state = %State{
      store_id: store_id,
      state: :closed,
      failure_count: 0,
      failure_threshold: Keyword.get(opts, :failure_threshold, 5),
      timeout_ms: Keyword.get(opts, :timeout_ms, 60_000)
    }

    # Schedule periodic health check
    schedule_health_check()

    Logger.info("Circuit breaker started for store #{store_id}")
    {:ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state.state, state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = %{
      state: state.state,
      failure_count: state.failure_count,
      success_count: state.success_count,
      total_requests: state.total_requests,
      failure_rate:
        if state.total_requests > 0 do
          state.failure_count / state.total_requests * 100
        else
          0.0
        end,
      last_failure_time: state.last_failure_time
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_call(:reset, _from, state) do
    Logger.info("Circuit breaker reset for store #{state.store_id}")

    new_state = %{
      state
      | state: :closed,
        failure_count: 0,
        success_count: 0,
        total_requests: 0,
        last_failure_time: nil
    }

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:record_success, result}, _from, state) do
    new_state = %{
      state
      | success_count: state.success_count + 1,
        total_requests: state.total_requests + 1
    }

    new_state =
      case state.state do
        :half_open ->
          # Success in half_open → transition to closed
          Logger.info("Circuit breaker closed for store #{state.store_id} (successful recovery)")
          %{new_state | state: :closed, failure_count: 0}

        :closed ->
          # Success in closed → reset failure count
          %{new_state | failure_count: 0}

        :open ->
          # Should not happen, but handle gracefully
          new_state
      end

    {:reply, {:ok, result}, new_state}
  end

  @impl true
  def handle_call({:record_failure, error}, _from, state) do
    new_state = %{
      state
      | failure_count: state.failure_count + 1,
        total_requests: state.total_requests + 1,
        last_failure_time: DateTime.utc_now()
    }

    new_state =
      case state.state do
        :half_open ->
          # Failure in half_open → back to open
          Logger.warn("Circuit breaker reopened for store #{state.store_id} (recovery failed)")
          %{new_state | state: :open}

        :closed when new_state.failure_count >= state.failure_threshold ->
          # Too many failures → open circuit
          Logger.error(
            "Circuit breaker opened for store #{state.store_id} (#{new_state.failure_count} failures)"
          )

          %{new_state | state: :open}

        :closed ->
          # Still below threshold
          new_state

        :open ->
          # Already open
          new_state
      end

    {:reply, {:error, error}, new_state}
  end

  @impl true
  def handle_info(:health_check, state) do
    new_state =
      case state.state do
        :open ->
          # Check if timeout expired
          if time_since_last_failure(state) >= state.timeout_ms do
            Logger.info(
              "Circuit breaker transitioning to half_open for store #{state.store_id}"
            )

            %{state | state: :half_open}
          else
            state
          end

        _ ->
          state
      end

    schedule_health_check()
    {:noreply, new_state}
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp via_tuple(store_id) do
    {:via, Registry, {VeriSim.CircuitBreakerRegistry, store_id}}
  end

  defp ensure_started(store_id, opts) do
    case Registry.lookup(VeriSim.CircuitBreakerRegistry, store_id) do
      [] ->
        # Start circuit breaker if not exists
        case DynamicSupervisor.start_child(
               VeriSim.CircuitBreakerSupervisor,
               {__MODULE__, {store_id, opts}}
             ) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
          error -> error
        end

      [_] ->
        :ok
    end
  end

  defp execute_and_record(store_id, func) do
    case func.() do
      {:ok, result} ->
        GenServer.call(via_tuple(store_id), {:record_success, result})

      {:error, reason} = error ->
        GenServer.call(via_tuple(store_id), {:record_failure, reason})
        error
    end
  end

  defp time_since_last_failure(state) do
    case state.last_failure_time do
      nil -> :infinity
      time -> DateTime.diff(DateTime.utc_now(), time, :millisecond)
    end
  end

  defp schedule_health_check do
    # Check every 10 seconds
    Process.send_after(self(), :health_check, 10_000)
  end
end
