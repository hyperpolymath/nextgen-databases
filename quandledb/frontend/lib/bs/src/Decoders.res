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
          determinant: optInt("determinant"),
          signature: optInt("signature"),
          alexanderPolynomial: optStr("alexander_polynomial"),
          alexanderDisplay: optStr("alexander_display"),
          jonesPolynomial: optStr("jones_polynomial"),
          jonesDisplay: optStr("jones_display"),
          homflyPolynomial: optStr("homfly_polynomial"),
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

let decodeStageTrace = (json: Js.Json.t): option<Types.stageTrace> => {
  open Js.Json
  switch classify(json) {
  | JSONObject(obj) => {
      let str = key =>
        switch Js.Dict.get(obj, key) {
        | Some(v) => switch classify(v) { | JSONString(s) => s | _ => "" }
        | None => ""
        }
      let int_ = key =>
        switch Js.Dict.get(obj, key) {
        | Some(v) => switch classify(v) { | JSONNumber(n) => Belt.Float.toInt(n) | _ => 0 }
        | None => 0
        }
      let float_ = key =>
        switch Js.Dict.get(obj, key) {
        | Some(v) => switch classify(v) { | JSONNumber(n) => n | _ => 0.0 }
        | None => 0.0
        }
      Some({
        Types.stage: str("stage"),
        rowsIn: int_("rows_in"),
        rowsOut: int_("rows_out"),
        elapsedMs: float_("elapsed_ms"),
        note: str("note"),
      })
    }
  | _ => None
  }
}

let decodeQueryResponse = (json: Js.Json.t): result<Types.queryResponse, string> => {
  open Js.Json
  switch classify(json) {
  | JSONObject(obj) => {
      let float_ = (key, def) =>
        switch Js.Dict.get(obj, key) {
        | Some(v) => switch classify(v) { | JSONNumber(n) => n | _ => def }
        | None => def
        }
      let int_ = (key, def) =>
        switch Js.Dict.get(obj, key) {
        | Some(v) => switch classify(v) { | JSONNumber(n) => Belt.Float.toInt(n) | _ => def }
        | None => def
        }
      let bool_ = (key, def) =>
        switch Js.Dict.get(obj, key) {
        | Some(v) => switch classify(v) { | JSONTrue => true | JSONFalse => false | _ => def }
        | None => def
        }
      let str_ = (key, def) =>
        switch Js.Dict.get(obj, key) {
        | Some(v) => switch classify(v) { | JSONString(s) => s | _ => def }
        | None => def
        }
      let rows = switch Js.Dict.get(obj, "rows") {
      | Some(v) => switch classify(v) { | JSONArray(arr) => arr | _ => [] }
      | None => []
      }
      let warnings = switch Js.Dict.get(obj, "warnings") {
      | Some(v) =>
        switch classify(v) {
        | JSONArray(arr) =>
          arr->Belt.Array.keepMap(item =>
            switch classify(item) { | JSONString(s) => Some(s) | _ => None })
        | _ => []
        }
      | None => []
      }
      let trace = switch Js.Dict.get(obj, "trace") {
      | Some(v) =>
        switch classify(v) {
        | JSONArray(arr) => arr->Belt.Array.keepMap(decodeStageTrace)
        | _ => []
        }
      | None => []
      }
      Ok({
        Types.rows,
        count: int_("count", Belt.Array.length(rows)),
        parseTimeMs: float_("parse_time_ms", 0.0),
        evalTimeMs: float_("eval_time_ms", 0.0),
        totalMs: float_("total_ms", 0.0),
        pushdownUsed: bool_("pushdown_used", false),
        parseSource: str_("parse_source", "krl"),
        warnings,
        trace,
      })
    }
  | _ => Error("Expected JSON object for query response")
  }
}

let decodeQueryError = (json: Js.Json.t): Types.queryError => {
  open Js.Json
  switch classify(json) {
  | JSONObject(obj) => {
      let str_ = (key, def) =>
        switch Js.Dict.get(obj, key) {
        | Some(v) => switch classify(v) { | JSONString(s) => s | _ => def }
        | None => def
        }
      let optInt = key =>
        switch Js.Dict.get(obj, key) {
        | Some(v) => switch classify(v) { | JSONNumber(n) => Some(Belt.Float.toInt(n)) | _ => None }
        | None => None
        }
      {
        Types.errorKind: str_("error", "unknown"),
        message: str_("message", "Unknown error"),
        line: optInt("line"),
        col: optInt("col"),
      }
    }
  | _ => {Types.errorKind: "decode_error", message: "Could not parse error response", line: None, col: None}
  }
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
