# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim.AdaptiveLearner do
  @moduledoc """
  Adaptive learning for VeriSimDB optimization.

  Uses feedback loops (observe → decide → act → measure) to learn:
  - Cache TTL policies (hit rate optimization)
  - Normalization thresholds (reduce false positives)
  - Drift tolerance (balance repair cost vs consistency)
  - Query plan selection (learn from execution times)

  Architecture:
  - GenServer per learning domain
  - Periodic measurement and adjustment
  - Convergence detection (stop learning when stable)
  - Rollback on regression
  """

  use GenServer
  require Logger

  @type learning_domain ::
          :cache_ttl
          | :normalization_threshold
          | :drift_tolerance
          | :query_plan

  @type observation :: %{
          timestamp: DateTime.t(),
          metrics: map(),
          action_taken: atom(),
          result: map()
        }

  defmodule State do
    @type t :: %__MODULE__{
            domain: atom(),
            observations: [map()],
            current_policy: map(),
            baseline_policy: map(),
            learning_rate: float(),
            converged: boolean(),
            last_adjustment: DateTime.t() | nil
          }

    defstruct domain: nil,
              observations: [],
              current_policy: %{},
              baseline_policy: %{},
              learning_rate: 0.1,
              converged: false,
              last_adjustment: nil
  end

  # ============================================================================
  # Client API
  # ============================================================================

  @doc """
  Start adaptive learner for a domain.
  """
  def start_link(domain, initial_policy \\ %{}) do
    GenServer.start_link(__MODULE__, {domain, initial_policy}, name: via_tuple(domain))
  end

  @doc """
  Record observation for learning.
  """
  def observe(domain, metrics) do
    GenServer.cast(via_tuple(domain), {:observe, metrics})
  end

  @doc """
  Get current learned policy.
  """
  def get_policy(domain) do
    GenServer.call(via_tuple(domain), :get_policy)
  end

  @doc """
  Force policy adjustment (manual trigger).
  """
  def adjust_policy(domain) do
    GenServer.call(via_tuple(domain), :adjust_policy)
  end

  @doc """
  Reset to baseline policy (rollback learning).
  """
  def reset_policy(domain) do
    GenServer.call(via_tuple(domain), :reset_policy)
  end

  # ============================================================================
  # Server Callbacks
  # ============================================================================

  @impl true
  def init({domain, initial_policy}) do
    state = %State{
      domain: domain,
      current_policy: initial_policy,
      baseline_policy: initial_policy,
      observations: []
    }

    # Schedule periodic learning
    schedule_learning()

    Logger.info("Adaptive learner started for #{domain}")
    {:ok, state}
  end

  @impl true
  def handle_cast({:observe, metrics}, state) do
    observation = %{
      timestamp: DateTime.utc_now(),
      metrics: metrics
    }

    new_state = %{state | observations: [observation | state.observations] |> Enum.take(1000)}

    {:noreply, new_state}
  end

  @impl true
  def handle_call(:get_policy, _from, state) do
    {:reply, state.current_policy, state}
  end

  @impl true
  def handle_call(:adjust_policy, _from, state) do
    case adjust_policy_for_domain(state) do
      {:ok, new_policy} ->
        new_state = %{state | current_policy: new_policy, last_adjustment: DateTime.utc_now()}
        {:reply, {:ok, new_policy}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:reset_policy, _from, state) do
    Logger.warn("Resetting policy for #{state.domain} to baseline")

    new_state = %{
      state
      | current_policy: state.baseline_policy,
        converged: false,
        last_adjustment: DateTime.utc_now()
    }

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_info(:learn, state) do
    new_state =
      if should_learn?(state) do
        case adjust_policy_for_domain(state) do
          {:ok, new_policy} ->
            %{state | current_policy: new_policy, last_adjustment: DateTime.utc_now()}

          {:error, reason} ->
            Logger.error("Learning failed for #{state.domain}: #{inspect(reason)}")
            state
        end
      else
        state
      end

    schedule_learning()
    {:noreply, new_state}
  end

  # ============================================================================
  # Learning Algorithms (Domain-Specific)
  # ============================================================================

  defp adjust_policy_for_domain(%State{domain: :cache_ttl} = state) do
    learn_cache_ttl(state)
  end

  defp adjust_policy_for_domain(%State{domain: :normalization_threshold} = state) do
    learn_normalization_threshold(state)
  end

  defp adjust_policy_for_domain(%State{domain: :drift_tolerance} = state) do
    learn_drift_tolerance(state)
  end

  defp adjust_policy_for_domain(%State{domain: :query_plan} = state) do
    learn_query_plan_selection(state)
  end

  # ============================================================================
  # Cache TTL Learning
  # ============================================================================

  defp learn_cache_ttl(state) do
    recent_obs = Enum.take(state.observations, 100)

    if length(recent_obs) < 10 do
      {:error, :insufficient_data}
    else
      hit_rate = calculate_hit_rate(recent_obs)
      current_ttl = Map.get(state.current_policy, :ttl_seconds, 300)

      new_ttl =
        cond do
          # Low hit rate → increase TTL (cache longer)
          hit_rate < 0.4 ->
            increase = current_ttl * state.learning_rate
            min(current_ttl + increase, 3600)

          # Very high hit rate → decrease TTL (fresher data)
          hit_rate > 0.9 ->
            decrease = current_ttl * state.learning_rate
            max(current_ttl - decrease, 30)

          # Hit rate in acceptable range → maintain
          true ->
            current_ttl
        end
        |> round()

      Logger.info("Cache TTL adjusted: #{current_ttl}s → #{new_ttl}s (hit_rate: #{hit_rate})")

      new_policy = Map.put(state.current_policy, :ttl_seconds, new_ttl)
      {:ok, new_policy}
    end
  end

  defp calculate_hit_rate(observations) do
    totals =
      Enum.reduce(observations, %{hits: 0, misses: 0}, fn obs, acc ->
        %{
          hits: acc.hits + Map.get(obs.metrics, :cache_hits, 0),
          misses: acc.misses + Map.get(obs.metrics, :cache_misses, 0)
        }
      end)

    total_requests = totals.hits + totals.misses

    if total_requests > 0 do
      totals.hits / total_requests
    else
      0.0
    end
  end

  # ============================================================================
  # Normalization Threshold Learning
  # ============================================================================

  defp learn_normalization_threshold(state) do
    recent_obs = Enum.take(state.observations, 100)

    if length(recent_obs) < 10 do
      {:error, :insufficient_data}
    else
      false_positive_rate = calculate_false_positive_rate(recent_obs)
      current_threshold = Map.get(state.current_policy, :deviance_threshold, 0.1)

      new_threshold =
        cond do
          # Too many false positives → relax threshold
          false_positive_rate > 0.2 ->
            increase = current_threshold * state.learning_rate
            min(current_threshold + increase, 0.5)

          # Too few alerts (may be missing real issues) → tighten
          false_positive_rate < 0.05 ->
            decrease = current_threshold * state.learning_rate
            max(current_threshold - decrease, 0.01)

          true ->
            current_threshold
        end

      Logger.info(
        "Normalization threshold adjusted: #{current_threshold} → #{new_threshold} (FP rate: #{false_positive_rate})"
      )

      new_policy = Map.put(state.current_policy, :deviance_threshold, new_threshold)
      {:ok, new_policy}
    end
  end

  defp calculate_false_positive_rate(observations) do
    alerts =
      Enum.filter(observations, fn obs ->
        Map.get(obs.metrics, :deviance_alert, false)
      end)

    false_positives =
      Enum.count(alerts, fn obs ->
        Map.get(obs.metrics, :was_false_positive, false)
      end)

    if length(alerts) > 0 do
      false_positives / length(alerts)
    else
      0.0
    end
  end

  # ============================================================================
  # Drift Tolerance Learning
  # ============================================================================

  defp learn_drift_tolerance(state) do
    recent_obs = Enum.take(state.observations, 100)

    if length(recent_obs) < 10 do
      {:error, :insufficient_data}
    else
      repair_cost = calculate_average_repair_cost(recent_obs)
      inconsistency_impact = calculate_inconsistency_impact(recent_obs)

      current_tolerance = Map.get(state.current_policy, :drift_tolerance_threshold, 0.05)

      new_tolerance =
        cond do
          # Repairs are expensive, inconsistency impact is low → tolerate more drift
          repair_cost > 1000 and inconsistency_impact < 0.1 ->
            increase = current_tolerance * state.learning_rate
            min(current_tolerance + increase, 0.2)

          # Repairs are cheap, inconsistency impact is high → tighten tolerance
          repair_cost < 100 and inconsistency_impact > 0.5 ->
            decrease = current_tolerance * state.learning_rate
            max(current_tolerance - decrease, 0.01)

          true ->
            current_tolerance
        end

      Logger.info(
        "Drift tolerance adjusted: #{current_tolerance} → #{new_tolerance} (repair_cost: #{repair_cost}, impact: #{inconsistency_impact})"
      )

      new_policy = Map.put(state.current_policy, :drift_tolerance_threshold, new_tolerance)
      {:ok, new_policy}
    end
  end

  defp calculate_average_repair_cost(observations) do
    repairs = Enum.filter(observations, fn obs -> Map.has_key?(obs.metrics, :repair_cost_ms) end)

    if length(repairs) > 0 do
      Enum.sum(Enum.map(repairs, fn obs -> obs.metrics.repair_cost_ms end)) / length(repairs)
    else
      0.0
    end
  end

  defp calculate_inconsistency_impact(observations) do
    inconsistencies =
      Enum.count(observations, fn obs ->
        Map.get(obs.metrics, :user_affected_by_inconsistency, false)
      end)

    if length(observations) > 0 do
      inconsistencies / length(observations)
    else
      0.0
    end
  end

  # ============================================================================
  # Query Plan Selection Learning
  # ============================================================================

  defp learn_query_plan_selection(state) do
    recent_obs = Enum.take(state.observations, 200)

    if length(recent_obs) < 20 do
      {:error, :insufficient_data}
    else
      # Group observations by query pattern
      patterns = group_by_query_pattern(recent_obs)

      # For each pattern, find best-performing plan
      learned_plans =
        patterns
        |> Enum.map(fn {pattern, observations} ->
          best_plan = find_best_plan(observations)
          {pattern, best_plan}
        end)
        |> Map.new()

      current_plans = Map.get(state.current_policy, :preferred_plans, %{})

      # Merge learned plans with existing (learned plans take precedence)
      new_plans = Map.merge(current_plans, learned_plans)

      Logger.info("Query plan selection updated: learned #{map_size(learned_plans)} patterns")

      new_policy = Map.put(state.current_policy, :preferred_plans, new_plans)
      {:ok, new_policy}
    end
  end

  defp group_by_query_pattern(observations) do
    Enum.group_by(observations, fn obs ->
      # Extract query pattern (e.g., "SELECT-graph-WHERE-LIMIT")
      Map.get(obs.metrics, :query_pattern, :unknown)
    end)
  end

  defp find_best_plan(observations) do
    # Find plan with lowest average execution time
    observations
    |> Enum.group_by(fn obs -> Map.get(obs.metrics, :plan_id, :unknown) end)
    |> Enum.map(fn {plan_id, obs_for_plan} ->
      avg_time =
        Enum.sum(Enum.map(obs_for_plan, fn o -> Map.get(o.metrics, :execution_time_ms, 0) end)) /
          length(obs_for_plan)

      {plan_id, avg_time}
    end)
    |> Enum.min_by(fn {_plan_id, avg_time} -> avg_time end, fn -> {:unknown, :infinity} end)
    |> elem(0)
  end

  # ============================================================================
  # Convergence Detection
  # ============================================================================

  defp should_learn?(state) do
    cond do
      state.converged ->
        false

      length(state.observations) < 10 ->
        false

      recently_adjusted?(state) ->
        false

      true ->
        # Check if policy has stabilized
        if policy_stable?(state) do
          Logger.info("Learning converged for #{state.domain}")
          false
        else
          true
        end
    end
  end

  defp recently_adjusted?(state) do
    case state.last_adjustment do
      nil ->
        false

      last_time ->
        seconds_since = DateTime.diff(DateTime.utc_now(), last_time, :second)
        # Don't adjust more than once per hour
        seconds_since < 3600
    end
  end

  defp policy_stable?(state) do
    # Check last 10 observations for stability
    recent = Enum.take(state.observations, 10)

    if length(recent) < 10 do
      false
    else
      # Calculate variance in key metric
      variance = calculate_metric_variance(recent, state.domain)
      # Stable if variance < 5%
      variance < 0.05
    end
  end

  defp calculate_metric_variance(observations, domain) do
    metric_key =
      case domain do
        :cache_ttl -> :cache_hit_rate
        :normalization_threshold -> :false_positive_rate
        :drift_tolerance -> :inconsistency_impact
        :query_plan -> :avg_execution_time
      end

    values =
      Enum.map(observations, fn obs ->
        Map.get(obs.metrics, metric_key, 0.0)
      end)

    if length(values) > 1 do
      mean = Enum.sum(values) / length(values)
      variance = Enum.sum(Enum.map(values, fn v -> (v - mean) ** 2 end)) / length(values)
      :math.sqrt(variance) / mean
    else
      1.0
    end
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp via_tuple(domain) do
    {:via, Registry, {VeriSim.LearnerRegistry, domain}}
  end

  defp schedule_learning do
    # Learn every 10 minutes
    Process.send_after(self(), :learn, 600_000)
  end
end
