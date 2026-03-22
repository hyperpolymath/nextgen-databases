// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)

/// RuntimeBridge — Unified IPC bridge for Lith Studio.
///
/// Detects the available runtime (Gossamer, Tauri, or browser-only) and
/// dispatches `invoke` calls to the appropriate backend. This allows all
/// command modules to use a single import instead of binding directly
/// to `@tauri-apps/api/core`.
///
/// Priority order:
///   1. Gossamer (`window.__gossamer_invoke`)  — own stack, preferred
///   2. Tauri    (`window.__TAURI_INTERNALS__`) — legacy, transition
///   3. Browser  (direct HTTP fetch)            — development fallback
///
/// Migration path: replace
///   `Tauri.invoke("cmd", args)`
/// with
///   `RuntimeBridge.invoke("cmd", args)`

// ---------------------------------------------------------------------------
// Raw external bindings — exactly one of these will be available at runtime
// ---------------------------------------------------------------------------

/// Gossamer IPC: injected by gossamer_channel_open() into the webview.
/// Signature: (commandName: string, payload: object) => Promise<any>
%%raw(`
function isGossamerRuntime() {
  return typeof window !== 'undefined'
    && typeof window.__gossamer_invoke === 'function';
}
`)
@val external isGossamerRuntime: unit => bool = "isGossamerRuntime"

%%raw(`
function gossamerInvoke(cmd, args) {
  return window.__gossamer_invoke(cmd, args);
}
`)
@val external gossamerInvoke: (string, 'a) => promise<'b> = "gossamerInvoke"

/// Tauri IPC: injected by the Tauri runtime into the webview.
%%raw(`
function isTauriRuntime() {
  return typeof window !== 'undefined'
    && window.__TAURI_INTERNALS__ != null
    && !window.__TAURI_INTERNALS__.__BROWSER_SHIM__;
}
`)
@val external isTauriRuntime: unit => bool = "isTauriRuntime"

@module("@tauri-apps/api/core")
external tauriInvoke: (string, 'a) => promise<'b> = "invoke"

// ---------------------------------------------------------------------------
// Unified invoke — detects runtime and dispatches
// ---------------------------------------------------------------------------

/// The runtime currently in use. Cached after first detection for performance.
type runtime =
  | Gossamer
  | Tauri
  | BrowserOnly

%%raw(`
var _detectedRuntime = null;
function detectRuntime() {
  if (_detectedRuntime !== null) return _detectedRuntime;
  if (typeof window !== 'undefined' && typeof window.__gossamer_invoke === 'function') {
    _detectedRuntime = 'gossamer';
  } else if (typeof window !== 'undefined' && window.__TAURI_INTERNALS__ != null && !window.__TAURI_INTERNALS__.__BROWSER_SHIM__) {
    _detectedRuntime = 'tauri';
  } else {
    _detectedRuntime = 'browser';
  }
  return _detectedRuntime;
}
`)
@val external detectRuntimeRaw: unit => string = "detectRuntime"

/// Detect and return the current runtime.
let detectRuntime = (): runtime => {
  switch detectRuntimeRaw() {
  | "gossamer" => Gossamer
  | "tauri" => Tauri
  | _ => BrowserOnly
  }
}

/// Invoke a backend command through whatever runtime is available.
///
/// - On Gossamer: calls `window.__gossamer_invoke(cmd, args)`
/// - On Tauri:    calls `window.__TAURI_INTERNALS__.invoke(cmd, args)`
/// - On browser:  rejects with a descriptive error
///
/// This is the primary function all command modules should use.
let invoke = (cmd: string, args: 'a): promise<'b> => {
  if isGossamerRuntime() {
    gossamerInvoke(cmd, args)
  } else if isTauriRuntime() {
    tauriInvoke(cmd, args)
  } else {
    Promise.reject(
      JsError.throwWithMessage(
        `No desktop runtime — "${cmd}" requires Gossamer or Tauri`,
      ),
    )
  }
}

/// Check whether any desktop runtime is available.
let hasDesktopRuntime = (): bool => {
  isGossamerRuntime() || isTauriRuntime()
}

/// Get a human-readable name for the current runtime.
let runtimeName = (): string => {
  switch detectRuntime() {
  | Gossamer => "Gossamer"
  | Tauri => "Tauri"
  | BrowserOnly => "Browser"
  }
}
