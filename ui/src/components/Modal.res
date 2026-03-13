// SPDX-License-Identifier: PMPL-1.0-or-later
// Modal component for dialogs

@react.component
let make = (~isOpen: bool, ~onClose: unit => unit, ~title: string, ~children: React.element) => {
  // Close on Escape key
  React.useEffect1(() => {
    if isOpen {
      let handleKeyDown = (evt: 'a) => {
        let key: string = %raw(`evt.key`)
        if key == "Escape" {
          onClose()
        }
      }

      let handleKeyDownAny: Dom.event => unit = event => {
        handleKeyDown(event)
      }

      %raw(`document.addEventListener("keydown", handleKeyDownAny)`)

      Some(
        () => {
          %raw(`document.removeEventListener("keydown", handleKeyDownAny)`)
        },
      )
    } else {
      None
    }
  }, [isOpen])

  if !isOpen {
    React.null
  } else {
    <div className="modal-overlay" onClick={_ => onClose()}>
      <div className="modal-dialog" onClick={evt => evt->ReactEvent.Mouse.stopPropagation}>
        <div className="modal-header">
          <h2 className="modal-title"> {React.string(title)} </h2>
          <button className="modal-close-button" onClick={_ => onClose()} ariaLabel="Close">
            {React.string("×")}
          </button>
        </div>
        <div className="modal-body"> {children} </div>
      </div>
    </div>
  }
}
