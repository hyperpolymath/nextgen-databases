// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)

/// RuntimeBridge — Unified IPC bridge for Lith Studio.
///
/// Dispatches `invoke` calls to the Gossamer backend via
/// `window.__gossamer_invoke`. The Tauri codepath has been removed;
/// Gossamer is now the only desktop runtime.
///
/// Priority order:
///   1. Gossamer (`window.__gossamer_invoke`)  — primary runtime
///   2. Browser  (rejects with error)           — development fallback

// ---------------------------------------------------------------------------
// Raw external bindings
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

// ---------------------------------------------------------------------------
// Runtime detection
// ---------------------------------------------------------------------------

/// The runtime currently in use.
type runtime =
  | Gossamer
  | BrowserOnly

/// Detect and return the current runtime.
let detectRuntime = (): runtime => {
  if isGossamerRuntime() {
    Gossamer
  } else {
    BrowserOnly
  }
}

// ---------------------------------------------------------------------------
// Unified invoke — detects runtime and dispatches
// ---------------------------------------------------------------------------

/// Invoke a backend command through the Gossamer runtime.
///
/// - On Gossamer: calls `window.__gossamer_invoke(cmd, args)`
/// - On browser:  rejects with a descriptive error
///
/// This is the primary function all command modules should use.
let invoke = (cmd: string, args: 'a): promise<'b> => {
  if isGossamerRuntime() {
    gossamerInvoke(cmd, args)
  } else {
    Promise.reject(
      JsError.throwWithMessage(
        `No desktop runtime — "${cmd}" requires Gossamer`,
      ),
    )
  }
}

/// Check whether the Gossamer desktop runtime is available.
let hasDesktopRuntime = (): bool => {
  isGossamerRuntime()
}

/// Get a human-readable name for the current runtime.
let runtimeName = (): string => {
  switch detectRuntime() {
  | Gossamer => "Gossamer"
  | BrowserOnly => "Browser"
  }
}
