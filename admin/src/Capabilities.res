// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)

/// Capabilities -- Gossamer capability token management for VeriSimDB Admin.
///
/// VeriSimDB Admin requires three capabilities:
///   1 = network    -- Required for all VeriSimDB API calls (Rust core + Elixir layer)
///   2 = filesystem -- Required for exporting query results and octad data
///   5 = clipboard  -- Required for copying VQL queries to clipboard
///
/// Flow:
///   1. App starts with NO capabilities (sandbox by default)
///   2. User sees the capability grant panel
///   3. User clicks "Grant Network" -> Gossamer shows consent dialog
///   4. Runtime returns a token (float) valid for TTL seconds
///   5. All subsequent API calls include the token in the IPC payload
///   6. Token expires -> app must re-request or operations fail

/// Capability kind identifiers matching the Gossamer runtime's internal enum.
/// These map to the `kind` field in `__gossamer_cap_grant` requests.
module Kind = {
  /// Network access -- HTTP to VeriSimDB Rust core (port 8080) and Elixir
  /// orchestration layer (port 4080).
  let network = 1

  /// Filesystem access -- exporting query results, octad snapshots, and
  /// drift reports to disk.
  let filesystem = 2

  /// Clipboard access -- copying VQL queries and entity IDs to the system
  /// clipboard.
  let clipboard = 5

  /// Human-readable name for a capability kind.
  let toString = (kind: int): string => {
    switch kind {
    | 1 => "network"
    | 2 => "filesystem"
    | 5 => "clipboard"
    | k => `unknown(${Int.toString(k)})`
    }
  }

  /// Description of why VeriSimDB Admin needs this capability.
  let description = (kind: int): string => {
    switch kind {
    | 1 => "Connect to VeriSimDB Rust core and Elixir orchestration layer to manage octads, run VQL queries, and monitor drift."
    | 2 => "Export query results, octad snapshots, and drift reports to local files."
    | 5 => "Copy VQL queries and entity IDs to the system clipboard."
    | _ => "Unknown capability."
    }
  }
}

/// Request a capability token from the Gossamer runtime.
///
/// This triggers Gossamer's consent dialog. The user must approve the
/// request before the runtime issues a token. Returns a promise that
/// resolves to the token value (float) on success.
///
/// @param kind - The capability kind (use Kind.network, Kind.filesystem, etc.)
let requestCapability = (kind: int): promise<float> => {
  RuntimeBridge.invoke("__gossamer_cap_grant", {"kind": kind})
}

/// Request network capability -- needed for ALL VeriSimDB API calls.
///
/// Without this token, no HTTP requests can be made to the Rust core
/// or Elixir orchestration layer. This is the first capability users
/// should grant.
let requestNetworkAccess = (): promise<float> => {
  requestCapability(Kind.network)
}

/// Request filesystem capability -- needed for exporting data.
///
/// Export operations write query results and octad snapshots to local
/// files in user-chosen directories.
let requestFilesystemAccess = (): promise<float> => {
  requestCapability(Kind.filesystem)
}

/// Request clipboard capability -- needed for VQL copy operations.
///
/// The VQL console allows copying queries and results to the clipboard
/// for use in other tools.
let requestClipboardAccess = (): promise<float> => {
  requestCapability(Kind.clipboard)
}

/// Revoke a previously granted capability.
///
/// This is the counterpart to requestCapability. After revocation, any
/// IPC calls using the old token will fail. The app should update its
/// UI to reflect the reduced permissions.
///
/// @param kind - The capability kind to revoke
let revokeCapability = (kind: int): promise<unit> => {
  RuntimeBridge.invoke("__gossamer_cap_revoke", {"kind": kind})
}

/// Check whether a token is still valid.
///
/// Tokens expire after the TTL defined in gossamer.conf.json (default:
/// 3600 seconds). This lets the app proactively check and re-request
/// before a critical operation fails.
///
/// @param token - The capability token to validate
let validateToken = (token: float): promise<bool> => {
  RuntimeBridge.invoke("__gossamer_cap_validate", {"token": token})
}

/// Copy text to the system clipboard (requires clipboard capability).
///
/// @param text  - The text to copy
/// @param token - Valid clipboard capability token
let copyToClipboard = (text: string, token: float): promise<unit> => {
  RuntimeBridge.invokeWithToken(
    "__gossamer_clipboard_write",
    {"text": text},
    token,
  )
}
