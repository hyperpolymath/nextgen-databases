// SPDX-License-Identifier: PMPL-1.0-or-later
// VQL syntax highlighting for the playground editor.
// Produces HTML spans with CSS classes for keyword colouring.

let highlightVql = (text: string, ~vqlDt: bool=false): string => {
  let result = ref("")
  let chars = String.split(text, "")
  let len = Array.length(chars)
  let i = ref(0)

  while i.contents < len {
    let ch = chars[i.contents]->Option.getOr("")

    // String literals
    if ch == "'" || ch == "\"" {
      let quote = ch
      let start = i.contents
      i := i.contents + 1
      while i.contents < len && chars[i.contents]->Option.getOr("") != quote {
        if chars[i.contents]->Option.getOr("") == "\\" {
          i := i.contents + 1
        }
        i := i.contents + 1
      }
      if i.contents < len {
        i := i.contents + 1
      }
      let slice = String.slice(text, ~start, ~end=i.contents)
      result := result.contents ++ `<span class="str">${slice}</span>`
    }
    // Comments (-- single line)
    else if ch == "-" && i.contents + 1 < len && chars[i.contents + 1]->Option.getOr("") == "-" {
      let start = i.contents
      while i.contents < len && chars[i.contents]->Option.getOr("") != "\n" {
        i := i.contents + 1
      }
      let slice = String.slice(text, ~start, ~end=i.contents)
      result := result.contents ++ `<span class="cmt">${slice}</span>`
    }
    // Words
    else if Js.Re.test_(%re("/[a-zA-Z_]/"), ch) {
      let start = i.contents
      while i.contents < len && Js.Re.test_(%re("/[a-zA-Z0-9_]/"), chars[i.contents]->Option.getOr("")) {
        i := i.contents + 1
      }
      let word = String.slice(text, ~start, ~end=i.contents)
      let upper = String.toUpperCase(word)

      if VqlKeywords.isModality(upper) {
        result := result.contents ++ `<span class="mod">${word}</span>`
      } else if VqlKeywords.isProofType(upper) && vqlDt {
        result := result.contents ++ `<span class="proof">${word}</span>`
      } else if VqlKeywords.isKeyword(upper) {
        result := result.contents ++ `<span class="kw">${word}</span>`
      } else {
        result := result.contents ++ word
      }
    }
    // Numbers
    else if Js.Re.test_(%re("/[0-9]/"), ch) {
      let start = i.contents
      while i.contents < len && Js.Re.test_(%re("/[0-9.]/"), chars[i.contents]->Option.getOr("")) {
        i := i.contents + 1
      }
      let num = String.slice(text, ~start, ~end=i.contents)
      result := result.contents ++ `<span class="num">${num}</span>`
    }
    // Everything else
    else {
      // HTML-escape < > &
      let escaped = switch ch {
      | "<" => "&lt;"
      | ">" => "&gt;"
      | "&" => "&amp;"
      | c => c
      }
      result := result.contents ++ escaped
      i := i.contents + 1
    }
  }

  result.contents
}
