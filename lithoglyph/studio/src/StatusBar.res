// SPDX-License-Identifier: PMPL-1.0-or-later
// Lith Studio - Status Bar Component

open Types

@react.component
let make = (~status: option<ServiceStatus.t>) => {
  let statusClass = switch status {
  | Some(s) if s.overall_ready => "status-bar ready"
  | Some(_) => "status-bar partial"
  | None => "status-bar loading"
  }

  let renderService = (info: ServiceStatus.serviceInfo) => {
    let statusIcon = if info.available {
      "[OK]"
    } else {
      "[ ]"
    }

    let statusText = if info.available {
      switch info.version {
      | Some(v) => `${info.name} v${v}`
      | None => info.name
      }
    } else {
      switch info.blocking_milestone {
      | Some(m) => `${info.name} (awaiting ${m})`
      | None => `${info.name} unavailable`
      }
    }

    <span className={info.available ? "service available" : "service unavailable"} title={info.message}>
      {React.string(statusIcon)}
      {React.string(" " ++ statusText)}
    </span>
  }

  <footer className={statusClass}>
    {switch status {
    | Some(s) =>
      <>
        <div className="service-status">
          {renderService(s.lith)}
          <span className="separator">{React.string(" | ")}</span>
          {renderService(s.fbqldt)}
        </div>
        <div className="feature-status">
          {if s.features.schema_builder {
            <span className="feature enabled" title="Schema builder available">
              {React.string("Schema [OK]")}
            </span>
          } else {
            React.null
          }}
          {if s.features.query_execution {
            <span className="feature enabled" title="Query execution available">
              {React.string("Query [OK]")}
            </span>
          } else {
            <span className="feature disabled" title="Query execution requires Lith">
              {React.string("Query [ ]")}
            </span>
          }}
        </div>
      </>
    | None =>
      <div className="loading-status">
        {React.string("Checking services...")}
      </div>
    }}
  </footer>
}
