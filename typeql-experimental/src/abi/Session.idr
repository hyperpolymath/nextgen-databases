-- SPDX-License-Identifier: PMPL-1.0-or-later
-- Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
--
-- Session.idr — Session type protocols (WITH SESSION)
--
-- Models database session state machines as indexed types. The session
-- type is indexed by its current protocol state, and only valid state
-- transitions are permitted by the type system.
--
-- State graph:
--   Fresh → Authenticated → InTransaction → Committed → Closed
--                       ↑                        │
--                       └────── RolledBack ◄─────┘

module Session

import Core

%default total

-- ============================================================================
-- Session States
-- ============================================================================

||| Protocol states for a database session. Transitions between states are
||| controlled by the operations below — the type system prevents illegal
||| transitions (e.g., querying before authentication, committing twice).
public export
data SessionState : Type where
  Fresh          : SessionState
  Authenticated  : SessionState
  InTransaction  : SessionState
  Committed      : SessionState
  RolledBack     : SessionState
  Closed         : SessionState

public export
Eq SessionState where
  Fresh         == Fresh         = True
  Authenticated == Authenticated = True
  InTransaction == InTransaction = True
  Committed     == Committed     = True
  RolledBack    == RolledBack    = True
  Closed        == Closed        = True
  _             == _             = False

public export
Show SessionState where
  show Fresh         = "Fresh"
  show Authenticated = "Authenticated"
  show InTransaction = "InTransaction"
  show Committed     = "Committed"
  show RolledBack    = "RolledBack"
  show Closed        = "Closed"

-- ============================================================================
-- Session Type (Indexed by State)
-- ============================================================================

||| A database session indexed by its current protocol state.
||| The state index is tracked at the type level, ensuring that operations
||| are only available in the correct state.
public export
data Session : SessionState -> Type where
  ||| A fresh session, not yet authenticated.
  MkFresh : Session Fresh

-- ============================================================================
-- Closability Proof
-- ============================================================================

||| Proof that a session in state `s` can be closed.
||| Sessions can be closed from Committed, RolledBack, or Authenticated states.
||| Fresh sessions can also be closed (abandoned). InTransaction and Closed cannot.
public export
data CanClose : SessionState -> Type where
  CloseFromCommitted    : CanClose Committed
  CloseFromRolledBack   : CanClose RolledBack
  CloseFromAuthenticated : CanClose Authenticated
  CloseFromFresh        : CanClose Fresh

-- ============================================================================
-- State Transitions (via SessionImpl with distinct constructors per state)
-- ============================================================================

||| Internal session representation carrying connection state.
public export
data SessionImpl : SessionState -> Type where
  FreshSession   : SessionImpl Fresh
  AuthSession    : (token : String) -> SessionImpl Authenticated
  TxSession      : (txId : String) -> SessionImpl InTransaction
  DoneSession    : SessionImpl Committed
  AbortedSession : SessionImpl RolledBack
  EndSession     : SessionImpl Closed

||| Authenticate: Fresh → Authenticated
public export
auth : (1 _ : SessionImpl Fresh) -> Either String (SessionImpl Authenticated)
auth FreshSession = Right (AuthSession "token")

||| Begin transaction: Authenticated → InTransaction
public export
beginTx : (1 _ : SessionImpl Authenticated) -> SessionImpl InTransaction
beginTx (AuthSession _) = TxSession "tx-001"

||| Execute a query within a transaction. The session remains InTransaction.
||| Returns the query result and the (still active) session.
public export
query : (1 _ : SessionImpl InTransaction) -> (Core.QueryResult, SessionImpl InTransaction)
query (TxSession txId) = (MkQueryResult [] 0, TxSession txId)

||| Commit: InTransaction → Committed
public export
commit : (1 _ : SessionImpl InTransaction) -> Either String (SessionImpl Committed)
commit (TxSession _) = Right DoneSession

||| Rollback: InTransaction → RolledBack
public export
rollback : (1 _ : SessionImpl InTransaction) -> SessionImpl RolledBack
rollback (TxSession _) = AbortedSession

||| Close a session from any closable state.
public export
close : (1 _ : SessionImpl s) -> {auto prf : CanClose s} -> SessionImpl Closed
close FreshSession          {prf = CloseFromFresh}         = EndSession
close (AuthSession _)       {prf = CloseFromAuthenticated} = EndSession
close DoneSession           {prf = CloseFromCommitted}     = EndSession
close AbortedSession        {prf = CloseFromRolledBack}    = EndSession

-- ============================================================================
-- Protocol Names
-- ============================================================================

||| Named protocols that correspond to WITH SESSION clauses.
||| Each protocol restricts which state transitions are available.
public export
data Protocol : Type where
  ReadOnlyProtocol  : Protocol
  MutationProtocol  : Protocol
  StreamProtocol    : Protocol
  BatchProtocol     : Protocol

public export
Show Protocol where
  show ReadOnlyProtocol  = "ReadOnlyProtocol"
  show MutationProtocol  = "MutationProtocol"
  show StreamProtocol    = "StreamProtocol"
  show BatchProtocol     = "BatchProtocol"

-- ============================================================================
-- Protocol Compliance
-- ============================================================================

||| Proof that a state transition is allowed under a given protocol.
||| ReadOnly prohibits Write effects; Mutation allows all; etc.
public export
data AllowedTransition : Protocol -> SessionState -> SessionState -> Type where
  ||| ReadOnly: can authenticate, begin read-only tx, query, commit, close
  ROAuth   : AllowedTransition ReadOnlyProtocol Fresh Authenticated
  ROBegin  : AllowedTransition ReadOnlyProtocol Authenticated InTransaction
  ROQuery  : AllowedTransition ReadOnlyProtocol InTransaction InTransaction
  ROCommit : AllowedTransition ReadOnlyProtocol InTransaction Committed
  ROClose  : AllowedTransition ReadOnlyProtocol Committed Closed

  ||| Mutation: all transitions allowed
  MutAuth     : AllowedTransition MutationProtocol Fresh Authenticated
  MutBegin    : AllowedTransition MutationProtocol Authenticated InTransaction
  MutQuery    : AllowedTransition MutationProtocol InTransaction InTransaction
  MutCommit   : AllowedTransition MutationProtocol InTransaction Committed
  MutRollback : AllowedTransition MutationProtocol InTransaction RolledBack
  MutClose    : AllowedTransition MutationProtocol Committed Closed
  MutCloseRB  : AllowedTransition MutationProtocol RolledBack Closed

-- ============================================================================
-- Example: Complete ReadOnly Session
-- ============================================================================

||| A complete read-only session: authenticate, begin, query, commit, close.
||| The type system ensures the protocol is followed exactly.
public export
readOnlyExample : SessionImpl Fresh -> Either String (SessionImpl Closed)
readOnlyExample fresh =
  case auth fresh of
    Left err => Left err
    Right authed =>
      let txSession = beginTx authed
          (_, txSession2) = query txSession
      in case commit txSession2 of
           Left err => Left err
           Right committed => Right (close committed)
