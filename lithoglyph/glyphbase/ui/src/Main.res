// SPDX-License-Identifier: PMPL-1.0-or-later
// Main entry point with formally verified DOM mounting

// Use SafeDOM for high-assurance mount operations
// Provides compile-time guarantees: no null pointers, validated selectors, type-safe operations

module SafeDOMMounter = {
  // Safe React root mounting with error handling
  let mountReactRoot = (selector: string, ~onError: string => unit): unit => {
    SafeDOM.mountWhenReady(
      selector,
      "", // Empty HTML - we'll use ReactDOM to render
      ~onSuccess=element => {
        // Element proven to exist - mount React root
        let root = ReactDOM.Client.createRoot(element)
        ReactDOM.Client.Root.render(root, <App />)
      },
      ~onError=err => {
        onError(err)
      },
    )
  }
}

// Mount with formally verified selector
SafeDOMMounter.mountReactRoot("#root", ~onError=err => {
  Console.error("Failed to mount Glyphbase:")
  Console.error(err)
})
