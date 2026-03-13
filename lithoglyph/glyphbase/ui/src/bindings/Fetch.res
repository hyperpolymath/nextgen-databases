// SPDX-License-Identifier: PMPL-1.0-or-later
// Fetch API bindings for ReScript

type response

@val external fetch: (string, 'options) => promise<response> = "fetch"

module Response = {
  @get external ok: response => bool = "ok"
  @get external status: response => int = "status"
  @get external statusText: response => string = "statusText"
  @send external json: response => promise<JSON.t> = "json"
  @send external text: response => promise<string> = "text"
}
