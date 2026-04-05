// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

// HTTP API client for QuandleDB server

let baseUrl = ""

// Type-safe Fetch API bindings (no Obj.magic)
type fetchResponse
@val external fetch: (string, 'a) => promise<fetchResponse> = "fetch"
@get external responseOk: fetchResponse => bool = "ok"
@get external responseStatus: fetchResponse => int = "status"
@send external responseJson: fetchResponse => promise<Js.Json.t> = "json"
@send external responseText: fetchResponse => promise<string> = "text"

let fetchJson = async (url: string): result<Js.Json.t, string> => {
  try {
    let resp = await fetch(url, {"method": "GET"})
    if responseOk(resp) {
      let data = await responseJson(resp)
      Ok(data)
    } else {
      let body = await responseText(resp)
      Error(`HTTP ${Belt.Int.toString(responseStatus(resp))}: ${body}`)
    }
  } catch {
  | exn => Error(Js.String2.make(exn))
  }
}

let fetchKnots = async (~filters: Types.filters=Types.emptyFilters): result<
  Types.knotListResponse,
  string,
> => {
  let params = []

  switch filters.crossingNumber {
  | Some(cn) =>
    let _ = Js.Array2.push(params, "crossing_number=" ++ Belt.Int.toString(cn))
  | None => ()
  }

  switch filters.genus {
  | Some(g) =>
    let _ = Js.Array2.push(params, "genus=" ++ Belt.Int.toString(g))
  | None => ()
  }

  if filters.nameSearch != "" {
    let _ = Js.Array2.push(
      params,
      "name=" ++ Js.Global.encodeURIComponent(filters.nameSearch),
    )
  }

  let queryStr = if Belt.Array.length(params) > 0 {
    "?" ++ Js.Array2.joinWith(params, "&")
  } else {
    ""
  }

  let result = await fetchJson(baseUrl ++ "/api/knots" ++ queryStr)
  switch result {
  | Ok(json) => Decoders.decodeKnotList(json)
  | Error(e) => Error(e)
  }
}

let fetchKnot = async (name: string): result<Types.knot, string> => {
  let result = await fetchJson(
    baseUrl ++ "/api/knots/" ++ Js.Global.encodeURIComponent(name),
  )
  switch result {
  | Ok(json) => Decoders.decodeKnot(json)
  | Error(e) => Error(e)
  }
}

let fetchStatistics = async (): result<Types.statistics, string> => {
  let result = await fetchJson(baseUrl ++ "/api/statistics")
  switch result {
  | Ok(json) => Decoders.decodeStatistics(json)
  | Error(e) => Error(e)
  }
}
