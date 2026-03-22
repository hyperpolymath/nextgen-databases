// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)

/// App -- TEA (The Elm Architecture) entry point for VeriSimDB Admin.
///
/// This is the SECOND application built natively for the Gossamer webview
/// shell (after Burble Admin). It showcases Gossamer's capability token
/// system applied to a database administration context.
///
/// Architecture:
///   - Model.res       -- State types (octads, VQL, drift, telemetry, caps)
///   - Msg.res         -- Message types
///   - App.res         -- init, update, view (this file)
///   - VeriSimDbCmd    -- IPC commands to the VeriSimDB backend
///   - Capabilities    -- Gossamer capability token management
///   - RuntimeBridge   -- Gossamer-native IPC bridge
///
/// Panel layout:
///   +---------------------------------------------+
///   | Header: status, runtime, health, caps       |
///   +----------+----------------------------------+
///   | VQL Console (top bar, full width)            |
///   | [input area]         [results]               |
///   +----------+----------------------------------+
///   | Sidebar  | Entity Detail (main)              |
///   | Octad    |   [modality tabs]                 |
///   | Browser  |   [content per modality]          |
///   | (paged)  |   [drift indicator + normalise]   |
///   +----------+----------------------------------+
///   | Telemetry Dashboard (bottom bar)             |
///   +---------------------------------------------+

// ---------------------------------------------------------------------------
// TEA command helpers
// ---------------------------------------------------------------------------

/// Wrap an async operation as a TEA command.
/// Runs the promise and dispatches the resulting message.
let cmdFromPromise = (
  promiseFn: unit => promise<string>,
  onOk: string => Msg.msg,
  onErr: string => Msg.msg,
): Tea_Cmd.t<Msg.msg> => {
  Tea_Cmd.call(dispatch => {
    promiseFn()
    ->Promise.thenResolve(result => dispatch(onOk(result)))
    ->Promise.catch(err => {
      let errMsg = switch err {
      | JsExn(jsErr) =>
        switch JsExn.message(jsErr) {
        | Some(m) => m
        | None => "Unknown error"
        }
      | _ => "Unknown error"
      }
      dispatch(onErr(errMsg))
      Promise.resolve()
    })
    ->ignore
  })
}

/// Extract a network capability token from the model.
/// Returns None if the network capability has not been granted.
let getNetworkToken = (model: Model.model): option<float> => {
  switch model.networkCap {
  | Granted(token) => Some(token)
  | _ => None
  }
}

/// Extract a clipboard capability token from the model.
let getClipboardToken = (model: Model.model): option<float> => {
  switch model.clipboardCap {
  | Granted(token) => Some(token)
  | _ => None
  }
}

// ---------------------------------------------------------------------------
// Init
// ---------------------------------------------------------------------------

/// Initialise the application. Starts with the capability grant panel
/// visible and no active connections.
let init = (): (Model.model, Tea_Cmd.t<Msg.msg>) => {
  (Model.initial, Tea_Cmd.none)
}

// ---------------------------------------------------------------------------
// Update
// ---------------------------------------------------------------------------

/// Process a message and return the new state plus any commands to execute.
let update = (model: Model.model, msg: Msg.msg): (Model.model, Tea_Cmd.t<Msg.msg>) => {
  switch msg {
  // --- Server health ---
  | CheckHealth =>
    switch getNetworkToken(model) {
    | Some(token) =>
      let cmd = cmdFromPromise(
        () => VeriSimDbCmd.checkHealth(token),
        result => Msg.HealthResult(Ok(result)),
        err => Msg.HealthResult(Error(err)),
      )
      ({...model, status: Connecting}, cmd)
    | None => ({...model, error: Some("Network capability required. Grant it in the capability panel.")}, Tea_Cmd.none)
    }

  | HealthResult(Ok(_response)) =>
    ({...model, status: Connected, error: None}, Tea_Cmd.none)

  | HealthResult(Error(err)) =>
    ({...model, status: Disconnected, error: Some(`Health check failed: ${err}`)}, Tea_Cmd.none)

  // --- VQL console ---
  | VqlInputChanged(input) =>
    ({...model, vqlInput: input}, Tea_Cmd.none)

  | ExecuteVql =>
    switch getNetworkToken(model) {
    | Some(token) =>
      if String.trim(model.vqlInput) == "" {
        ({...model, error: Some("VQL query cannot be empty.")}, Tea_Cmd.none)
      } else {
        let cmd = cmdFromPromise(
          () => VeriSimDbCmd.queryVql(model.vqlInput, token),
          result => Msg.VqlResult(Ok(result)),
          err => Msg.VqlResult(Error(err)),
        )
        ({...model, vqlExecuting: true, vqlResult: None, error: None}, cmd)
      }
    | None => ({...model, error: Some("Network capability required.")}, Tea_Cmd.none)
    }

  | VqlResult(Ok(result)) =>
    ({...model, vqlExecuting: false, vqlResult: Some(result), error: None}, Tea_Cmd.none)

  | VqlResult(Error(err)) =>
    ({...model, vqlExecuting: false, error: Some(`VQL query failed: ${err}`)}, Tea_Cmd.none)

  | CopyVql =>
    switch getClipboardToken(model) {
    | Some(token) =>
      let cmd = cmdFromPromise(
        () => Capabilities.copyToClipboard(model.vqlInput, token)->Promise.thenResolve(_ => "copied"),
        _result => Msg.NoOp,
        _err => Msg.NoOp,
      )
      (model, cmd)
    | None => ({...model, error: Some("Clipboard capability required.")}, Tea_Cmd.none)
    }

  // --- Octad browser ---
  | LoadOctads =>
    switch getNetworkToken(model) {
    | Some(token) =>
      let cmd = cmdFromPromise(
        () => VeriSimDbCmd.listOctads(model.octadLimit, model.octadOffset, token),
        result => Msg.OctadsLoaded(Ok(result)),
        err => Msg.OctadsLoaded(Error(err)),
      )
      (model, cmd)
    | None => ({...model, error: Some("Network capability required.")}, Tea_Cmd.none)
    }

  | OctadsLoaded(Ok(_response)) =>
    // In a full implementation, parse the JSON response into octadSummary array.
    // For now, store success and clear errors.
    ({...model, error: None}, Tea_Cmd.none)

  | OctadsLoaded(Error(err)) =>
    ({...model, error: Some(`Failed to load octads: ${err}`)}, Tea_Cmd.none)

  | SelectEntity(entityId) =>
    switch getNetworkToken(model) {
    | Some(token) =>
      let cmd = cmdFromPromise(
        () => VeriSimDbCmd.getEntity(entityId, token),
        result => Msg.EntityLoaded(Ok(result)),
        err => Msg.EntityLoaded(Error(err)),
      )
      ({...model, selectedEntity: Some(entityId), detailTab: Overview}, cmd)
    | None => ({...model, error: Some("Network capability required.")}, Tea_Cmd.none)
    }

  | EntityLoaded(Ok(detail)) =>
    ({...model, entityDetail: Some(detail), error: None}, Tea_Cmd.none)

  | EntityLoaded(Error(err)) =>
    ({...model, error: Some(`Failed to load entity: ${err}`)}, Tea_Cmd.none)

  | SwitchDetailTab(tab) =>
    ({...model, detailTab: tab}, Tea_Cmd.none)

  | NextPage =>
    let newOffset = model.octadOffset + model.octadLimit
    let updated = {...model, octadOffset: newOffset}
    update(updated, LoadOctads)

  | PrevPage =>
    let newOffset = Math.Int.max(0, model.octadOffset - model.octadLimit)
    let updated = {...model, octadOffset: newOffset}
    update(updated, LoadOctads)

  // --- Entity CRUD ---
  | CreateOctad(entityJson) =>
    switch getNetworkToken(model) {
    | Some(token) =>
      let cmd = cmdFromPromise(
        () => VeriSimDbCmd.createOctad(entityJson, token),
        result => Msg.OctadCreated(Ok(result)),
        err => Msg.OctadCreated(Error(err)),
      )
      (model, cmd)
    | None => ({...model, error: Some("Network capability required.")}, Tea_Cmd.none)
    }

  | OctadCreated(Ok(_response)) =>
    update(model, LoadOctads)

  | OctadCreated(Error(err)) =>
    ({...model, error: Some(`Failed to create octad: ${err}`)}, Tea_Cmd.none)

  | DeleteOctad(entityId) =>
    switch getNetworkToken(model) {
    | Some(token) =>
      let cmd = cmdFromPromise(
        () => VeriSimDbCmd.deleteOctad(entityId, token),
        result => Msg.OctadDeleted(Ok(result)),
        err => Msg.OctadDeleted(Error(err)),
      )
      (model, cmd)
    | None => ({...model, error: Some("Network capability required.")}, Tea_Cmd.none)
    }

  | OctadDeleted(Ok(_response)) =>
    let updated = {...model, selectedEntity: None, entityDetail: None, driftStatus: None}
    update(updated, LoadOctads)

  | OctadDeleted(Error(err)) =>
    ({...model, error: Some(`Failed to delete octad: ${err}`)}, Tea_Cmd.none)

  // --- Drift detection ---
  | LoadDrift(entityId) =>
    switch getNetworkToken(model) {
    | Some(token) =>
      let cmd = cmdFromPromise(
        () => VeriSimDbCmd.getDrift(entityId, token),
        result => Msg.DriftLoaded(Ok(result)),
        err => Msg.DriftLoaded(Error(err)),
      )
      (model, cmd)
    | None => ({...model, error: Some("Network capability required.")}, Tea_Cmd.none)
    }

  | DriftLoaded(Ok(_response)) =>
    // In a full implementation, parse the JSON into driftInfo.
    ({...model, error: None}, Tea_Cmd.none)

  | DriftLoaded(Error(err)) =>
    ({...model, error: Some(`Failed to load drift: ${err}`)}, Tea_Cmd.none)

  | TriggerNormalise(entityId) =>
    switch getNetworkToken(model) {
    | Some(token) =>
      let cmd = cmdFromPromise(
        () => VeriSimDbCmd.triggerNormalise(entityId, token),
        result => Msg.NormaliseResult(Ok(result)),
        err => Msg.NormaliseResult(Error(err)),
      )
      (model, cmd)
    | None => ({...model, error: Some("Network capability required.")}, Tea_Cmd.none)
    }

  | NormaliseResult(Ok(_response)) =>
    // Reload entity and drift after normalisation.
    switch model.selectedEntity {
    | Some(entityId) =>
      let (m1, cmd1) = update(model, SelectEntity(entityId))
      let cmd2 = cmdFromPromise(
        () => {
          switch getNetworkToken(m1) {
          | Some(token) => VeriSimDbCmd.getDrift(entityId, token)
          | None => Promise.reject(JsError.throwWithMessage("No token"))
          }
        },
        result => Msg.DriftLoaded(Ok(result)),
        err => Msg.DriftLoaded(Error(err)),
      )
      (m1, Tea_Cmd.batch([cmd1, cmd2]))
    | None => (model, Tea_Cmd.none)
    }

  | NormaliseResult(Error(err)) =>
    ({...model, error: Some(`Normalisation failed: ${err}`)}, Tea_Cmd.none)

  // --- Telemetry ---
  | LoadTelemetry =>
    switch getNetworkToken(model) {
    | Some(token) =>
      let cmd = cmdFromPromise(
        () => VeriSimDbCmd.getTelemetry(token),
        result => Msg.TelemetryLoaded(Ok(result)),
        err => Msg.TelemetryLoaded(Error(err)),
      )
      (model, cmd)
    | None => ({...model, error: Some("Network capability required.")}, Tea_Cmd.none)
    }

  | TelemetryLoaded(Ok(raw)) =>
    ({...model, telemetry: Some({raw, enabled: true}), error: None}, Tea_Cmd.none)

  | TelemetryLoaded(Error(err)) =>
    ({...model, error: Some(`Failed to load telemetry: ${err}`)}, Tea_Cmd.none)

  // --- Orchestration status ---
  | LoadOrchStatus =>
    switch getNetworkToken(model) {
    | Some(token) =>
      let cmd = cmdFromPromise(
        () => VeriSimDbCmd.getOrchStatus(token),
        result => Msg.OrchStatusLoaded(Ok(result)),
        err => Msg.OrchStatusLoaded(Error(err)),
      )
      (model, cmd)
    | None => ({...model, error: Some("Network capability required.")}, Tea_Cmd.none)
    }

  | OrchStatusLoaded(Ok(status)) =>
    ({...model, orchStatus: Some(status), error: None}, Tea_Cmd.none)

  | OrchStatusLoaded(Error(err)) =>
    ({...model, error: Some(`Failed to load orchestration status: ${err}`)}, Tea_Cmd.none)

  // --- Gossamer capability tokens ---
  | RequestCapability(kind) =>
    let kindInt = switch kind {
    | "network" => Capabilities.Kind.network
    | "filesystem" => Capabilities.Kind.filesystem
    | "clipboard" => Capabilities.Kind.clipboard
    | _ => 0
    }
    let updatedModel = switch kind {
    | "network" => {...model, networkCap: Pending}
    | "filesystem" => {...model, filesystemCap: Pending}
    | "clipboard" => {...model, clipboardCap: Pending}
    | _ => model
    }
    let cmd = cmdFromPromise(
      () => Capabilities.requestCapability(kindInt)->Promise.thenResolve(token => Float.toString(token)),
      tokenStr => {
        switch Float.fromString(tokenStr) {
        | Some(token) => Msg.CapGranted(kind, token)
        | None => Msg.ClearError
        }
      },
      _err => Msg.CapRevoked(kind),
    )
    (updatedModel, cmd)

  | CapGranted(kind, token) =>
    switch kind {
    | "network" => ({...model, networkCap: Granted(token), error: None}, Tea_Cmd.none)
    | "filesystem" => ({...model, filesystemCap: Granted(token), error: None}, Tea_Cmd.none)
    | "clipboard" => ({...model, clipboardCap: Granted(token), error: None}, Tea_Cmd.none)
    | _ => (model, Tea_Cmd.none)
    }

  | CapRevoked(kind) =>
    switch kind {
    | "network" => ({...model, networkCap: Denied}, Tea_Cmd.none)
    | "filesystem" => ({...model, filesystemCap: Denied}, Tea_Cmd.none)
    | "clipboard" => ({...model, clipboardCap: Denied}, Tea_Cmd.none)
    | _ => (model, Tea_Cmd.none)
    }

  | DismissCapPanel =>
    ({...model, showCapPanel: false}, Tea_Cmd.none)

  | ShowCapPanel =>
    ({...model, showCapPanel: true}, Tea_Cmd.none)

  // --- UI ---
  | ClearError =>
    ({...model, error: None}, Tea_Cmd.none)

  | NoOp =>
    (model, Tea_Cmd.none)
  }
}

// ---------------------------------------------------------------------------
// View helpers
// ---------------------------------------------------------------------------

/// Render the status indicator with appropriate colour.
let statusIndicator = (status: Model.serverStatus): Tea_Html.t<Msg.msg> => {
  let (label, className) = switch status {
  | Connected => ("Connected", "status-connected")
  | Disconnected => ("Disconnected", "status-disconnected")
  | Connecting => ("Connecting...", "status-connecting")
  }
  Tea_Html.span(
    [Tea_Html.Attributes.class(className)],
    [Tea_Html.text(label)],
  )
}

/// Render a capability row in the grant panel.
let capabilityRow = (
  kindName: string,
  kindInt: int,
  status: Model.capabilityStatus,
): Tea_Html.t<Msg.msg> => {
  let statusText = switch status {
  | NotRequested => "Not requested"
  | Pending => "Requesting..."
  | Granted(_) => "Granted"
  | Denied => "Denied"
  }
  let statusClass = switch status {
  | NotRequested => "cap-not-requested"
  | Pending => "cap-pending"
  | Granted(_) => "cap-granted"
  | Denied => "cap-denied"
  }
  let button = switch status {
  | NotRequested | Denied =>
    Tea_Html.button(
      [Tea_Html.Events.onClick(Msg.RequestCapability(kindName))],
      [Tea_Html.text("Grant")],
    )
  | Pending =>
    Tea_Html.button(
      [Tea_Html.Attributes.disabled(true)],
      [Tea_Html.text("Pending...")],
    )
  | Granted(_) =>
    Tea_Html.button(
      [Tea_Html.Attributes.disabled(true)],
      [Tea_Html.text("Active")],
    )
  }
  Tea_Html.div(
    [Tea_Html.Attributes.class("cap-row")],
    [
      Tea_Html.div(
        [Tea_Html.Attributes.class("cap-info")],
        [
          Tea_Html.strong([], [Tea_Html.text(Capabilities.Kind.toString(kindInt))]),
          Tea_Html.p([], [Tea_Html.text(Capabilities.Kind.description(kindInt))]),
          Tea_Html.span([Tea_Html.Attributes.class(statusClass)], [Tea_Html.text(statusText)]),
        ],
      ),
      button,
    ],
  )
}

/// Render an octad summary card in the sidebar.
let octadCard = (octad: Model.octadSummary): Tea_Html.t<Msg.msg> => {
  let driftClass = if octad.driftScore > 0.5 {
    "drift-high"
  } else if octad.driftScore > 0.2 {
    "drift-medium"
  } else {
    "drift-low"
  }
  Tea_Html.div(
    [
      Tea_Html.Attributes.class("octad-card"),
      Tea_Html.Events.onClick(Msg.SelectEntity(octad.id)),
    ],
    [
      Tea_Html.h3([], [Tea_Html.text(octad.title)]),
      Tea_Html.p(
        [Tea_Html.Attributes.class("octad-meta")],
        [Tea_Html.text(`${Int.toString(octad.activeModalities)}/8 modalities`)],
      ),
      Tea_Html.span(
        [Tea_Html.Attributes.class(driftClass)],
        [Tea_Html.text(`Drift: ${Float.toFixedWithPrecision(octad.driftScore, ~digits=3)}`)],
      ),
    ],
  )
}

/// Render a modality tab button.
let modalityTab = (
  tab: Model.detailTab,
  activeTab: Model.detailTab,
  label: string,
): Tea_Html.t<Msg.msg> => {
  let className = if tab == activeTab { "tab-active" } else { "tab-inactive" }
  Tea_Html.button(
    [
      Tea_Html.Attributes.class(`modality-tab ${className}`),
      Tea_Html.Events.onClick(Msg.SwitchDetailTab(tab)),
    ],
    [Tea_Html.text(label)],
  )
}

/// Render the drift indicator for the currently selected entity.
let driftIndicator = (driftOpt: option<Model.driftInfo>): Tea_Html.t<Msg.msg> => {
  switch driftOpt {
  | Some(drift) =>
    let driftRow = (label: string, value: float) => {
      let cls = if value > 0.5 {
        "drift-bar-high"
      } else if value > 0.2 {
        "drift-bar-medium"
      } else {
        "drift-bar-low"
      }
      Tea_Html.div(
        [Tea_Html.Attributes.class("drift-row")],
        [
          Tea_Html.span([Tea_Html.Attributes.class("drift-label")], [Tea_Html.text(label)]),
          Tea_Html.div(
            [Tea_Html.Attributes.class(`drift-bar ${cls}`)],
            [Tea_Html.text(Float.toFixedWithPrecision(value, ~digits=4))],
          ),
        ],
      )
    }
    Tea_Html.div(
      [Tea_Html.Attributes.class("drift-indicator")],
      [
        Tea_Html.h3([], [Tea_Html.text("Drift Status")]),
        driftRow("Semantic-Vector", drift.semanticVectorDrift),
        driftRow("Graph-Document", drift.graphDocumentDrift),
        driftRow("Temporal Consistency", drift.temporalConsistencyDrift),
        driftRow("Tensor", drift.tensorDrift),
        driftRow("Schema", drift.schemaDrift),
        driftRow("Quality", drift.qualityDrift),
        Tea_Html.button(
          [
            Tea_Html.Attributes.class("normalise-button"),
            Tea_Html.Events.onClick(Msg.TriggerNormalise(drift.entityId)),
          ],
          [Tea_Html.text("Normalise")],
        ),
      ],
    )
  | None =>
    Tea_Html.div(
      [Tea_Html.Attributes.class("drift-indicator drift-empty")],
      [Tea_Html.text("Select an entity to view drift status")],
    )
  }
}

// ---------------------------------------------------------------------------
// View
// ---------------------------------------------------------------------------

/// Render the complete VeriSimDB Admin panel UI.
let view = (model: Model.model): Tea_Html.t<Msg.msg> => {
  Tea_Html.div(
    [Tea_Html.Attributes.class("verisimdb-admin")],
    [
      // --- Header ---
      Tea_Html.header(
        [Tea_Html.Attributes.class("admin-header")],
        [
          Tea_Html.h1([], [Tea_Html.text("VeriSimDB Admin")]),
          Tea_Html.div(
            [Tea_Html.Attributes.class("header-controls")],
            [
              Tea_Html.span(
                [Tea_Html.Attributes.class("runtime-badge")],
                [Tea_Html.text(`Runtime: ${RuntimeBridge.runtimeName()}`)],
              ),
              statusIndicator(model.status),
              Tea_Html.button(
                [Tea_Html.Events.onClick(Msg.CheckHealth)],
                [Tea_Html.text("Check Health")],
              ),
              Tea_Html.button(
                [Tea_Html.Events.onClick(Msg.LoadOrchStatus)],
                [Tea_Html.text("Orch Status")],
              ),
              Tea_Html.button(
                [Tea_Html.Events.onClick(Msg.ShowCapPanel)],
                [Tea_Html.text("Capabilities")],
              ),
            ],
          ),
        ],
      ),

      // --- Error bar ---
      switch model.error {
      | Some(err) =>
        Tea_Html.div(
          [Tea_Html.Attributes.class("error-bar")],
          [
            Tea_Html.text(err),
            Tea_Html.button(
              [Tea_Html.Events.onClick(Msg.ClearError)],
              [Tea_Html.text("Dismiss")],
            ),
          ],
        )
      | None => Tea_Html.noNode
      },

      // --- Capability grant panel ---
      if model.showCapPanel {
        Tea_Html.div(
          [Tea_Html.Attributes.class("cap-panel")],
          [
            Tea_Html.h2([], [Tea_Html.text("Gossamer Capability Tokens")]),
            Tea_Html.p(
              [Tea_Html.Attributes.class("cap-description")],
              [
                Tea_Html.text(
                  "VeriSimDB Admin runs in a sandboxed Gossamer webview. " ++
                  "Grant capabilities below to enable database management features. " ++
                  "Each token is time-limited and can be revoked at any time.",
                ),
              ],
            ),
            capabilityRow("network", Capabilities.Kind.network, model.networkCap),
            capabilityRow("filesystem", Capabilities.Kind.filesystem, model.filesystemCap),
            capabilityRow("clipboard", Capabilities.Kind.clipboard, model.clipboardCap),
            Tea_Html.button(
              [
                Tea_Html.Attributes.class("cap-dismiss"),
                Tea_Html.Events.onClick(Msg.DismissCapPanel),
              ],
              [Tea_Html.text("Continue to Admin Panel")],
            ),
          ],
        )
      } else {
        Tea_Html.noNode
      },

      // --- VQL Console (top panel, full width) ---
      Tea_Html.section(
        [Tea_Html.Attributes.class("vql-console")],
        [
          Tea_Html.div(
            [Tea_Html.Attributes.class("vql-header")],
            [
              Tea_Html.h2([], [Tea_Html.text("VQL Console")]),
              Tea_Html.div(
                [Tea_Html.Attributes.class("vql-actions")],
                [
                  Tea_Html.button(
                    [
                      Tea_Html.Attributes.class(model.vqlExecuting ? "vql-executing" : "vql-execute"),
                      Tea_Html.Attributes.disabled(model.vqlExecuting),
                      Tea_Html.Events.onClick(Msg.ExecuteVql),
                    ],
                    [Tea_Html.text(model.vqlExecuting ? "Executing..." : "Execute")],
                  ),
                  Tea_Html.button(
                    [Tea_Html.Events.onClick(Msg.CopyVql)],
                    [Tea_Html.text("Copy VQL")],
                  ),
                ],
              ),
            ],
          ),
          Tea_Html.div(
            [Tea_Html.Attributes.class("vql-body")],
            [
              Tea_Html.textarea(
                [
                  Tea_Html.Attributes.class("vql-input"),
                  Tea_Html.Attributes.placeholder("Enter VQL query... e.g. FETCH entity WHERE type = 'Document' PROOF EXISTENCE"),
                  Tea_Html.Attributes.value(model.vqlInput),
                  Tea_Html.Events.onInput(value => Msg.VqlInputChanged(value)),
                ],
                [],
              ),
              Tea_Html.div(
                [Tea_Html.Attributes.class("vql-result")],
                [
                  switch model.vqlResult {
                  | Some(result) =>
                    Tea_Html.pre(
                      [Tea_Html.Attributes.class("vql-result-content")],
                      [Tea_Html.text(result)],
                    )
                  | None =>
                    Tea_Html.p(
                      [Tea_Html.Attributes.class("vql-placeholder")],
                      [Tea_Html.text("Query results will appear here")],
                    )
                  },
                ],
              ),
            ],
          ),
        ],
      ),

      // --- Main content: Sidebar + Detail ---
      Tea_Html.main(
        [Tea_Html.Attributes.class("admin-main")],
        [
          // Sidebar: octad browser (paginated)
          Tea_Html.aside(
            [Tea_Html.Attributes.class("octad-sidebar")],
            [
              Tea_Html.div(
                [Tea_Html.Attributes.class("sidebar-header")],
                [
                  Tea_Html.h2([], [Tea_Html.text("Octads")]),
                  Tea_Html.button(
                    [Tea_Html.Events.onClick(Msg.LoadOctads)],
                    [Tea_Html.text("Refresh")],
                  ),
                ],
              ),
              Tea_Html.div(
                [Tea_Html.Attributes.class("octad-list")],
                Array.map(model.octads, octadCard)->Array.toList->List.toArray,
              ),
              // Pagination controls
              Tea_Html.div(
                [Tea_Html.Attributes.class("pagination")],
                [
                  Tea_Html.button(
                    [
                      Tea_Html.Attributes.disabled(model.octadOffset == 0),
                      Tea_Html.Events.onClick(Msg.PrevPage),
                    ],
                    [Tea_Html.text("Prev")],
                  ),
                  Tea_Html.span(
                    [Tea_Html.Attributes.class("page-info")],
                    [
                      Tea_Html.text(
                        `${Int.toString(model.octadOffset + 1)}-${Int.toString(
                          Math.Int.min(
                            model.octadOffset + model.octadLimit,
                            model.octadTotal,
                          ),
                        )} of ${Int.toString(model.octadTotal)}`,
                      ),
                    ],
                  ),
                  Tea_Html.button(
                    [
                      Tea_Html.Attributes.disabled(
                        model.octadOffset + model.octadLimit >= model.octadTotal,
                      ),
                      Tea_Html.Events.onClick(Msg.NextPage),
                    ],
                    [Tea_Html.text("Next")],
                  ),
                ],
              ),
            ],
          ),

          // Main panel: entity detail with modality tabs
          Tea_Html.section(
            [Tea_Html.Attributes.class("detail-panel")],
            [
              switch model.selectedEntity {
              | Some(entityId) =>
                Tea_Html.div(
                  [],
                  [
                    Tea_Html.div(
                      [Tea_Html.Attributes.class("entity-header")],
                      [
                        Tea_Html.h2([], [Tea_Html.text(`Entity: ${entityId}`)]),
                        Tea_Html.div(
                          [Tea_Html.Attributes.class("entity-actions")],
                          [
                            Tea_Html.button(
                              [Tea_Html.Events.onClick(Msg.LoadDrift(entityId))],
                              [Tea_Html.text("Check Drift")],
                            ),
                            Tea_Html.button(
                              [
                                Tea_Html.Attributes.class("delete-button"),
                                Tea_Html.Events.onClick(Msg.DeleteOctad(entityId)),
                              ],
                              [Tea_Html.text("Delete")],
                            ),
                          ],
                        ),
                      ],
                    ),
                    // Modality tabs
                    Tea_Html.nav(
                      [Tea_Html.Attributes.class("modality-tabs")],
                      [
                        modalityTab(Overview, model.detailTab, "Overview"),
                        modalityTab(Graph, model.detailTab, "Graph"),
                        modalityTab(Vector, model.detailTab, "Vector"),
                        modalityTab(Tensor, model.detailTab, "Tensor"),
                        modalityTab(Semantic, model.detailTab, "Semantic"),
                        modalityTab(Document, model.detailTab, "Document"),
                        modalityTab(Temporal, model.detailTab, "Temporal"),
                        modalityTab(Provenance, model.detailTab, "Provenance"),
                        modalityTab(Spatial, model.detailTab, "Spatial"),
                      ],
                    ),
                    // Modality content
                    Tea_Html.div(
                      [Tea_Html.Attributes.class("modality-content")],
                      [
                        switch model.entityDetail {
                        | Some(detail) =>
                          Tea_Html.pre(
                            [Tea_Html.Attributes.class("entity-detail-json")],
                            [Tea_Html.text(detail)],
                          )
                        | None =>
                          Tea_Html.p([], [Tea_Html.text("Loading entity detail...")])
                        },
                      ],
                    ),
                    // Drift indicator with normalise button
                    driftIndicator(model.driftStatus),
                  ],
                )
              | None =>
                Tea_Html.div(
                  [Tea_Html.Attributes.class("overview")],
                  [
                    Tea_Html.h2([], [Tea_Html.text("VeriSimDB Overview")]),
                    Tea_Html.p([], [
                      Tea_Html.text(
                        `${Int.toString(Array.length(model.octads))} octads loaded`,
                      ),
                    ]),
                    switch model.orchStatus {
                    | Some(status) =>
                      Tea_Html.pre(
                        [Tea_Html.Attributes.class("orch-status-display")],
                        [Tea_Html.text(status)],
                      )
                    | None => Tea_Html.noNode
                    },
                  ],
                )
              },
            ],
          ),
        ],
      ),

      // --- Telemetry Dashboard (bottom bar) ---
      Tea_Html.footer(
        [Tea_Html.Attributes.class("telemetry-dashboard")],
        [
          Tea_Html.div(
            [Tea_Html.Attributes.class("telemetry-header")],
            [
              Tea_Html.h3([], [Tea_Html.text("Telemetry")]),
              Tea_Html.button(
                [Tea_Html.Events.onClick(Msg.LoadTelemetry)],
                [Tea_Html.text("Refresh Telemetry")],
              ),
            ],
          ),
          switch model.telemetry {
          | Some(telemetry) =>
            if telemetry.enabled {
              Tea_Html.pre(
                [Tea_Html.Attributes.class("telemetry-data")],
                [Tea_Html.text(telemetry.raw)],
              )
            } else {
              Tea_Html.p(
                [Tea_Html.Attributes.class("telemetry-disabled")],
                [Tea_Html.text("Telemetry collection disabled. Enable with VERISIM_TELEMETRY=true.")],
              )
            }
          | None =>
            Tea_Html.p(
              [Tea_Html.Attributes.class("telemetry-placeholder")],
              [Tea_Html.text("Click 'Refresh Telemetry' to load aggregate metrics")],
            )
          },
        ],
      ),
    ],
  )
}

// ---------------------------------------------------------------------------
// Main -- TEA program registration
// ---------------------------------------------------------------------------

/// Start the VeriSimDB Admin TEA application.
/// Mounts into the #app element in public/index.html.
let main = Tea_App.standardProgram({
  init: () => init(),
  update: update,
  view: view,
  subscriptions: _model => Tea_Sub.none,
})
