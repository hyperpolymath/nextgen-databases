# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

"""
Diagnostics — circuit breaker, query metrics, and health reporting for QuandleDB.

Provides three orthogonal capabilities:

  CircuitBreaker — wraps fallible function calls (Skein, semantic index) with
      state-machine fault isolation. States: :closed → :open → :half_open → :closed.
      Self-heals after cooldown by probing with a single call; reopens on failure.

  QueryMetrics — thread-safe rolling statistics over all /api/query calls.
      Tracks counts, latencies, error classes, and pushdown hit rates.

  HealthReport — aggregates component liveness into a structured JSON response
      suitable for readiness/liveness probes and operator dashboards.

Point-to-point tracing is built into EvalTrace (see Evaluator.jl), which records
per-stage timings and row counts. Diagnostics.jl provides the infrastructure that
the evaluator and serve.jl use to surface those traces.
"""

using Dates

# ─────────────────────────────────────────────────────────────────────────────
# Circuit breaker
# ─────────────────────────────────────────────────────────────────────────────

"""
    CircuitBreaker(name; threshold, cooldown_s)

State-machine wrapper around fallible I/O calls.

States:
  :closed    — normal; calls go through. Consecutive failures are counted.
  :open      — tripped; calls fail immediately with the last recorded error.
               Transitions to :half_open after `cooldown_s` seconds.
  :half_open — one probe call allowed through. Success → :closed; failure → :open.

Thread safety: all state mutations are guarded by an internal `ReentrantLock`.
"""
mutable struct CircuitBreaker
    name::String
    threshold::Int           # consecutive failures before opening
    cooldown_s::Float64      # seconds before attempting a probe
    state::Symbol            # :closed | :open | :half_open
    consecutive_failures::Int
    last_failure_at::Float64  # Unix timestamp
    last_error::Union{Exception, Nothing}
    total_calls::Int
    total_failures::Int
    total_short_circuits::Int
    lock::ReentrantLock
end

function CircuitBreaker(name::String;
                        threshold::Int = 3,
                        cooldown_s::Float64 = 30.0)
    CircuitBreaker(name, threshold, cooldown_s,
                   :closed, 0, 0.0, nothing,
                   0, 0, 0,
                   ReentrantLock())
end

"""
    call_with_breaker!(cb::CircuitBreaker, f) -> result

Call `f()` through the circuit breaker. Raises `CircuitOpenError` when the
circuit is open and the cooldown period has not expired.
"""
struct CircuitOpenError <: Exception
    breaker_name::String
    last_error::Union{Exception, Nothing}
    cooldown_remaining_s::Float64
end

Base.showerror(io::IO, e::CircuitOpenError) = print(io,
    "CircuitOpenError($(e.breaker_name)): circuit open; " *
    "retry in $(round(e.cooldown_remaining_s, digits=1))s. " *
    "Last error: $(e.last_error)")

function call_with_breaker!(cb::CircuitBreaker, f)
    lock(cb.lock) do
        cb.total_calls += 1
        now_ts = time()

        if cb.state == :open
            elapsed = now_ts - cb.last_failure_at
            if elapsed >= cb.cooldown_s
                cb.state = :half_open
            else
                cb.total_short_circuits += 1
                throw(CircuitOpenError(cb.name, cb.last_error,
                                       cb.cooldown_s - elapsed))
            end
        end
    end

    # Probe or normal call — outside the lock so f() can be slow
    try
        result = f()
        lock(cb.lock) do
            if cb.state == :half_open
                cb.state = :closed
            end
            cb.consecutive_failures = 0
        end
        return result
    catch e
        lock(cb.lock) do
            cb.consecutive_failures += 1
            cb.total_failures += 1
            cb.last_failure_at = time()
            cb.last_error = e
            if cb.state == :half_open || cb.consecutive_failures >= cb.threshold
                cb.state = :open
            end
        end
        rethrow()
    end
end

"""
    breaker_state_dict(cb) -> Dict

Serialize circuit breaker state for inclusion in health reports.
"""
function breaker_state_dict(cb::CircuitBreaker)
    lock(cb.lock) do
        remaining = cb.state == :open ?
            max(0.0, cb.cooldown_s - (time() - cb.last_failure_at)) : 0.0
        Dict{String, Any}(
            "name"               => cb.name,
            "state"              => string(cb.state),
            "consecutive_failures" => cb.consecutive_failures,
            "threshold"          => cb.threshold,
            "cooldown_remaining_s" => round(remaining, digits=1),
            "total_calls"        => cb.total_calls,
            "total_failures"     => cb.total_failures,
            "total_short_circuits" => cb.total_short_circuits,
            "last_error"         => isnothing(cb.last_error) ? nothing : string(cb.last_error),
        )
    end
end

# ─────────────────────────────────────────────────────────────────────────────
# Query metrics
# ─────────────────────────────────────────────────────────────────────────────

const _LATENCY_WINDOW = 200  # keep last N latencies for percentile calculation

"""
    QueryMetrics()

Thread-safe rolling statistics over KRL/SQL queries.

Error classes tracked:
  :parse_error  — KRLLexError or KRLParseError
  :eval_error   — error during stage execution (type mismatch, etc.)
  :db_error     — Skein DB failure (wrapped or raw)
  :timeout      — query exceeded configured timeout
  :circuit_open — circuit breaker rejected the call
"""
mutable struct QueryMetrics
    total::Int
    by_source::Dict{Symbol, Int}       # :krl, :sql, :unknown
    by_error_class::Dict{Symbol, Int}  # see above
    pushdown_hits::Int
    pushdown_misses::Int
    latencies_ms::Vector{Float64}      # circular buffer (last _LATENCY_WINDOW)
    lock::ReentrantLock
end

QueryMetrics() = QueryMetrics(0, Dict{Symbol,Int}(), Dict{Symbol,Int}(),
                              0, 0, Float64[], ReentrantLock())

"""
    record_query!(m, source, latency_ms; error_class=nothing, pushdown=false)

Record one completed query. `source` ∈ {:krl, :sql, :unknown}.
"""
function record_query!(m::QueryMetrics, source::Symbol, latency_ms::Float64;
                       error_class::Union{Symbol, Nothing} = nothing,
                       pushdown::Bool = false)
    lock(m.lock) do
        m.total += 1
        m.by_source[source] = get(m.by_source, source, 0) + 1
        if !isnothing(error_class)
            m.by_error_class[error_class] = get(m.by_error_class, error_class, 0) + 1
        end
        if pushdown; m.pushdown_hits += 1
        else; m.pushdown_misses += 1; end
        push!(m.latencies_ms, latency_ms)
        if length(m.latencies_ms) > _LATENCY_WINDOW
            deleteat!(m.latencies_ms, 1)
        end
    end
end

"""
    metrics_snapshot(m) -> Dict

Compute derived statistics (p50, p95, p99, avg) and return a snapshot dict.
"""
function metrics_snapshot(m::QueryMetrics)::Dict{String, Any}
    lock(m.lock) do
        lats = sort(copy(m.latencies_ms))
        n = length(lats)
        pct(p) = n == 0 ? 0.0 : lats[max(1, round(Int, p * n))]
        avg = n == 0 ? 0.0 : sum(lats) / n

        Dict{String, Any}(
            "total_queries"   => m.total,
            "by_source"       => Dict(string(k) => v for (k,v) in m.by_source),
            "by_error_class"  => Dict(string(k) => v for (k,v) in m.by_error_class),
            "pushdown_hits"   => m.pushdown_hits,
            "pushdown_misses" => m.pushdown_misses,
            "pushdown_rate"   => m.total > 0 ?
                                 round(m.pushdown_hits / m.total, digits = 3) : 0.0,
            "latency_ms" => Dict{String, Any}(
                "avg" => round(avg, digits = 2),
                "p50" => round(pct(0.50), digits = 2),
                "p95" => round(pct(0.95), digits = 2),
                "p99" => round(pct(0.99), digits = 2),
                "window" => n,
            ),
        )
    end
end

"""
    prometheus_text(m, cb_skein, cb_sem) -> String

Emit Prometheus exposition format text for /metrics.
"""
function prometheus_text(m::QueryMetrics,
                         cb_skein::CircuitBreaker,
                         cb_sem::CircuitBreaker)::String
    snap = metrics_snapshot(m)
    s = IOBuffer()
    function metric(name, help, type, val)
        println(s, "# HELP $name $help")
        println(s, "# TYPE $name $type")
        println(s, "$name $val")
    end
    metric("quandledb_queries_total", "Total queries processed", "counter", m.total)
    metric("quandledb_parse_errors_total", "Parse error count", "counter",
           get(m.by_error_class, :parse_error, 0))
    metric("quandledb_eval_errors_total", "Eval error count", "counter",
           get(m.by_error_class, :eval_error, 0))
    metric("quandledb_db_errors_total", "Database error count", "counter",
           get(m.by_error_class, :db_error, 0))
    metric("quandledb_circuit_open", "Skein DB circuit breaker state (1=open)", "gauge",
           cb_skein.state == :open ? 1 : 0)
    metric("quandledb_sem_circuit_open", "Semantic index circuit breaker state (1=open)", "gauge",
           cb_sem.state == :open ? 1 : 0)
    metric("quandledb_latency_p95_ms", "p95 query latency in milliseconds", "gauge",
           snap["latency_ms"]["p95"])
    metric("quandledb_latency_p99_ms", "p99 query latency in milliseconds", "gauge",
           snap["latency_ms"]["p99"])
    String(take!(s))
end

# ─────────────────────────────────────────────────────────────────────────────
# Health report
# ─────────────────────────────────────────────────────────────────────────────

"""
    ComponentStatus(name, status, detail, latency_ms)

`status` is `:ok`, `:degraded`, or `:down`.
"""
struct ComponentStatus
    name::String
    status::Symbol
    detail::String
    latency_ms::Float64
end

"""
    HealthReport(overall, components, metrics_snap, checked_at)

`overall` is the worst of all component statuses.
"""
struct HealthReport
    overall::Symbol
    components::Vector{ComponentStatus}
    metrics_snap::Dict{String, Any}
    checked_at::String
end

function health_report_dict(r::HealthReport)::Dict{String, Any}
    worst_order = Dict(:down => 2, :degraded => 1, :ok => 0)
    Dict{String, Any}(
        "status"     => string(r.overall),
        "checked_at" => r.checked_at,
        "components" => [Dict{String, Any}(
            "name"       => c.name,
            "status"     => string(c.status),
            "detail"     => c.detail,
            "latency_ms" => round(c.latency_ms, digits = 2),
        ) for c in r.components],
        "metrics" => r.metrics_snap,
    )
end

"""
    check_health(skein_probe, sem_probe, krl_ok, metrics, cb_skein, cb_sem) -> HealthReport

Probe each component and return a structured health report.

`skein_probe` and `sem_probe` are zero-argument callables that return
`(ok::Bool, detail::String)` — call them to measure liveness and latency.
"""
function check_health(skein_probe,
                      sem_probe,
                      krl_ok::Bool,
                      metrics::QueryMetrics,
                      cb_skein::CircuitBreaker,
                      cb_sem::CircuitBreaker)::HealthReport

    function probe_component(name, probe_fn)
        t0 = time()
        try
            ok, detail = probe_fn()
            lat = (time() - t0) * 1000
            st = ok ? :ok : :degraded
            ComponentStatus(name, st, detail, lat)
        catch e
            lat = (time() - t0) * 1000
            ComponentStatus(name, :down, string(e), lat)
        end
    end

    components = ComponentStatus[
        probe_component("skein_db", skein_probe),
        probe_component("semantic_index", sem_probe),
        ComponentStatus("krl_parser", krl_ok ? :ok : :down,
                        krl_ok ? "v0.1.0 operational" : "parser self-test failed", 0.0),
        ComponentStatus("skein_circuit",
                        cb_skein.state == :closed ? :ok :
                        cb_skein.state == :half_open ? :degraded : :down,
                        "state=$(cb_skein.state) failures=$(cb_skein.consecutive_failures)",
                        0.0),
        ComponentStatus("sem_circuit",
                        cb_sem.state == :closed ? :ok :
                        cb_sem.state == :half_open ? :degraded : :down,
                        "state=$(cb_sem.state) failures=$(cb_sem.consecutive_failures)",
                        0.0),
    ]

    worst = :ok
    for c in components
        if c.status == :down && worst != :down
            worst = :down
        elseif c.status == :degraded && worst == :ok
            worst = :degraded
        end
    end

    HealthReport(worst, components, metrics_snapshot(metrics),
                 string(Dates.now(Dates.UTC)) * "Z")
end

# ─────────────────────────────────────────────────────────────────────────────
# KRL parser self-test
# ─────────────────────────────────────────────────────────────────────────────

"""
    krl_parser_selftest() -> (ok::Bool, detail::String)

Run a minimal round-trip through the KRL lexer + parser to verify the
parser module is operational. Does not touch any database.
"""
function krl_parser_selftest()::Tuple{Bool, String}
    try
        prog = parse_krl("from knots | filter crossing_number == 3 | take 1")
        ok = length(prog.statements) == 1
        (ok, ok ? "self-test passed" : "unexpected statement count")
    catch e
        (false, "self-test threw: $e")
    end
end
