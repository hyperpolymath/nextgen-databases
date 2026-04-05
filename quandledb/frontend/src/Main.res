// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

// Entry point — mounts QuandleDB app to #root

switch ReactDOM.querySelector("#root") {
| Some(root) => {
    let rootElement = ReactDOM.Client.createRoot(root)
    rootElement->ReactDOM.Client.Root.render(<App />)
  }
| None => Js.Console.error("QuandleDB: could not find #root element")
}
