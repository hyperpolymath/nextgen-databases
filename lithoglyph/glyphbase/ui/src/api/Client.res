// SPDX-License-Identifier: PMPL-1.0-or-later
// API client for Glyphbase server

let baseUrl = "http://localhost:8080/api"

type apiError = {
  code: string,
  message: string,
}

type apiResult<'a> = result<'a, apiError>

// Generic fetch wrapper
let fetchJson = async (~method: string, ~path: string, ~body: option<JSON.t>=?, ()): result<
  JSON.t,
  apiError,
> => {
  let headers = Dict.fromArray([
    ("Content-Type", "application/json"),
    ("Accept", "application/json"),
  ])

  let init = {
    "method": method,
    "headers": headers,
    "body": body->Option.map(j => JSON.stringify(j))->Nullable.fromOption,
  }

  try {
    let response = await Fetch.fetch(baseUrl ++ path, init)
    let json = await Fetch.Response.json(response)

    if Fetch.Response.ok(response) {
      Ok(json)
    } else {
      Error({
        code: "API_ERROR",
        message: "Request failed",
      })
    }
  } catch {
  | _ =>
    Error({
      code: "NETWORK_ERROR",
      message: "Failed to connect to server",
    })
  }
}

// Base CRUD
let getBases = async () => {
  await fetchJson(~method="GET", ~path="/bases", ())
}

let getBase = async (id: string) => {
  await fetchJson(~method="GET", ~path="/bases/" ++ id, ())
}

let createBase = async (name: string, description: option<string>) => {
  let body = Dict.fromArray([
    ("name", JSON.Encode.string(name)),
    ("description", description->Option.mapOr(JSON.Encode.null, JSON.Encode.string)),
  ])
  await fetchJson(~method="POST", ~path="/bases", ~body=JSON.Encode.object(body), ())
}

// Table CRUD
let getTables = async (baseId: string) => {
  await fetchJson(~method="GET", ~path="/bases/" ++ baseId ++ "/tables", ())
}

let createTable = async (baseId: string, name: string) => {
  let body = Dict.fromArray([("name", JSON.Encode.string(name))])
  await fetchJson(
    ~method="POST",
    ~path="/bases/" ++ baseId ++ "/tables",
    ~body=JSON.Encode.object(body),
    (),
  )
}

// Row CRUD
@val external encodeURIComponent: string => string = "encodeURIComponent"

let getRows = async (baseId: string, tableId: string, ~filter: option<string>=?, ()) => {
  let path = "/bases/" ++ baseId ++ "/tables/" ++ tableId ++ "/rows"
  let queryPath = switch filter {
  | Some(f) => path ++ "?filter=" ++ encodeURIComponent(f)
  | None => path
  }
  await fetchJson(~method="GET", ~path=queryPath, ())
}

let createRow = async (baseId: string, tableId: string, rowId: string, cells: Dict.t<JSON.t>) => {
  let body = Dict.fromArray([
    ("id", JSON.Encode.string(rowId)),
    ("cells", JSON.Encode.object(cells)),
  ])
  await fetchJson(
    ~method="POST",
    ~path="/bases/" ++ baseId ++ "/tables/" ++ tableId ++ "/rows",
    ~body=JSON.Encode.object(body),
    (),
  )
}

let updateCell = async (
  baseId: string,
  tableId: string,
  rowId: string,
  fieldId: string,
  value: JSON.t,
  ~rationale: option<string>=?,
  (),
) => {
  let body = Dict.fromArray([
    ("value", value),
    ("rationale", rationale->Option.mapOr(JSON.Encode.null, JSON.Encode.string)),
  ])
  await fetchJson(
    ~method="PATCH",
    ~path="/bases/" ++ baseId ++ "/tables/" ++ tableId ++ "/rows/" ++ rowId ++ "/cells/" ++ fieldId,
    ~body=JSON.Encode.object(body),
    (),
  )
}

let deleteRow = async (baseId: string, tableId: string, rowId: string) => {
  await fetchJson(
    ~method="DELETE",
    ~path="/bases/" ++ baseId ++ "/tables/" ++ tableId ++ "/rows/" ++ rowId,
    (),
  )
}

// Provenance
let getCellProvenance = async (baseId: string, tableId: string, rowId: string, fieldId: string) => {
  await fetchJson(
    ~method="GET",
    ~path="/bases/" ++
    baseId ++
    "/tables/" ++
    tableId ++
    "/rows/" ++
    rowId ++
    "/cells/" ++
    fieldId ++ "/provenance",
    (),
  )
}
