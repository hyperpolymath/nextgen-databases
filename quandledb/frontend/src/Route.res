// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

// Route definitions for QuandleDB SPA

type t =
  | Dashboard
  | KnotList
  | KnotDetail(string)
  | Query
  | NotFound

let fromPath = (path: string): t => {
  let segments =
    path
    ->Js.String2.split("/")
    ->Belt.Array.keep(s => s != "")

  switch segments {
  | [] => Dashboard
  | ["knots"] => KnotList
  | ["knots", name] => KnotDetail(name)
  | ["query"] => Query
  | _ => NotFound
  }
}

let toPath = (route: t): string =>
  switch route {
  | Dashboard => "/"
  | KnotList => "/knots"
  | KnotDetail(name) => "/knots/" ++ name
  | Query => "/query"
  | NotFound => "/404"
  }

let fromUrl = (): t => {
  let path = switch %external(window) {
  | Some(_) => {
      let location: {"pathname": string} = %raw(`window.location`)
      location["pathname"]
    }
  | None => "/"
  }
  fromPath(path)
}
