// SPDX-License-Identifier: PMPL-1.0-or-later
// Calendar Store - State management for Calendar View

open Types

// Atoms for calendar state
let currentDateAtom: Jotai.atom<Date.t> = Jotai.atom(Date.make())

type viewMode = Month | Week | Day

let viewModeAtom: Jotai.atom<viewMode> = Jotai.atom(Month)

// Helper functions for date navigation
module Navigation = {
  let goToPreviousMonth = (currentDate: Date.t): Date.t => {
    let year = currentDate->Date.getFullYear
    let month = currentDate->Date.getMonth
    %raw(`new Date(year, month - 1, 1)`)
  }

  let goToNextMonth = (currentDate: Date.t): Date.t => {
    let year = currentDate->Date.getFullYear
    let month = currentDate->Date.getMonth
    %raw(`new Date(year, month + 1, 1)`)
  }

  let goToPreviousWeek = (currentDate: Date.t): Date.t => {
    Date.fromTime(currentDate->Date.getTime -. 7.0 *. 86400000.0)
  }

  let goToNextWeek = (currentDate: Date.t): Date.t => {
    Date.fromTime(currentDate->Date.getTime +. 7.0 *. 86400000.0)
  }

  let goToPreviousDay = (currentDate: Date.t): Date.t => {
    Date.fromTime(currentDate->Date.getTime -. 86400000.0)
  }

  let goToNextDay = (currentDate: Date.t): Date.t => {
    Date.fromTime(currentDate->Date.getTime +. 86400000.0)
  }

  let goToToday = (): Date.t => {
    Date.make()
  }
}

// API integration helpers
module API = {
  // Update event date via API
  let updateEventDate = async (
    tableId: string,
    rowId: string,
    dateFieldId: string,
    newDate: Date.t,
  ): result<unit, string> => {
    try {
      // Format date as ISO string
      let dateStr = newDate->Date.toISOString

      // Call API to update row - build JSON dynamically since dateFieldId is a variable
      let cells = Dict.make()
      cells->Dict.set(
        dateFieldId,
        JSON.Encode.object(Dict.fromArray([("value", JSON.Encode.string(dateStr))])),
      )

      let bodyJson = JSON.stringifyAny({
        "cells": cells,
      })->Option.getOr("{}")

      let response = await Fetch.fetch(
        `/api/tables/${tableId}/rows/${rowId}`,
        %raw(`{
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: bodyJson
        }`),
      )

      if response->Fetch.Response.ok {
        Ok()
      } else {
        Error("Failed to update event date")
      }
    } catch {
    | error => Error(`API error: ${error->JSON.stringifyAny->Option.getOr("Unknown error")}`)
    }
  }

  // Create new event via API
  let createEvent = async (
    tableId: string,
    dateFieldId: string,
    date: Date.t,
    title: string,
  ): result<string, string> => {
    try {
      let dateStr = date->Date.toISOString

      // Build JSON payload using Dict
      let cells = Dict.make()
      cells->Dict.set(
        dateFieldId,
        JSON.Encode.object(Dict.fromArray([("value", JSON.Encode.string(dateStr))])),
      )
      cells->Dict.set(
        "title",
        JSON.Encode.object(Dict.fromArray([("value", JSON.Encode.string(title))])),
      )

      let payload = JSON.Encode.object(Dict.fromArray([("cells", JSON.Encode.object(cells))]))
      let bodyJson = JSON.stringify(payload)

      let response = await Fetch.fetch(
        `/api/tables/${tableId}/rows`,
        %raw(`{
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: bodyJson
        }`),
      )

      let result = if response->Fetch.Response.ok {
        let json = await response->Fetch.Response.json
        switch json->JSON.Decode.object->Option.flatMap(obj => obj->Dict.get("id")) {
        | Some(id) =>
          switch id->JSON.Decode.string {
          | Some(rowId) => Ok(rowId)
          | None => Error("Invalid row ID in response")
          }
        | None => Error("No row ID in response")
        }
      } else {
        Error("Failed to create event")
      }
      result
    } catch {
    | error => Error(`API error: ${error->JSON.stringifyAny->Option.getOr("Unknown error")}`)
    }
  }

  // Delete event via API
  let deleteEvent = async (tableId: string, rowId: string): result<unit, string> => {
    try {
      let response = await Fetch.fetch(
        `/api/tables/${tableId}/rows/${rowId}`,
        %raw(`{ method: "DELETE" }`),
      )

      if response->Fetch.Response.ok {
        Ok()
      } else {
        Error("Failed to delete event")
      }
    } catch {
    | error => Error(`API error: ${error->JSON.stringifyAny->Option.getOr("Unknown error")}`)
    }
  }
}
