// SPDX-License-Identifier: PMPL-1.0-or-later

/**
 * Lith Performance Metrics
 *
 * Real-time performance monitoring and metrics collection
 */

/** Metric type */
type metricType =
  | Counter
  | Gauge
  | Histogram
  | Timer

/** Metric value */
type metricValue =
  | IntValue(int)
  | FloatValue(float)
  | HistogramValue({buckets: array<float>, counts: array<int>})

/** Metric */
type metric = {
  name: string,
  metricType: metricType,
  mutable value: metricValue,
  labels: Js.Dict.t<string>,
  timestamp: float,
}

/** Metrics registry */
type metricsRegistry = {
  mutable metrics: Js.Dict.t<metric>,
  prefix: string,
}

/** Create metrics registry */
let makeRegistry = (~prefix: string="lith"): metricsRegistry => {
  {
    metrics: Js.Dict.empty(),
    prefix,
  }
}

/** Register counter */
let counter = (registry: metricsRegistry, name: string, ~labels: Js.Dict.t<string>=Js.Dict.empty()): metric => {
  let fullName = `${registry.prefix}_${name}`
  let m = {
    name: fullName,
    metricType: Counter,
    value: IntValue(0),
    labels,
    timestamp: Js.Date.now(),
  }
  Js.Dict.set(registry.metrics, fullName, m)
  m
}

/** Register gauge */
let gauge = (registry: metricsRegistry, name: string, ~labels: Js.Dict.t<string>=Js.Dict.empty()): metric => {
  let fullName = `${registry.prefix}_${name}`
  let m = {
    name: fullName,
    metricType: Gauge,
    value: FloatValue(0.0),
    labels,
    timestamp: Js.Date.now(),
  }
  Js.Dict.set(registry.metrics, fullName, m)
  m
}

/** Increment counter */
let inc = (m: metric, ~by: int=1): unit => {
  switch m.value {
  | IntValue(v) => m.value = IntValue(v + by)
  | _ => ()
  }
}

/** Set gauge value */
let set = (m: metric, value: float): unit => {
  switch m.metricType {
  | Gauge => m.value = FloatValue(value)
  | _ => ()
  }
}

/** Timer context */
type timerContext = {
  metric: metric,
  startTime: float,
}

/** Start timer */
let startTimer = (m: metric): timerContext => {
  {metric: m, startTime: Js.Date.now()}
}

/** Stop timer */
let stopTimer = (ctx: timerContext): float => {
  let elapsed = Js.Date.now() -. ctx.startTime
  switch ctx.metric.value {
  | FloatValue(_) => ctx.metric.value = FloatValue(elapsed)
  | _ => ()
  }
  elapsed
}

/** Global metrics registry */
let registry: metricsRegistry = makeRegistry()

/** Pre-defined metrics */
let queryCount = counter(registry, "query_total")
let queryLatency = gauge(registry, "query_latency_ms")
let cacheHits = counter(registry, "cache_hits_total")
let cacheMisses = counter(registry, "cache_misses_total")
let connectionPoolSize = gauge(registry, "connection_pool_size")
let activeConnections = gauge(registry, "active_connections")
let batchSize = gauge(registry, "batch_size")
let errorCount = counter(registry, "errors_total")

/** Record query execution */
let recordQuery = (latencyMs: float): unit => {
  inc(queryCount)
  set(queryLatency, latencyMs)
}

/** Record cache hit */
let recordCacheHit = (): unit => {
  inc(cacheHits)
}

/** Record cache miss */
let recordCacheMiss = (): unit => {
  inc(cacheMisses)
}

/** Record error */
let recordError = (): unit => {
  inc(errorCount)
}

/** Export metrics in Prometheus format */
let exportPrometheus = (): string => {
  let lines: array<string> = []

  Js.Dict.keys(registry.metrics)->Array.forEach(key => {
    switch Js.Dict.get(registry.metrics, key) {
    | Some(m) => {
        let valueStr = switch m.value {
        | IntValue(v) => Int.toString(v)
        | FloatValue(v) => Float.toString(v)
        | HistogramValue(_) => "0" // Simplified
        }
        lines->Array.push(`${m.name} ${valueStr}`)->ignore
      }
    | None => ()
    }
  })

  lines->Array.join("\n")
}

/** Get metrics summary */
let getSummary = (): Js.Dict.t<metricValue> => {
  let summary = Js.Dict.empty()

  Js.Dict.keys(registry.metrics)->Array.forEach(key => {
    switch Js.Dict.get(registry.metrics, key) {
    | Some(m) => Js.Dict.set(summary, m.name, m.value)
    | None => ()
    }
  })

  summary
}
