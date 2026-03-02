// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// VeriSimDB ReScript Client — Search operations.
//
// This module provides multi-modal search capabilities against VeriSimDB,
// including full-text search, vector similarity search, spatial radius and
// bounding-box queries, nearest-neighbour lookups, and relationship traversal.

// --------------------------------------------------------------------------
// Search parameter types
// --------------------------------------------------------------------------

/** Parameters for a full-text search query. */
type textSearchParams = {
  query: string,
  modalities: array<VeriSimTypes.modality>,
  limit: int,
  offset: int,
}

/** Parameters for a vector similarity search. */
type vectorSearchParams = {
  vector: array<float>,
  model: string,
  topK: int,
  threshold: float,
}

/** Parameters for a spatial radius search (point + distance). */
type spatialRadiusParams = {
  latitude: float,
  longitude: float,
  radiusKm: float,
  limit: int,
}

/** Parameters for a spatial bounding-box search. */
type spatialBoundsParams = {
  minLat: float,
  minLon: float,
  maxLat: float,
  maxLon: float,
  limit: int,
}

/** Parameters for a nearest-neighbour search by hexad ID. */
type nearestParams = {
  hexadId: string,
  topK: int,
  modality: VeriSimTypes.modality,
}

/** Parameters for a relationship traversal search. */
type relatedParams = {
  hexadId: string,
  relType: option<string>,
  depth: int,
  limit: int,
}

// --------------------------------------------------------------------------
// Search functions
// --------------------------------------------------------------------------

/** Perform a full-text search across hexad content.
 *
 * @param client The authenticated client.
 * @param params Text search parameters including query string and filters.
 * @returns A list of search results ranked by relevance, or an error.
 */
let text = async (
  client: VeriSimClient.t,
  params: textSearchParams,
): result<array<VeriSimTypes.searchResult>, VeriSimError.t> => {
  try {
    let body = params->Obj.magic->JSON.stringify->JSON.parseExn
    let resp = await VeriSimClient.doPost(client, "/api/v1/search/text", body)
    if resp.ok {
      let json = await VeriSimClient.jsonBody(resp)
      Ok(json->Obj.magic)
    } else {
      Error(VeriSimError.fromStatus(resp.status))
    }
  } catch {
  | _ => Error(VeriSimError.ConnectionError("Text search failed"))
  }
}

/** Perform a vector similarity search using a query embedding.
 *
 * @param client The authenticated client.
 * @param params Vector search parameters including the query vector.
 * @returns A list of search results ranked by cosine similarity, or an error.
 */
let vector = async (
  client: VeriSimClient.t,
  params: vectorSearchParams,
): result<array<VeriSimTypes.searchResult>, VeriSimError.t> => {
  try {
    let body = params->Obj.magic->JSON.stringify->JSON.parseExn
    let resp = await VeriSimClient.doPost(client, "/api/v1/search/vector", body)
    if resp.ok {
      let json = await VeriSimClient.jsonBody(resp)
      Ok(json->Obj.magic)
    } else {
      Error(VeriSimError.fromStatus(resp.status))
    }
  } catch {
  | _ => Error(VeriSimError.ConnectionError("Vector search failed"))
  }
}

/** Find hexads within a given radius of a geographic point.
 *
 * @param client The authenticated client.
 * @param params Latitude, longitude, and radius in kilometres.
 * @returns A list of search results within the radius, or an error.
 */
let spatialRadius = async (
  client: VeriSimClient.t,
  params: spatialRadiusParams,
): result<array<VeriSimTypes.searchResult>, VeriSimError.t> => {
  try {
    let body = params->Obj.magic->JSON.stringify->JSON.parseExn
    let resp = await VeriSimClient.doPost(client, "/api/v1/search/spatial/radius", body)
    if resp.ok {
      let json = await VeriSimClient.jsonBody(resp)
      Ok(json->Obj.magic)
    } else {
      Error(VeriSimError.fromStatus(resp.status))
    }
  } catch {
  | _ => Error(VeriSimError.ConnectionError("Spatial radius search failed"))
  }
}

/** Find hexads within a rectangular bounding box.
 *
 * @param client The authenticated client.
 * @param params The bounding box defined by min/max latitude and longitude.
 * @returns A list of search results within the bounds, or an error.
 */
let spatialBounds = async (
  client: VeriSimClient.t,
  params: spatialBoundsParams,
): result<array<VeriSimTypes.searchResult>, VeriSimError.t> => {
  try {
    let body = params->Obj.magic->JSON.stringify->JSON.parseExn
    let resp = await VeriSimClient.doPost(client, "/api/v1/search/spatial/bounds", body)
    if resp.ok {
      let json = await VeriSimClient.jsonBody(resp)
      Ok(json->Obj.magic)
    } else {
      Error(VeriSimError.fromStatus(resp.status))
    }
  } catch {
  | _ => Error(VeriSimError.ConnectionError("Spatial bounds search failed"))
  }
}

/** Find the nearest neighbours of a given hexad.
 *
 * @param client The authenticated client.
 * @param params The hexad ID and number of neighbours to return.
 * @returns A list of search results ordered by proximity, or an error.
 */
let nearest = async (
  client: VeriSimClient.t,
  params: nearestParams,
): result<array<VeriSimTypes.searchResult>, VeriSimError.t> => {
  try {
    let body = params->Obj.magic->JSON.stringify->JSON.parseExn
    let resp = await VeriSimClient.doPost(client, "/api/v1/search/nearest", body)
    if resp.ok {
      let json = await VeriSimClient.jsonBody(resp)
      Ok(json->Obj.magic)
    } else {
      Error(VeriSimError.fromStatus(resp.status))
    }
  } catch {
  | _ => Error(VeriSimError.ConnectionError("Nearest search failed"))
  }
}

/** Traverse relationships from a given hexad.
 *
 * @param client The authenticated client.
 * @param params The source hexad ID, optional relationship type filter, and depth.
 * @returns A list of search results connected by relationships, or an error.
 */
let related = async (
  client: VeriSimClient.t,
  params: relatedParams,
): result<array<VeriSimTypes.searchResult>, VeriSimError.t> => {
  try {
    let body = params->Obj.magic->JSON.stringify->JSON.parseExn
    let resp = await VeriSimClient.doPost(client, "/api/v1/search/related", body)
    if resp.ok {
      let json = await VeriSimClient.jsonBody(resp)
      Ok(json->Obj.magic)
    } else {
      Error(VeriSimError.fromStatus(resp.status))
    }
  } catch {
  | _ => Error(VeriSimError.ConnectionError("Related search failed"))
  }
}
