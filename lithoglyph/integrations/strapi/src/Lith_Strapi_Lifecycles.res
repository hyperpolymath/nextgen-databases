// SPDX-License-Identifier: PMPL-1.0-or-later

/**
 * Lith Strapi Lifecycle Hooks
 *
 * Hooks for Strapi content lifecycle events
 */

open Lith_Strapi_Types
open Lith_Strapi_Service

/** Lifecycle event data */
type lifecycleEvent = {
  model: modelInfo,
  result: option<Js.Json.t>,
  params: lifecycleParams,
}
and modelInfo = {
  uid: string,
  singularName: string,
  pluralName: string,
}
and lifecycleParams = {
  data: option<Js.Json.t>,
  where: option<Js.Json.t>,
}

/** After create hook */
let afterCreate = async (event: lifecycleEvent): unit => {
  let modelName = event.model.singularName

  switch event.result {
  | Some(data) =>
    let _ = await syncCreate(modelName, data)
    ()
  | None => ()
  }
}

/** After update hook */
let afterUpdate = async (event: lifecycleEvent): unit => {
  let modelName = event.model.singularName

  switch event.result {
  | Some(data) =>
    // Extract ID from result
    let id = switch Js.Json.decodeObject(data) {
    | Some(obj) =>
      switch Js.Dict.get(obj, "id") {
      | Some(idJson) =>
        switch Js.Json.decodeNumber(idJson) {
        | Some(n) => Int.toString(Float.toInt(n))
        | None =>
          switch Js.Json.decodeString(idJson) {
          | Some(s) => s
          | None => ""
          }
        }
      | None => ""
      }
    | None => ""
    }

    if id !== "" {
      let _ = await syncUpdate(modelName, data, id)
      ()
    }
  | None => ()
  }
}

/** After delete hook */
let afterDelete = async (event: lifecycleEvent): unit => {
  let modelName = event.model.singularName

  switch event.result {
  | Some(data) =>
    // Extract ID from result
    let id = switch Js.Json.decodeObject(data) {
    | Some(obj) =>
      switch Js.Dict.get(obj, "id") {
      | Some(idJson) =>
        switch Js.Json.decodeNumber(idJson) {
        | Some(n) => Int.toString(Float.toInt(n))
        | None =>
          switch Js.Json.decodeString(idJson) {
          | Some(s) => s
          | None => ""
          }
        }
      | None => ""
      }
    | None => ""
    }

    if id !== "" {
      let _ = await syncDelete(modelName, id)
      ()
    }
  | None => ()
  }
}

/** After create many hook */
let afterCreateMany = async (event: lifecycleEvent): unit => {
  let modelName = event.model.singularName

  switch event.result {
  | Some(data) =>
    // Handle array of created items
    switch Js.Json.decodeArray(data) {
    | Some(items) =>
      let _ = await Promise.all(
        items->Array.map(item => syncCreate(modelName, item))
      )
      ()
    | None => ()
    }
  | None => ()
  }
}

/** After update many hook */
let afterUpdateMany = async (_event: lifecycleEvent): unit => {
  // Update many requires fetching the updated records
  // This is a simplified implementation
  ()
}

/** After delete many hook */
let afterDeleteMany = async (_event: lifecycleEvent): unit => {
  // Delete many requires knowing which records were deleted
  // This is a simplified implementation
  ()
}

/** Export lifecycle hooks */
let lifecycles = {
  "afterCreate": afterCreate,
  "afterUpdate": afterUpdate,
  "afterDelete": afterDelete,
  "afterCreateMany": afterCreateMany,
  "afterUpdateMany": afterUpdateMany,
  "afterDeleteMany": afterDeleteMany,
}
