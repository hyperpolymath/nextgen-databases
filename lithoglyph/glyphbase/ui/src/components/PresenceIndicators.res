// SPDX-License-Identifier: PMPL-1.0-or-later
// Presence indicators - shows who's currently online

open CollaborationStore

@react.component
let make = (~users: array<collaborativeUser>, ~maxVisible: int=5) => {
  let visibleUsers = users->Array.slice(~start=0, ~end=maxVisible)
  let remainingCount = Array.length(users) - Array.length(visibleUsers)

  <div className="presence-indicators">
    <div className="presence-avatars">
      {visibleUsers
      ->Array.map(user => {
        <div
          key={user.clientId}
          className="presence-avatar"
          style=%raw(`{
            width: "32px",
            height: "32px",
            borderRadius: "50%",
            backgroundColor: user.color,
            display: "inline-flex",
            alignItems: "center",
            justifyContent: "center",
            color: "white",
            fontSize: "14px",
            fontWeight: "600",
            border: "2px solid white",
            marginLeft: "-8px",
            cursor: "pointer"
          }`)
          title={user.name}
        >
          {React.string(user.name->String.slice(~start=0, ~end=1)->String.toUpperCase)}
        </div>
      })
      ->React.array}
      {if remainingCount > 0 {
        <div
          className="presence-avatar presence-overflow"
          style=%raw(`{
            width: "32px",
            height: "32px",
            borderRadius: "50%",
            backgroundColor: "#94a3b8",
            display: "inline-flex",
            alignItems: "center",
            justifyContent: "center",
            color: "white",
            fontSize: "12px",
            fontWeight: "600",
            border: "2px solid white",
            marginLeft: "-8px",
            cursor: "pointer"
          }`)
          title={`${Int.toString(remainingCount)} more`}
        >
          {React.string(`+${Int.toString(remainingCount)}`)}
        </div>
      } else {
        React.null
      }}
    </div>
    <div className="presence-status">
      {React.string(
        `${Int.toString(Array.length(users))} ${Array.length(users) === 1
            ? "user"
            : "users"} online`,
      )}
    </div>
  </div>
}
