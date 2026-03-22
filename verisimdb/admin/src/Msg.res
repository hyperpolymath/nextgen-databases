// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)

/// Msg -- Message type for the VeriSimDB Admin TEA architecture.
///
/// Every user interaction and async result flows through this type.
/// Messages are dispatched by the view and processed by the update
/// function in App.res.

/// All messages that can occur in the VeriSimDB Admin panel.
type msg =
  // --- Server health ---
  | /// User clicked "Check Health" or auto-poll triggered.
    CheckHealth
  | /// Health check response arrived from the Rust core.
    HealthResult(result<string, string>)

  // --- VQL console ---
  | /// User typed in the VQL console input.
    VqlInputChanged(string)
  | /// User pressed Execute or Ctrl+Enter in the VQL console.
    ExecuteVql
  | /// VQL query result arrived.
    VqlResult(result<string, string>)
  | /// User clicked "Copy VQL" to copy the current query to clipboard.
    CopyVql

  // --- Octad browser ---
  | /// Load or refresh the octad entity list.
    LoadOctads
  | /// Octad list response arrived.
    OctadsLoaded(result<string, string>)
  | /// User selected an entity in the sidebar.
    SelectEntity(string)
  | /// Entity detail response arrived (full 8-modality snapshot).
    EntityLoaded(result<string, string>)
  | /// User switched the detail tab to a different modality.
    SwitchDetailTab(Model.detailTab)
  | /// Navigate pagination forward.
    NextPage
  | /// Navigate pagination backward.
    PrevPage

  // --- Entity CRUD ---
  | /// User submitted the create octad form.
    CreateOctad(string)
  | /// Create response arrived.
    OctadCreated(result<string, string>)
  | /// User confirmed deletion of an entity.
    DeleteOctad(string)
  | /// Delete response arrived.
    OctadDeleted(result<string, string>)

  // --- Drift detection ---
  | /// Load drift status for the currently selected entity.
    LoadDrift(string)
  | /// Drift status response arrived.
    DriftLoaded(result<string, string>)
  | /// User clicked "Normalise" to trigger self-normalisation.
    TriggerNormalise(string)
  | /// Normalisation response arrived.
    NormaliseResult(result<string, string>)

  // --- Telemetry ---
  | /// Load aggregate telemetry from the Elixir orchestration layer.
    LoadTelemetry
  | /// Telemetry response arrived.
    TelemetryLoaded(result<string, string>)

  // --- Orchestration status ---
  | /// Load orchestration layer status.
    LoadOrchStatus
  | /// Orchestration status response arrived.
    OrchStatusLoaded(result<string, string>)

  // --- Gossamer capability tokens ---
  | /// User clicked "Grant" on a capability in the cap panel.
    RequestCapability(string)
  | /// Gossamer runtime granted a capability token.
    CapGranted(string, float)
  | /// Gossamer runtime revoked or denied a capability token.
    CapRevoked(string)
  | /// User dismissed the capability panel.
    DismissCapPanel
  | /// User reopened the capability panel.
    ShowCapPanel

  // --- UI ---
  | /// Clear the current error message.
    ClearError
  | /// No-op message (used for commands that have no followup).
    NoOp
