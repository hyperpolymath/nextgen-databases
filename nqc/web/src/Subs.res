// SPDX-License-Identifier: PMPL-1.0-or-later
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath)

@@ocaml.doc("
Subscriptions for the NQC Web UI.
Currently no active subscriptions are needed — URL change detection
is handled via `Tea_Router.listen` in the init command (see App.res).
The popstate listener is set up once and persists for the app lifetime.

This module exists as a placeholder for future subscriptions such as:
- WebSocket connections to database engines for live result streaming
- Periodic health-check polling
- Keyboard shortcut subscriptions
")

// ============================================================================
// Subscriptions function — required by the TEA app specification
// ============================================================================

@ocaml.doc("
Return the active subscriptions for the given model state.
Currently returns `Tea_Sub.none` as all event sources are
wired up via one-time init commands.
")
let subscriptions = (_model: Model.t): Tea_Sub.t<Msg.t> => {
  Tea_Sub.none
}
