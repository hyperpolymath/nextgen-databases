-- SPDX-License-Identifier: PMPL-1.0-or-later
-- Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
--
-- TestSession.idr — Type-level tests for Session types extension
--
-- Compile-time tests: if this module type-checks, the session protocol
-- state machine is correct. The indexed types prevent illegal state
-- transitions.

module TestSession

import Core
import Session

%default total

-- ============================================================================
-- Test: Complete read-only session flow
-- ============================================================================

-- Fresh → Authenticated → InTransaction → Committed → Closed
-- This is the happy path for a read-only session.
testReadOnlyFlow : Either String (SessionImpl Closed)
testReadOnlyFlow = readOnlyExample FreshSession

-- ============================================================================
-- Test: Session with rollback
-- ============================================================================

-- Fresh → Authenticated → InTransaction → RolledBack → Closed
testRollbackFlow : SessionImpl Closed
testRollbackFlow =
  let authed = AuthSession "test-token"
      tx = beginTx authed
      rolled = rollback tx
  in close rolled

-- ============================================================================
-- Test: Authenticate then close (no transaction)
-- ============================================================================

-- Fresh → Authenticated → Closed
testAuthAndClose : SessionImpl Closed
testAuthAndClose =
  let authed = AuthSession "test-token"
  in close authed

-- ============================================================================
-- Test: Abandon fresh session
-- ============================================================================

-- Fresh → Closed (abandoned without authentication)
testAbandon : SessionImpl Closed
testAbandon = close FreshSession

-- ============================================================================
-- Test: Multiple queries in transaction
-- ============================================================================

-- Fresh → Authenticated → InTransaction → (query × 3) → Committed → Closed
testMultiQuery : Either String (SessionImpl Closed)
testMultiQuery =
  let authed = AuthSession "test-token"
      tx = beginTx authed
      (_, tx2) = query tx
      (_, tx3) = query tx2
      (_, tx4) = query tx3
  in case commit tx4 of
       Left err => Left err
       Right done => Right (close done)

-- ============================================================================
-- Test: CanClose proofs exist for valid states
-- ============================================================================

-- Verify CanClose proofs can be constructed for valid states.
testCanCloseFresh : CanClose Fresh
testCanCloseFresh = CloseFromFresh

testCanCloseAuth : CanClose Authenticated
testCanCloseAuth = CloseFromAuthenticated

testCanCloseCommitted : CanClose Committed
testCanCloseCommitted = CloseFromCommitted

testCanCloseRolledBack : CanClose RolledBack
testCanCloseRolledBack = CloseFromRolledBack

-- ============================================================================
-- Test: Protocol names
-- ============================================================================

testProtocolShow : List String
testProtocolShow =
  [ show ReadOnlyProtocol
  , show MutationProtocol
  , show StreamProtocol
  , show BatchProtocol
  ]

-- ============================================================================
-- Negative test (commented — would fail to type-check, as expected):
-- ============================================================================

-- Cannot close an InTransaction session (no CanClose InTransaction):
--
-- testBadClose : SessionImpl Closed
-- testBadClose =
--   let tx = TxSession "tx-001"
--   in close tx  -- ERROR: No auto-proof for CanClose InTransaction

-- Cannot query a Fresh session:
--
-- testBadQuery : (QueryResult, SessionImpl Fresh)
-- testBadQuery = query FreshSession  -- ERROR: query requires InTransaction
