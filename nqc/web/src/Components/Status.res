// SPDX-License-Identifier: PMPL-1.0-or-later
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath)

@@ocaml.doc("
Connection status indicator component.
Renders a coloured dot + label reflecting the health-check state
of a database engine.  Used in both the Picker cards and the Header.

Colour mapping:
  - Grey    (default)    → Disconnected / unknown
  - Orange  (pulsing)    → Connecting / health check in progress
  - Green                → Connected / healthy
  - Red                  → Error / unreachable

CSS classes are defined in `index.html` under `.nqc-status*`.
")

// ============================================================================
// Component
// ============================================================================

@ocaml.doc("
Render a status indicator given a connection state.
`showLabel` controls whether the text label is shown alongside the dot
(e.g. 'Connected', 'Error: timeout').  On cards we show just the dot;
in the header we show dot + label.
")
let make = (~state: Msg.connectionState, ~showLabel: bool) => {
  let (dotClass, label) = switch state {
  | Msg.Disconnected => ("nqc-status__dot", "Disconnected")
  | Msg.Connecting => ("nqc-status__dot nqc-status__dot--connecting", "Connecting...")
  | Msg.Connected => ("nqc-status__dot nqc-status__dot--connected", "Connected")
  | Msg.ConnectionError(msg) => ("nqc-status__dot nqc-status__dot--error", "Error: " ++ msg)
  }

  <span className="nqc-status">
    <span className={dotClass} />
    {if showLabel {
      <span> {React.string(label)} </span>
    } else {
      React.null
    }}
  </span>
}
