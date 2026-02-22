// SPDX-License-Identifier: PMPL-1.0-or-later
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath)

@@ocaml.doc("
Entry point for the NQC Web UI.
Mounts the TEA application into the `#root` DOM element defined in `index.html`.
Uses React 19's `createRoot` API for concurrent rendering.

This file is the `<script type='module'>` target in `index.html`:
  `<script type='module' src='./src/Index.res.mjs'></script>`
")

// ============================================================================
// DOM mounting
// ============================================================================

// Binding to document.getElementById — returns nullable DOM element
@val @scope("document")
external getElementById: string => Nullable.t<Dom.element> = "getElementById"

// Find the root element and mount the application
switch getElementById("root")->Nullable.toOption {
| Some(rootElement) => {
    let root = ReactDOM.Client.createRoot(rootElement)
    root->ReactDOM.Client.Root.render(<App />)
  }
| None =>
  // This should never happen unless index.html is malformed
  Console.error("NQC Web UI: Could not find #root element. Check index.html.")
}
