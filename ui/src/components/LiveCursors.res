// SPDX-License-Identifier: PMPL-1.0-or-later
// Live cursors component - shows other users' cursor positions

open CollaborationStore

@react.component
let make = (~users: array<collaborativeUser>) => {
  <div className="live-cursors">
    {users
    ->Array.map(user => {
      switch user.cursor {
      | Some(cursor) => <div
          key={user.clientId}
          className="cursor-indicator"
          style=%raw(`{
              position: "absolute",
              backgroundColor: user.color,
              borderRadius: "50%",
              width: "12px",
              height: "12px",
              pointerEvents: "none",
              zIndex: "1000",
              boxShadow: "0 2px 4px rgba(0,0,0,0.2)"
            }`)
        >
          <div
            className="cursor-label"
            style=%raw(`{
                position: "absolute",
                top: "16px",
                left: "0",
                backgroundColor: user.color,
                color: "white",
                padding: "2px 6px",
                borderRadius: "3px",
                fontSize: "11px",
                fontWeight: "500",
                whiteSpace: "nowrap",
                boxShadow: "0 1px 3px rgba(0,0,0,0.3)"
              }`)
          >
            {React.string(user.name)}
          </div>
        </div>
      | None => React.null
      }
    })
    ->React.array}
  </div>
}
