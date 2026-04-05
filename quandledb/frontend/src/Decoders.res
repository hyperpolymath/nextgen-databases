// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

// JSON decoders for QuandleDB API responses

let decodeKnot = (json: Js.Json.t): result<Types.knot, string> => {
  open Js.Json
  switch classify(json) {
  | JSONObject(obj) => {
      let str = (key: string): result<string, string> =>
        switch Js.Dict.get(obj, key) {
        | Some(v) =>
          switch classify(v) {
          | JSONString(s) => Ok(s)
          | JSONNull => Error(`Missing field: ${key}`)
          | _ => Error(`Expected string for ${key}`)
          }
        | None => Error(`Missing field: ${key}`)
        }

      let int_ = (key: string): result<int, string> =>
        switch Js.Dict.get(obj, key) {
        | Some(v) =>
          switch classify(v) {
          | JSONNumber(n) => Ok(Belt.Float.toInt(n))
          | _ => Error(`Expected int for ${key}`)
          }
        | None => Error(`Missing field: ${key}`)
        }

      let optStr = (key: string): option<string> =>
        switch Js.Dict.get(obj, key) {
        | Some(v) =>
          switch classify(v) {
          | JSONString(s) => Some(s)
          | _ => None
          }
        | None => None
        }

      let optInt = (key: string): option<int> =>
        switch Js.Dict.get(obj, key) {
        | Some(v) =>
          switch classify(v) {
          | JSONNumber(n) => Some(Belt.Float.toInt(n))
          | _ => None
          }
        | None => None
        }

      let gaussCode = switch Js.Dict.get(obj, "gauss_code") {
      | Some(v) =>
        switch classify(v) {
        | JSONArray(arr) =>
          arr->Belt.Array.keepMap(item =>
            switch classify(item) {
            | JSONNumber(n) => Some(Belt.Float.toInt(n))
            | _ => None
            }
          )
        | _ => []
        }
      | None => []
      }

      let metadata = switch Js.Dict.get(obj, "metadata") {
      | Some(v) =>
        switch classify(v) {
        | JSONObject(metaObj) => {
            let result = Js.Dict.empty()
            metaObj
            ->Js.Dict.entries
            ->Belt.Array.forEach(((k, v)) =>
              switch classify(v) {
              | JSONString(s) => Js.Dict.set(result, k, s)
              | _ => ()
              }
            )
            result
          }
        | _ => Js.Dict.empty()
        }
      | None => Js.Dict.empty()
      }

      switch (str("id"), str("name"), int_("crossing_number"), int_("writhe")) {
      | (Ok(id), Ok(name), Ok(cn), Ok(wr)) =>
        Ok({
          Types.id,
          name,
          gaussCode,
          crossingNumber: cn,
          writhe: wr,
          genus: optInt("genus"),
          seifertCircleCount: optInt("seifert_circle_count"),
          jonesPolynomial: optStr("jones_polynomial"),
          jonesDisplay: optStr("jones_display"),
          metadata,
          createdAt: optStr("created_at")->Belt.Option.getWithDefault(""),
          updatedAt: optStr("updated_at")->Belt.Option.getWithDefault(""),
        })
      | (Error(e), _, _, _)
      | (_, Error(e), _, _)
      | (_, _, Error(e), _)
      | (_, _, _, Error(e)) =>
        Error(e)
      }
    }
  | _ => Error("Expected JSON object for knot")
  }
}

let decodeKnotList = (json: Js.Json.t): result<Types.knotListResponse, string> => {
  open Js.Json
  switch classify(json) {
  | JSONObject(obj) => {
      let knots = switch Js.Dict.get(obj, "knots") {
      | Some(v) =>
        switch classify(v) {
        | JSONArray(arr) =>
          arr->Belt.Array.keepMap(item =>
            switch decodeKnot(item) {
            | Ok(k) => Some(k)
            | Error(_) => None
            }
          )
        | _ => []
        }
      | None => []
      }

      let intField = (key: string, default: int) =>
        switch Js.Dict.get(obj, key) {
        | Some(v) =>
          switch classify(v) {
          | JSONNumber(n) => Belt.Float.toInt(n)
          | _ => default
          }
        | None => default
        }

      Ok({
        Types.knots,
        count: intField("count", Belt.Array.length(knots)),
        limit: intField("limit", 100),
        offset: intField("offset", 0),
      })
    }
  | _ => Error("Expected JSON object for knot list")
  }
}

let decodeIntDict = (json: Js.Json.t): Js.Dict.t<int> => {
  open Js.Json
  let result = Js.Dict.empty()
  switch classify(json) {
  | JSONObject(obj) =>
    obj
    ->Js.Dict.entries
    ->Belt.Array.forEach(((k, v)) =>
      switch classify(v) {
      | JSONNumber(n) => Js.Dict.set(result, k, Belt.Float.toInt(n))
      | _ => ()
      }
    )
  | _ => ()
  }
  result
}

let decodeStatistics = (json: Js.Json.t): result<Types.statistics, string> => {
  open Js.Json
  switch classify(json) {
  | JSONObject(obj) => {
      let intField = (key: string) =>
        switch Js.Dict.get(obj, key) {
        | Some(v) =>
          switch classify(v) {
          | JSONNumber(n) => Some(Belt.Float.toInt(n))
          | _ => None
          }
        | None => None
        }

      let crossingDist = switch Js.Dict.get(obj, "crossing_distribution") {
      | Some(v) => decodeIntDict(v)
      | None => Js.Dict.empty()
      }

      let genusDist = switch Js.Dict.get(obj, "genus_distribution") {
      | Some(v) => decodeIntDict(v)
      | None => Js.Dict.empty()
      }

      Ok({
        Types.totalKnots: intField("total_knots")->Belt.Option.getWithDefault(0),
        minCrossings: intField("min_crossings"),
        maxCrossings: intField("max_crossings"),
        crossingDistribution: crossingDist,
        genusDistribution: genusDist,
        schemaVersion: intField("schema_version")->Belt.Option.getWithDefault(0),
      })
    }
  | _ => Error("Expected JSON object for statistics")
  }
}
