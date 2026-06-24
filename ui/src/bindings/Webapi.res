// SPDX-License-Identifier: MPL-2.0
// Webapi bindings for DOM operations

module Dom = {
  @val external document: Dom.document = "document"

  module Document = {
    @send
    external addEventListener: (Dom.document, string, 'a => unit) => unit = "addEventListener"

    @send
    external removeEventListener: (Dom.document, string, 'a => unit) => unit = "removeEventListener"

    let addMouseMoveEventListener = (doc: Dom.document, handler: Dom.mouseEvent => unit) => {
      addEventListener(doc, "mousemove", handler)
    }

    let removeMouseMoveEventListener = (doc: Dom.document, handler: Dom.mouseEvent => unit) => {
      removeEventListener(doc, "mousemove", handler)
    }

    let addMouseUpEventListener = (doc: Dom.document, handler: Dom.mouseEvent => unit) => {
      addEventListener(doc, "mouseup", handler)
    }

    let removeMouseUpEventListener = (doc: Dom.document, handler: Dom.mouseEvent => unit) => {
      removeEventListener(doc, "mouseup", handler)
    }
  }
}
