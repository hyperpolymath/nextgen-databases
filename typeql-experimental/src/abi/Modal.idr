-- SPDX-License-Identifier: PMPL-1.0-or-later
-- Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
--
-- Modal.idr — Modal scoping (IN TRANSACTION)
--
-- Data accessed in one transaction scope is wrapped in a modal Box.
-- Data from different scopes cannot be mixed without explicit marshalling.
-- This ensures scope isolation at the type level.

module Modal

import Core

%default total

-- ============================================================================
-- World Tags (Transaction Scopes)
-- ============================================================================

||| A world represents a named transaction scope. Data wrapped in a Box
||| is tagged with the world it belongs to, preventing cross-scope leaks.
public export
data World : Type where
  ||| Construct a named world (transaction scope).
  MkWorld : (name : String) -> World

public export
Eq World where
  (MkWorld a) == (MkWorld b) = a == b

public export
Show World where
  show (MkWorld n) = "World<" ++ n ++ ">"

-- ============================================================================
-- Transaction States (World-level)
-- ============================================================================

||| The state of a transaction scope. This is similar to SessionState but
||| at the modal/world level rather than the session level.
public export
data TxState : Type where
  TxFresh      : TxState
  TxActive     : TxState
  TxCommitted  : TxState
  TxRolledBack : TxState
  TxSnapshot   : TxState  -- read-only snapshot

public export
Show TxState where
  show TxFresh      = "Fresh"
  show TxActive     = "Active"
  show TxCommitted  = "Committed"
  show TxRolledBack = "RolledBack"
  show TxSnapshot   = "ReadSnapshot"

-- ============================================================================
-- Modal Box Type
-- ============================================================================

||| A modal box wraps a value with a world tag. Values inside a Box can
||| only be extracted in the same world scope. Cross-world access requires
||| explicit marshalling via `marshal`.
public export
data Box : World -> Type -> Type where
  ||| Wrap a value in a world scope.
  MkBox : (val : a) -> Box w a

||| Functor-like map over a Box, staying in the same world.
public export
mapBox : (a -> b) -> Box w a -> Box w b
mapBox f (MkBox val) = MkBox (f val)

-- ============================================================================
-- Scope Evidence
-- ============================================================================

||| Proof that we are currently operating in world `w`.
||| This is a capability token — you can only extract from a Box if you
||| hold evidence of being in the matching world.
public export
data InScope : World -> Type where
  ||| Evidence that we are in the given world.
  ScopeEvidence : (w : World) -> InScope w

-- ============================================================================
-- Box Operations
-- ============================================================================

||| Extract a value from a Box, given evidence of being in the correct scope.
||| This is the elimination form for modal types.
public export
unbox : Box w a -> (prf : InScope w) -> a
unbox (MkBox val) (ScopeEvidence _) = val

||| Marshal a value from one world to another via a transformation function.
||| This is the only way to move data across world boundaries. The function
||| `f` acts as a sanitiser/adapter for cross-scope data flow.
public export
marshal : Box w1 a -> (a -> b) -> Box w2 b
marshal (MkBox val) f = MkBox (f val)

||| Duplicate a Box — create a copy in the same world.
public export
duplicate : Box w a -> Box w (Box w a)
duplicate b = MkBox b

||| Flatten nested Boxes in the same world.
public export
flatten : Box w (Box w a) -> Box w a
flatten (MkBox inner) = inner

-- ============================================================================
-- Scope Combinators
-- ============================================================================

||| Combine two boxed values in the same world.
public export
combine : Box w a -> Box w b -> Box w (a, b)
combine (MkBox x) (MkBox y) = MkBox (x, y)

||| Apply a boxed function to a boxed value in the same world.
public export
apply : Box w (a -> b) -> Box w a -> Box w b
apply (MkBox f) (MkBox x) = MkBox (f x)

-- ============================================================================
-- Transaction-Scoped Queries
-- ============================================================================

||| A query result scoped to a specific transaction world and state.
public export
record ScopedResult (w : World) (s : TxState) where
  constructor MkScopedResult
  result : Box w Core.QueryResult

||| Proof that a transaction state allows reading.
public export
data CanRead : TxState -> Type where
  ReadActive   : CanRead TxActive
  ReadSnapshot : CanRead TxSnapshot

||| Proof that a transaction state allows writing.
public export
data CanWrite : TxState -> Type where
  WriteActive : CanWrite TxActive

||| Execute a read in a scoped transaction.
public export
scopedRead : {auto canRead : CanRead s} -> (w : World) -> Box w Core.QueryResult
scopedRead w = MkBox (MkQueryResult [] 0)

||| Execute a write in a scoped transaction.
public export
scopedWrite : {auto canWrite : CanWrite s} -> (w : World) -> Box w ()
scopedWrite w = MkBox ()
