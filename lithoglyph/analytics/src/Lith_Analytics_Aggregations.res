// SPDX-License-Identifier: PMPL-1.0-or-later

/**
 * Lith Analytics Aggregations
 *
 * Statistical aggregation functions for data analysis
 */

/** Aggregation type */
type aggregationType =
  | Count
  | Sum
  | Avg
  | Min
  | Max
  | Median
  | Stddev
  | Variance
  | Percentile(float)
  | CountDistinct

/** Aggregation result */
type aggregationResult = {
  aggregationType: aggregationType,
  field: string,
  value: float,
  count: int,
}

/** Group by result */
type groupByResult = {
  groupKey: Js.Dict.t<Js.Json.t>,
  aggregations: array<aggregationResult>,
  count: int,
}

/** Extract numeric value from JSON */
let extractNumeric = (json: Js.Json.t): option<float> => {
  switch Js.Json.classify(json) {
  | JSONNumber(n) => Some(n)
  | JSONString(s) => Float.fromString(s)
  | _ => None
  }
}

/** Count aggregation */
let count = (values: array<Js.Json.t>): float => {
  Int.toFloat(Array.length(values))
}

/** Sum aggregation */
let sum = (values: array<float>): float => {
  values->Array.reduce(0.0, (acc, v) => acc +. v)
}

/** Average aggregation */
let avg = (values: array<float>): float => {
  let len = Array.length(values)
  if len == 0 {
    0.0
  } else {
    sum(values) /. Int.toFloat(len)
  }
}

/** Minimum aggregation */
let minValue = (values: array<float>): option<float> => {
  if Array.length(values) == 0 {
    None
  } else {
    Some(values->Array.reduce(Float.Constants.positiveInfinity, (acc, v) => min(acc, v)))
  }
}

/** Maximum aggregation */
let maxValue = (values: array<float>): option<float> => {
  if Array.length(values) == 0 {
    None
  } else {
    Some(values->Array.reduce(Float.Constants.negativeInfinity, (acc, v) => max(acc, v)))
  }
}

/** Median aggregation */
let median = (values: array<float>): option<float> => {
  let len = Array.length(values)
  if len == 0 {
    None
  } else {
    let sorted = values->Array.toSorted((a, b) => a -. b)
    if mod(len, 2) == 0 {
      let mid = len / 2
      switch (sorted->Array.get(mid - 1), sorted->Array.get(mid)) {
      | (Some(a), Some(b)) => Some((a +. b) /. 2.0)
      | _ => None
      }
    } else {
      sorted->Array.get(len / 2)
    }
  }
}

/** Variance aggregation */
let variance = (values: array<float>): float => {
  let len = Array.length(values)
  if len == 0 {
    0.0
  } else {
    let mean = avg(values)
    let sumSquares = values->Array.reduce(0.0, (acc, v) => {
      let diff = v -. mean
      acc +. diff *. diff
    })
    sumSquares /. Int.toFloat(len)
  }
}

/** Standard deviation aggregation */
let stddev = (values: array<float>): float => {
  Js.Math.sqrt(variance(values))
}

/** Percentile aggregation */
let percentile = (values: array<float>, p: float): option<float> => {
  let len = Array.length(values)
  if len == 0 || p < 0.0 || p > 100.0 {
    None
  } else {
    let sorted = values->Array.toSorted((a, b) => a -. b)
    let index = (p /. 100.0) *. Int.toFloat(len - 1)
    let lower = Float.toInt(Js.Math.floor(index))
    let upper = Float.toInt(Js.Math.ceil(index))
    let fraction = index -. Js.Math.floor(index)

    switch (sorted->Array.get(lower), sorted->Array.get(upper)) {
    | (Some(l), Some(u)) => Some(l +. fraction *. (u -. l))
    | (Some(l), None) => Some(l)
    | _ => None
    }
  }
}

/** Count distinct aggregation */
let countDistinct = (values: array<Js.Json.t>): int => {
  let seen = Js.Dict.empty()
  values->Array.forEach(v => {
    let key = Js.Json.stringify(v)
    Js.Dict.set(seen, key, true)
  })
  Js.Dict.keys(seen)->Array.length
}

/** Apply aggregation to field values */
let applyAggregation = (
  aggregationType: aggregationType,
  values: array<Js.Json.t>,
  field: string,
): aggregationResult => {
  let numericValues = values->Array.filterMap(extractNumeric)
  let count = Array.length(values)

  let value = switch aggregationType {
  | Count => Int.toFloat(count)
  | Sum => sum(numericValues)
  | Avg => avg(numericValues)
  | Min => minValue(numericValues)->Option.getOr(0.0)
  | Max => maxValue(numericValues)->Option.getOr(0.0)
  | Median => median(numericValues)->Option.getOr(0.0)
  | Stddev => stddev(numericValues)
  | Variance => variance(numericValues)
  | Percentile(p) => percentile(numericValues, p)->Option.getOr(0.0)
  | CountDistinct => Int.toFloat(countDistinct(values))
  }

  {aggregationType, field, value, count}
}

/** Group documents by fields */
let groupBy = (
  documents: array<Js.Dict.t<Js.Json.t>>,
  groupFields: array<string>,
  aggregations: array<(aggregationType, string)>,
): array<groupByResult> => {
  // Build groups
  let groups: Js.Dict.t<array<Js.Dict.t<Js.Json.t>>> = Js.Dict.empty()

  documents->Array.forEach(doc => {
    // Build group key
    let keyParts: array<string> = []
    groupFields->Array.forEach(field => {
      switch Js.Dict.get(doc, field) {
      | Some(v) => keyParts->Array.push(Js.Json.stringify(v))->ignore
      | None => keyParts->Array.push("null")->ignore
      }
    })
    let key = keyParts->Array.join("|")

    // Add to group
    switch Js.Dict.get(groups, key) {
    | Some(arr) => arr->Array.push(doc)->ignore
    | None => Js.Dict.set(groups, key, [doc])
    }
  })

  // Process each group
  Js.Dict.keys(groups)->Array.filterMap(key => {
    switch Js.Dict.get(groups, key) {
    | Some(docs) => {
        // Build group key dict
        let groupKey = Js.Dict.empty()
        switch docs->Array.get(0) {
        | Some(firstDoc) =>
          groupFields->Array.forEach(field => {
            switch Js.Dict.get(firstDoc, field) {
            | Some(v) => Js.Dict.set(groupKey, field, v)
            | None => ()
            }
          })
        | None => ()
        }

        // Apply aggregations
        let aggResults = aggregations->Array.map(((aggType, field)) => {
          let values = docs->Array.filterMap(doc => Js.Dict.get(doc, field))
          applyAggregation(aggType, values, field)
        })

        Some({
          groupKey,
          aggregations: aggResults,
          count: Array.length(docs),
        })
      }
    | None => None
    }
  })
}

/** Aggregation type to string */
let aggregationTypeToString = (t: aggregationType): string => {
  switch t {
  | Count => "count"
  | Sum => "sum"
  | Avg => "avg"
  | Min => "min"
  | Max => "max"
  | Median => "median"
  | Stddev => "stddev"
  | Variance => "variance"
  | Percentile(p) => `percentile(${Float.toString(p)})`
  | CountDistinct => "count_distinct"
  }
}
