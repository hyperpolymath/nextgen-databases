// SPDX-License-Identifier: PMPL-1.0-or-later

/**
 * Lith Time Series Analytics
 *
 * Time-based data analysis and trend detection
 */

/** Time bucket granularity */
type timeGranularity =
  | Second
  | Minute
  | Hour
  | Day
  | Week
  | Month
  | Quarter
  | Year

/** Time series data point */
type dataPoint = {
  timestamp: float,
  value: float,
  metadata: option<Js.Dict.t<Js.Json.t>>,
}

/** Time bucket */
type timeBucket = {
  start: float,
  end_: float,
  points: array<dataPoint>,
  aggregatedValue: float,
}

/** Time series */
type timeSeries = {
  name: string,
  field: string,
  granularity: timeGranularity,
  buckets: array<timeBucket>,
  startTime: float,
  endTime: float,
}

/** Trend direction */
type trendDirection =
  | Increasing
  | Decreasing
  | Stable
  | Volatile

/** Trend analysis result */
type trendAnalysis = {
  direction: trendDirection,
  slope: float,
  rSquared: float,
  changePercent: float,
}

/** Granularity to milliseconds */
let granularityToMs = (g: timeGranularity): float => {
  switch g {
  | Second => 1000.0
  | Minute => 60000.0
  | Hour => 3600000.0
  | Day => 86400000.0
  | Week => 604800000.0
  | Month => 2592000000.0 // Approximation (30 days)
  | Quarter => 7776000000.0 // Approximation (90 days)
  | Year => 31536000000.0 // Approximation (365 days)
  }
}

/** Get bucket start for timestamp */
let getBucketStart = (timestamp: float, granularity: timeGranularity): float => {
  let ms = granularityToMs(granularity)
  Js.Math.floor(timestamp /. ms) *. ms
}

/** Create time series from data points */
let createTimeSeries = (
  name: string,
  field: string,
  points: array<dataPoint>,
  granularity: timeGranularity,
): timeSeries => {
  if Array.length(points) == 0 {
    {
      name,
      field,
      granularity,
      buckets: [],
      startTime: 0.0,
      endTime: 0.0,
    }
  } else {
    // Sort by timestamp
    let sorted = points->Array.toSorted((a, b) => a.timestamp -. b.timestamp)

    // Find time range
    let startTime = switch sorted->Array.get(0) {
    | Some(p) => getBucketStart(p.timestamp, granularity)
    | None => 0.0
    }
    let endTime = switch sorted->Array.get(Array.length(sorted) - 1) {
    | Some(p) => getBucketStart(p.timestamp, granularity) +. granularityToMs(granularity)
    | None => 0.0
    }

    // Group into buckets
    let bucketMap: Js.Dict.t<array<dataPoint>> = Js.Dict.empty()

    sorted->Array.forEach(point => {
      let bucketStart = getBucketStart(point.timestamp, granularity)
      let key = Float.toString(bucketStart)
      switch Js.Dict.get(bucketMap, key) {
      | Some(arr) => arr->Array.push(point)->ignore
      | None => Js.Dict.set(bucketMap, key, [point])
      }
    })

    // Create buckets
    let ms = granularityToMs(granularity)
    let buckets: array<timeBucket> = []
    let numBuckets = Float.toInt((endTime -. startTime) /. ms)

    for i in 0 to numBuckets - 1 {
      let start = startTime +. Int.toFloat(i) *. ms
      let key = Float.toString(start)
      let points = Js.Dict.get(bucketMap, key)->Option.getOr([])
      let values = points->Array.map(p => p.value)
      let aggregatedValue = if Array.length(values) == 0 {
        0.0
      } else {
        values->Array.reduce(0.0, (a, b) => a +. b) /. Int.toFloat(Array.length(values))
      }

      buckets->Array.push({
        start,
        end_: start +. ms,
        points,
        aggregatedValue,
      })->ignore
    }

    {name, field, granularity, buckets, startTime, endTime}
  }
}

/** Calculate linear regression */
let linearRegression = (points: array<(float, float)>): (float, float, float) => {
  let n = Int.toFloat(Array.length(points))
  if n < 2.0 {
    (0.0, 0.0, 0.0)
  } else {
    let sumX = points->Array.reduce(0.0, (acc, (x, _)) => acc +. x)
    let sumY = points->Array.reduce(0.0, (acc, (_, y)) => acc +. y)
    let sumXY = points->Array.reduce(0.0, (acc, (x, y)) => acc +. x *. y)
    let sumX2 = points->Array.reduce(0.0, (acc, (x, _)) => acc +. x *. x)
    let sumY2 = points->Array.reduce(0.0, (acc, (_, y)) => acc +. y *. y)

    let slope = (n *. sumXY -. sumX *. sumY) /. (n *. sumX2 -. sumX *. sumX)
    let intercept = (sumY -. slope *. sumX) /. n

    // R-squared
    let ssTotal = sumY2 -. sumY *. sumY /. n
    let ssResidual = points->Array.reduce(0.0, (acc, (x, y)) => {
      let predicted = slope *. x +. intercept
      let residual = y -. predicted
      acc +. residual *. residual
    })
    let rSquared = if ssTotal == 0.0 {
      1.0
    } else {
      1.0 -. ssResidual /. ssTotal
    }

    (slope, intercept, rSquared)
  }
}

/** Analyze trend in time series */
let analyzeTrend = (series: timeSeries): trendAnalysis => {
  if Array.length(series.buckets) < 2 {
    {direction: Stable, slope: 0.0, rSquared: 0.0, changePercent: 0.0}
  } else {
    // Create points for regression (index, value)
    let points = series.buckets->Array.mapWithIndex((bucket, i) =>
      (Int.toFloat(i), bucket.aggregatedValue)
    )

    let (slope, _, rSquared) = linearRegression(points)

    // Calculate change percent
    let firstValue = switch series.buckets->Array.get(0) {
    | Some(b) => b.aggregatedValue
    | None => 0.0
    }
    let lastValue = switch series.buckets->Array.get(Array.length(series.buckets) - 1) {
    | Some(b) => b.aggregatedValue
    | None => 0.0
    }
    let changePercent = if firstValue == 0.0 {
      0.0
    } else {
      (lastValue -. firstValue) /. firstValue *. 100.0
    }

    // Determine direction
    let direction = if rSquared < 0.3 {
      Volatile
    } else if slope > 0.01 {
      Increasing
    } else if slope < -0.01 {
      Decreasing
    } else {
      Stable
    }

    {direction, slope, rSquared, changePercent}
  }
}

/** Moving average */
let movingAverage = (series: timeSeries, windowSize: int): array<float> => {
  let values = series.buckets->Array.map(b => b.aggregatedValue)
  let len = Array.length(values)

  if len < windowSize {
    values
  } else {
    let result: array<float> = []
    for i in 0 to len - windowSize {
      let sum = ref(0.0)
      for j in 0 to windowSize - 1 {
        switch values->Array.get(i + j) {
        | Some(v) => sum := sum.contents +. v
        | None => ()
        }
      }
      result->Array.push(sum.contents /. Int.toFloat(windowSize))->ignore
    }
    result
  }
}

/** Detect anomalies using standard deviation */
let detectAnomalies = (series: timeSeries, threshold: float): array<timeBucket> => {
  let values = series.buckets->Array.map(b => b.aggregatedValue)
  let len = Array.length(values)

  if len < 2 {
    []
  } else {
    let mean = values->Array.reduce(0.0, (a, b) => a +. b) /. Int.toFloat(len)
    let variance = values->Array.reduce(0.0, (acc, v) => {
      let diff = v -. mean
      acc +. diff *. diff
    }) /. Int.toFloat(len)
    let stddev = Js.Math.sqrt(variance)

    series.buckets->Array.filter(bucket => {
      let deviation = Js.Math.abs_float(bucket.aggregatedValue -. mean)
      deviation > threshold *. stddev
    })
  }
}

/** Granularity to string */
let granularityToString = (g: timeGranularity): string => {
  switch g {
  | Second => "second"
  | Minute => "minute"
  | Hour => "hour"
  | Day => "day"
  | Week => "week"
  | Month => "month"
  | Quarter => "quarter"
  | Year => "year"
  }
}

/** Trend direction to string */
let trendDirectionToString = (d: trendDirection): string => {
  switch d {
  | Increasing => "increasing"
  | Decreasing => "decreasing"
  | Stable => "stable"
  | Volatile => "volatile"
  }
}
