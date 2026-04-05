// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

// Domain types for QuandleDB frontend

type remoteData<'a, 'e> =
  | NotAsked
  | Loading
  | Success('a)
  | Failure('e)

type knot = {
  id: string,
  name: string,
  gaussCode: array<int>,
  crossingNumber: int,
  writhe: int,
  genus: option<int>,
  seifertCircleCount: option<int>,
  jonesPolynomial: option<string>,
  jonesDisplay: option<string>,
  metadata: Js.Dict.t<string>,
  createdAt: string,
  updatedAt: string,
}

type knotListResponse = {
  knots: array<knot>,
  count: int,
  limit: int,
  offset: int,
}

type crossingDistribution = Js.Dict.t<int>
type genusDistribution = Js.Dict.t<int>

type statistics = {
  totalKnots: int,
  minCrossings: option<int>,
  maxCrossings: option<int>,
  crossingDistribution: crossingDistribution,
  genusDistribution: genusDistribution,
  schemaVersion: int,
}

type filters = {
  crossingNumber: option<int>,
  genus: option<int>,
  nameSearch: string,
}

let emptyFilters: filters = {
  crossingNumber: None,
  genus: None,
  nameSearch: "",
}
