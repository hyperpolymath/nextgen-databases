// SPDX-License-Identifier: PMPL-1.0-or-later

/**
 * Lith Window Functions
 *
 * SQL-style window functions for advanced analytics
 */

/** Window frame type */
type frameType =
  | Rows
  | Range

/** Frame boundary */
type frameBoundary =
  | UnboundedPreceding
  | CurrentRow
  | Preceding(int)
  | Following(int)
  | UnboundedFollowing

/** Window specification */
type windowSpec = {
  partitionBy: array<string>,
  orderBy: array<(string, bool)>, // (field, ascending)
  frameType: frameType,
  frameStart: frameBoundary,
  frameEnd: frameBoundary,
}

/** Default window spec */
let defaultWindowSpec: windowSpec = {
  partitionBy: [],
  orderBy: [],
  frameType: Rows,
  frameStart: UnboundedPreceding,
  frameEnd: CurrentRow,
}

/** Window function type */
type windowFunction =
  | RowNumber
  | Rank
  | DenseRank
  | Ntile(int)
  | Lag(string, int, option<Js.Json.t>)
  | Lead(string, int, option<Js.Json.t>)
  | FirstValue(string)
  | LastValue(string)
  | NthValue(string, int)
  | CumulativeSum(string)
  | RunningAvg(string)
  | PercentRank

/** Window result */
type windowResult = {
  rowIndex: int,
  partitionKey: string,
  value: Js.Json.t,
}

/** Get partition key for document */
let getPartitionKey = (doc: Js.Dict.t<Js.Json.t>, fields: array<string>): string => {
  fields
  ->Array.map(f => {
    switch Js.Dict.get(doc, f) {
    | Some(v) => Js.Json.stringify(v)
    | None => "null"
    }
  })
  ->Array.join("|")
}

/** Compare documents for ordering */
let compareForOrder = (
  a: Js.Dict.t<Js.Json.t>,
  b: Js.Dict.t<Js.Json.t>,
  orderBy: array<(string, bool)>,
): int => {
  let result = ref(0)

  orderBy->Array.forEach(((field, ascending)) => {
    if result.contents == 0 {
      let aVal = Js.Dict.get(a, field)
      let bVal = Js.Dict.get(b, field)

      let cmp = switch (aVal, bVal) {
      | (Some(av), Some(bv)) => {
          let aStr = Js.Json.stringify(av)
          let bStr = Js.Json.stringify(bv)
          if aStr < bStr {
            -1
          } else if aStr > bStr {
            1
          } else {
            0
          }
        }
      | (Some(_), None) => 1
      | (None, Some(_)) => -1
      | (None, None) => 0
      }

      result := if ascending {
        cmp
      } else {
        -cmp
      }
    }
  })

  result.contents
}

/** Get frame boundaries for a row */
let getFrameRange = (
  currentIndex: int,
  partitionSize: int,
  frameStart: frameBoundary,
  frameEnd: frameBoundary,
): (int, int) => {
  let start = switch frameStart {
  | UnboundedPreceding => 0
  | CurrentRow => currentIndex
  | Preceding(n) => max(0, currentIndex - n)
  | Following(n) => min(partitionSize - 1, currentIndex + n)
  | UnboundedFollowing => partitionSize - 1
  }

  let end_ = switch frameEnd {
  | UnboundedPreceding => 0
  | CurrentRow => currentIndex
  | Preceding(n) => max(0, currentIndex - n)
  | Following(n) => min(partitionSize - 1, currentIndex + n)
  | UnboundedFollowing => partitionSize - 1
  }

  (start, end_)
}

/** Apply window function to partition */
let applyWindowFunction = (
  func: windowFunction,
  partition: array<Js.Dict.t<Js.Json.t>>,
  currentIndex: int,
  spec: windowSpec,
): Js.Json.t => {
  let (frameStart, frameEnd) = getFrameRange(
    currentIndex,
    Array.length(partition),
    spec.frameStart,
    spec.frameEnd,
  )

  switch func {
  | RowNumber => Js.Json.number(Int.toFloat(currentIndex + 1))

  | Rank => {
      // Count how many rows have smaller values
      let current = partition->Array.getUnsafe(currentIndex)
      let rank = ref(1)
      for i in 0 to currentIndex - 1 {
        if compareForOrder(partition->Array.getUnsafe(i), current, spec.orderBy) < 0 {
          rank := rank.contents + 1
        }
      }
      Js.Json.number(Int.toFloat(rank.contents))
    }

  | DenseRank => {
      // Count distinct values before current
      let current = partition->Array.getUnsafe(currentIndex)
      let seen = Js.Dict.empty()
      for i in 0 to currentIndex - 1 {
        let key = spec.orderBy
          ->Array.map(((f, _)) => {
            switch Js.Dict.get(partition->Array.getUnsafe(i), f) {
            | Some(v) => Js.Json.stringify(v)
            | None => "null"
            }
          })
          ->Array.join("|")
        Js.Dict.set(seen, key, true)
      }
      Js.Json.number(Int.toFloat(Js.Dict.keys(seen)->Array.length + 1))
    }

  | Ntile(n) => {
      let partitionSize = Array.length(partition)
      let bucket = Float.toInt(Int.toFloat(currentIndex * n) /. Int.toFloat(partitionSize)) + 1
      Js.Json.number(Int.toFloat(bucket))
    }

  | Lag(field, offset, default) => {
      let targetIndex = currentIndex - offset
      if targetIndex < 0 {
        default->Option.getOr(Js.Json.null)
      } else {
        switch partition->Array.get(targetIndex) {
        | Some(row) => Js.Dict.get(row, field)->Option.getOr(Js.Json.null)
        | None => default->Option.getOr(Js.Json.null)
        }
      }
    }

  | Lead(field, offset, default) => {
      let targetIndex = currentIndex + offset
      switch partition->Array.get(targetIndex) {
      | Some(row) => Js.Dict.get(row, field)->Option.getOr(Js.Json.null)
      | None => default->Option.getOr(Js.Json.null)
      }
    }

  | FirstValue(field) => {
      switch partition->Array.get(frameStart) {
      | Some(row) => Js.Dict.get(row, field)->Option.getOr(Js.Json.null)
      | None => Js.Json.null
      }
    }

  | LastValue(field) => {
      switch partition->Array.get(frameEnd) {
      | Some(row) => Js.Dict.get(row, field)->Option.getOr(Js.Json.null)
      | None => Js.Json.null
      }
    }

  | NthValue(field, n) => {
      let targetIndex = frameStart + n - 1
      if targetIndex <= frameEnd {
        switch partition->Array.get(targetIndex) {
        | Some(row) => Js.Dict.get(row, field)->Option.getOr(Js.Json.null)
        | None => Js.Json.null
        }
      } else {
        Js.Json.null
      }
    }

  | CumulativeSum(field) => {
      let sum = ref(0.0)
      for i in frameStart to min(currentIndex, frameEnd) {
        switch partition->Array.get(i) {
        | Some(row) =>
          switch Js.Dict.get(row, field) {
          | Some(v) =>
            switch Js.Json.classify(v) {
            | JSONNumber(n) => sum := sum.contents +. n
            | _ => ()
            }
          | None => ()
          }
        | None => ()
        }
      }
      Js.Json.number(sum.contents)
    }

  | RunningAvg(field) => {
      let sum = ref(0.0)
      let count = ref(0)
      for i in frameStart to min(currentIndex, frameEnd) {
        switch partition->Array.get(i) {
        | Some(row) =>
          switch Js.Dict.get(row, field) {
          | Some(v) =>
            switch Js.Json.classify(v) {
            | JSONNumber(n) => {
                sum := sum.contents +. n
                count := count.contents + 1
              }
            | _ => ()
            }
          | None => ()
          }
        | None => ()
        }
      }
      if count.contents == 0 {
        Js.Json.number(0.0)
      } else {
        Js.Json.number(sum.contents /. Int.toFloat(count.contents))
      }
    }

  | PercentRank => {
      if Array.length(partition) == 1 {
        Js.Json.number(0.0)
      } else {
        let current = partition->Array.getUnsafe(currentIndex)
        let rank = ref(0)
        for i in 0 to currentIndex - 1 {
          if compareForOrder(partition->Array.getUnsafe(i), current, spec.orderBy) < 0 {
            rank := rank.contents + 1
          }
        }
        Js.Json.number(Int.toFloat(rank.contents) /. Int.toFloat(Array.length(partition) - 1))
      }
    }
  }
}

/** Execute window function on documents */
let execute = (
  documents: array<Js.Dict.t<Js.Json.t>>,
  func: windowFunction,
  spec: windowSpec,
): array<windowResult> => {
  // Group by partition
  let partitions: Js.Dict.t<array<Js.Dict.t<Js.Json.t>>> = Js.Dict.empty()

  documents->Array.forEach(doc => {
    let key = getPartitionKey(doc, spec.partitionBy)
    switch Js.Dict.get(partitions, key) {
    | Some(arr) => arr->Array.push(doc)->ignore
    | None => Js.Dict.set(partitions, key, [doc])
    }
  })

  // Process each partition
  let results: array<windowResult> = []
  let globalIndex = ref(0)

  Js.Dict.keys(partitions)->Array.forEach(partitionKey => {
    switch Js.Dict.get(partitions, partitionKey) {
    | Some(partition) => {
        // Sort partition by orderBy
        let sorted = partition->Array.toSorted((a, b) => Float.toInt(
          Int.toFloat(compareForOrder(a, b, spec.orderBy)),
        ))

        // Apply window function to each row
        sorted->Array.forEachWithIndex((_, i) => {
          let value = applyWindowFunction(func, sorted, i, spec)
          results
          ->Array.push({
            rowIndex: globalIndex.contents,
            partitionKey,
            value,
          })
          ->ignore
          globalIndex := globalIndex.contents + 1
        })
      }
    | None => ()
    }
  })

  results
}

/** Window function to string */
let windowFunctionToString = (f: windowFunction): string => {
  switch f {
  | RowNumber => "row_number()"
  | Rank => "rank()"
  | DenseRank => "dense_rank()"
  | Ntile(n) => `ntile(${Int.toString(n)})`
  | Lag(field, offset, _) => `lag(${field}, ${Int.toString(offset)})`
  | Lead(field, offset, _) => `lead(${field}, ${Int.toString(offset)})`
  | FirstValue(field) => `first_value(${field})`
  | LastValue(field) => `last_value(${field})`
  | NthValue(field, n) => `nth_value(${field}, ${Int.toString(n)})`
  | CumulativeSum(field) => `sum(${field})`
  | RunningAvg(field) => `avg(${field})`
  | PercentRank => "percent_rank()"
  }
}
