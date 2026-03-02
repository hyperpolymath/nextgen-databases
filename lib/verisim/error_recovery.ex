# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim.ErrorRecovery do
  @moduledoc """
  Error recovery strategies for VQL queries.

  Implements:
  1. Retry with exponential backoff
  2. Circuit breaker pattern
  3. Fallback to cached results
  4. Partial results handling
  5. Compensating transactions

  All recovery attempts are logged to verisim-temporal for audit trail.
  """

  require Logger
  alias VeriSim.QueryCache
  alias VeriSim.CircuitBreaker
  alias VeriSim.Temporal

  @type recovery_strategy ::
          :retry
          | :cache_fallback
          | :partial_results
          | :fail_fast
          | :compensate

  @type recovery_opts :: [
          max_retries: pos_integer(),
          base_delay_ms: pos_integer(),
          strategy: recovery_strategy(),
          min_quorum: pos_integer()
        ]

  # ============================================================================
  # Retry with Exponential Backoff
  # ============================================================================

  @doc """
  Execute function with automatic retry on recoverable errors.

  ## Options
    * `:max_retries` - Maximum retry attempts (default: 3)
    * `:base_delay_ms` - Base delay in milliseconds (default: 100)
    * `:max_delay_ms` - Maximum delay cap (default: 10_000)

  ## Examples

      iex> ErrorRecovery.retry_with_backoff(fn ->
      ...>   execute_query(query)
      ...> end, max_retries: 5)
      {:ok, result}
  """
  def retry_with_backoff(func, opts \\ []) do
    max_retries = Keyword.get(opts, :max_retries, 3)
    base_delay_ms = Keyword.get(opts, :base_delay_ms, 100)
    max_delay_ms = Keyword.get(opts, :max_delay_ms, 10_000)

    do_retry(func, max_retries, base_delay_ms, max_delay_ms, 0, [])
  end

  defp do_retry(func, max_retries, base_delay_ms, max_delay_ms, attempt, errors)
       when attempt < max_retries do
    case func.() do
      {:ok, result} ->
        if attempt > 0 do
          Logger.info("Retry succeeded on attempt #{attempt + 1}")
        end

        {:ok, result}

      {:error, error} when is_recoverable?(error) ->
        delay_ms = calculate_backoff(attempt, base_delay_ms, max_delay_ms)

        Logger.debug(
          "Retry attempt #{attempt + 1}/#{max_retries} after #{delay_ms}ms for error: #{inspect(error)}"
        )

        Process.sleep(delay_ms)
        do_retry(func, max_retries, base_delay_ms, max_delay_ms, attempt + 1, [error | errors])

      {:error, error} ->
        Logger.error("Non-recoverable error, failing immediately: #{inspect(error)}")
        {:error, error}
    end
  end

  defp do_retry(_func, _max_retries, _base_delay_ms, _max_delay_ms, attempt, errors) do
    Logger.error("Max retries exceeded (#{attempt} attempts), errors: #{inspect(Enum.reverse(errors))}")
    {:error, {:max_retries_exceeded, Enum.reverse(errors)}}
  end

  defp calculate_backoff(attempt, base_delay_ms, max_delay_ms) do
    # Exponential backoff: delay = base * 2^attempt
    delay = base_delay_ms * :math.pow(2, attempt) |> round()

    # Add jitter (±25%)
    jitter = delay * (0.75 + :rand.uniform() * 0.5) |> round()

    # Cap at max_delay_ms
    min(jitter, max_delay_ms)
  end

  @doc """
  Check if an error is recoverable (worth retrying).
  """
  def is_recoverable?({:store_unavailable, _}), do: true
  def is_recoverable?({:network_error, _}), do: true
  def is_recoverable?({:timeout, _}), do: true
  def is_recoverable?({:temporary_failure, _}), do: true
  def is_recoverable?({:resource_exhausted, _}), do: true
  def is_recoverable?(_), do: false

  # ============================================================================
  # Circuit Breaker Integration
  # ============================================================================

  @doc """
  Execute function with circuit breaker protection.

  If the store has failed too many times, the circuit breaker opens
  and requests fail fast without attempting execution.
  """
  def execute_with_circuit_breaker(store_id, func, opts \\ []) do
    case CircuitBreaker.call_with_breaker(store_id, func, opts) do
      {:ok, result} ->
        {:ok, result}

      {:error, {:circuit_open, _msg}} = error ->
        Logger.warn("Circuit breaker open for store #{store_id}, failing fast")
        error

      {:error, _reason} = error ->
        error
    end
  end

  # ============================================================================
  # Cache Fallback
  # ============================================================================

  @doc """
  Execute query with fallback to cached results if execution fails.

  Even stale cache results are returned if the store is unavailable.
  """
  def execute_with_cache_fallback(query, execute_func) do
    cache_key = QueryCache.query_result_key(query.ast)

    case execute_func.() do
      {:ok, result} ->
        # Success, cache for next time
        QueryCache.put(cache_key, result, ttl: 300)
        {:ok, result}

      {:error, {:store_unavailable, _}} = error ->
        # Try cache even if expired
        case QueryCache.get(cache_key) do
          {:ok, cached} ->
            Logger.warn(
              "Using stale cached result due to store unavailability (cache age: #{cache_age(cached)}s)"
            )

            {:ok, %{cached | stale: true, warning: "Data may be outdated due to store unavailability"}}

          {:error, :not_found} ->
            Logger.error("No cached result available for fallback")
            error
        end

      {:error, _} = error ->
        error
    end
  end

  defp cache_age(cached_entry) do
    DateTime.diff(DateTime.utc_now(), cached_entry.created_at, :second)
  end

  # ============================================================================
  # Partial Results Handling
  # ============================================================================

  @doc """
  Execute federated query with partial results handling.

  Returns partial results if enough stores succeed (quorum-based).

  ## Options
    * `:min_quorum` - Minimum successful stores required (default: 1)
    * `:timeout_ms` - Per-store timeout (default: 30_000)
  """
  def execute_with_partial_results(query, stores, execute_on_store_func, opts \\ []) do
    min_quorum = Keyword.get(opts, :min_quorum, 1)
    timeout_ms = Keyword.get(opts, :timeout_ms, 30_000)

    # Execute on all stores in parallel
    results =
      stores
      |> Task.async_stream(
        fn store ->
          {store, execute_on_store_func.(store, query)}
        end,
        timeout: timeout_ms,
        max_concurrency: length(stores)
      )
      |> Enum.to_list()

    # Separate successes and failures
    {succeeded, failed} = categorize_results(results)

    cond do
      Enum.empty?(failed) ->
        # All succeeded
        Logger.info("Federation query succeeded on all #{length(succeeded)} stores")
        {:ok, combine_results(succeeded)}

      Enum.empty?(succeeded) ->
        # All failed
        Logger.error("Federation query failed on all #{length(stores)} stores")
        {:error, {:all_stores_failed, failed}}

      length(succeeded) >= min_quorum ->
        # Enough succeeded for partial results
        Logger.warn(
          "Partial results from federation: succeeded=#{length(succeeded)}, failed=#{length(failed)}"
        )

        {:partial, combine_results(succeeded),
         %{
           failed_stores: Enum.map(failed, fn {store, _} -> store end),
           warning: "Not all stores responded"
         }}

      true ->
        # Not enough succeeded
        Logger.error(
          "Insufficient quorum: needed #{min_quorum}, got #{length(succeeded)}"
        )

        {:error, {:insufficient_quorum, length(succeeded), min_quorum}}
    end
  end

  defp categorize_results(results) do
    Enum.reduce(results, {[], []}, fn
      {:ok, {store, {:ok, result}}}, {succ, fail} ->
        {[{store, result} | succ], fail}

      {:ok, {store, {:error, reason}}}, {succ, fail} ->
        {succ, [{store, reason} | fail]}

      {:exit, reason}, {succ, fail} ->
        {succ, [{:unknown_store, reason} | fail]}
    end)
  end

  defp combine_results(store_results) do
    store_results
    |> Enum.flat_map(fn {_store, result} -> result.data end)
  end

  # ============================================================================
  # Compensating Transactions
  # ============================================================================

  @doc """
  Execute mutation with compensating transaction support.

  If any step fails, all previous steps are rolled back using
  their compensation functions.
  """
  def execute_with_compensation(mutation_id, steps) do
    saga = %{
      id: mutation_id,
      steps: [],
      completed_steps: []
    }

    try do
      saga = execute_saga_steps(saga, steps)
      commit_saga(saga)
      {:ok, saga.completed_steps}
    rescue
      error ->
        Logger.error("Mutation #{mutation_id} failed, rolling back: #{inspect(error)}")
        rollback_saga(saga)
        {:error, {:mutation_failed, error}}
    end
  end

  defp execute_saga_steps(saga, []), do: saga

  defp execute_saga_steps(saga, [{name, forward_func, compensate_func} | rest]) do
    Logger.debug("Executing saga step: #{name}")

    case forward_func.() do
      {:ok, result} ->
        updated_saga = %{
          saga
          | completed_steps: [{name, result, compensate_func} | saga.completed_steps]
        }

        execute_saga_steps(updated_saga, rest)

      {:error, reason} ->
        raise "Saga step #{name} failed: #{inspect(reason)}"
    end
  end

  defp commit_saga(saga) do
    Logger.info("Saga #{saga.id} committed successfully (#{length(saga.completed_steps)} steps)")

    # Log to temporal for audit trail
    Temporal.append_audit_log("saga_commits", %{
      saga_id: saga.id,
      steps: Enum.map(saga.completed_steps, fn {name, _, _} -> name end),
      timestamp: DateTime.utc_now()
    })

    saga
  end

  defp rollback_saga(saga) do
    Logger.warn("Rolling back saga #{saga.id} (#{length(saga.completed_steps)} steps)")

    # Execute compensation functions in reverse order
    saga.completed_steps
    |> Enum.reverse()
    |> Enum.each(fn {name, result, compensate_func} ->
      Logger.debug("Compensating step: #{name}")

      case compensate_func.(result) do
        :ok ->
          Logger.debug("Compensated step #{name} successfully")

        {:error, reason} ->
          Logger.error("Failed to compensate step #{name}: #{inspect(reason)}")
      end
    end)

    # Log to temporal for audit trail
    Temporal.append_audit_log("saga_rollbacks", %{
      saga_id: saga.id,
      steps: Enum.map(saga.completed_steps, fn {name, _, _} -> name end),
      timestamp: DateTime.utc_now()
    })

    :ok
  end

  # ============================================================================
  # Recovery Strategy Selection
  # ============================================================================

  @doc """
  Automatically select recovery strategy based on error type.
  """
  def execute_with_auto_recovery(query, execute_func, opts \\ []) do
    case execute_func.() do
      {:ok, result} ->
        {:ok, result}

      {:error, {:store_unavailable, _} = error} ->
        Logger.info("Store unavailable, trying cache fallback")
        execute_with_cache_fallback(query, execute_func)

      {:error, {:network_error, _} = error} ->
        Logger.info("Network error, retrying with backoff")
        retry_with_backoff(execute_func, opts)

      {:error, {:timeout, _} = error} ->
        Logger.info("Timeout, trying cache fallback")
        execute_with_cache_fallback(query, execute_func)

      {:error, {:permission_denied, _} = error} ->
        Logger.error("Permission denied, failing immediately")
        {:error, error}

      {:error, error} ->
        if is_recoverable?(error) do
          Logger.info("Recoverable error, retrying: #{inspect(error)}")
          retry_with_backoff(execute_func, opts)
        else
          Logger.error("Non-recoverable error: #{inspect(error)}")
          {:error, error}
        end
    end
  end

  # ============================================================================
  # Error Logging
  # ============================================================================

  @doc """
  Log error to audit trail in verisim-temporal.
  """
  def log_error(error, context) do
    entry = %{
      timestamp: DateTime.utc_now(),
      error: inspect(error),
      error_recoverable: is_recoverable?(error),
      query_id: context[:query_id],
      user_id: context[:user_id],
      hexad_ids: context[:hexad_ids],
      recovery_attempted: context[:recovery_attempted],
      recovery_successful: context[:recovery_successful],
      retry_count: context[:retry_count]
    }

    Temporal.append_audit_log("errors", entry)
  end
end
