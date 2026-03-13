// SPDX-License-Identifier: PMPL-1.0-or-later
// ReScript bindings for Jotai

type atom<'a>
type writableAtom<'a, 'b>

@module("jotai")
external atom: 'a => atom<'a> = "atom"

@module("jotai")
external atomWithDefault: (unit => 'a) => atom<'a> = "atom"

// For derived atoms, use %raw to avoid type constraints
// The get function can retrieve any atom type
@module("jotai")
external derivedAtomRaw: ('a => 'b) => atom<'b> = "atom"

@module("jotai")
external useAtom: atom<'a> => ('a, ('a => 'a) => unit) = "useAtom"

@module("jotai")
external useAtomValue: atom<'a> => 'a = "useAtomValue"

@module("jotai")
external useSetAtom: atom<'a> => ('a => 'a) => unit = "useSetAtom"

module Provider = {
  @module("jotai") @react.component
  external make: (~children: React.element) => React.element = "Provider"
}
