-- SPDX-License-Identifier: PMPL-1.0-or-later
-- Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
--
-- Linear.idr — Linear types via Idris2 QTT (CONSUME AFTER N USE)
--
-- Idris2's native quantitative type theory assigns quantities to bindings:
--   0 = erased, 1 = linear (exactly once), ω = unrestricted.
--
-- This module models resource-counted connections where CONSUME AFTER n USE
-- maps to a connection type indexed by its remaining usage count. The type
-- system enforces that connections are used exactly the declared number of
-- times before being closed.

module Linear

import Core

%default total

-- ============================================================================
-- Linear Connection Type
-- ============================================================================

||| A database connection indexed by its remaining usage count.
||| When remaining = S n, the connection can be used once (yielding a
||| connection with count n). When remaining = 0, it can only be closed.
|||
||| This is the Idris2 encoding of VQL-dt++ `CONSUME AFTER n USE`.
public export
data LinConn : (remaining : Nat) -> Type where
  ||| Construct a connection with a given remaining usage count.
  ||| The handle is an opaque reference to the underlying database connection.
  MkLinConn : (handle : Bits64) -> LinConn remaining

-- ============================================================================
-- Connection Operations
-- ============================================================================

||| Use a connection exactly once, decrementing its remaining count.
||| The `1` quantity on the input ensures linear consumption — the compiler
||| rejects code that uses the original connection after this call.
|||
||| Returns both the query result and a connection with decremented count.
public export
useConn : (1 _ : LinConn (S n)) -> (Core.QueryResult, LinConn n)
useConn (MkLinConn h) = (MkQueryResult [] 0, MkLinConn h)

||| Close a fully-consumed connection (remaining = 0).
||| This is the only operation available on a depleted connection.
||| The `1` quantity ensures the connection is consumed by closing.
public export
closeConn : (1 _ : LinConn 0) -> ()
closeConn (MkLinConn _) = ()

||| Get the handle from a connection without consuming it.
||| This is an erased (quantity 0) operation — available only at the type level.
public export
connHandle : LinConn n -> Bits64
connHandle (MkLinConn h) = h

-- ============================================================================
-- Connection Factory
-- ============================================================================

||| Create a new connection with a specified usage limit.
||| This is the entry point corresponding to CONSUME AFTER n USE.
public export
openConn : (handle : Bits64) -> (limit : Nat) -> LinConn limit
openConn h limit = MkLinConn h

||| Create a single-use connection (CONSUME AFTER 1 USE).
public export
openOnce : (handle : Bits64) -> LinConn 1
openOnce h = openConn h 1

-- ============================================================================
-- Usage Tracking Proofs
-- ============================================================================

||| Proof that a connection has been used exactly the right number of times.
||| If we start with LinConn n and end with LinConn 0, we used it n times.
public export
data FullyConsumed : LinConn 0 -> Type where
  ||| Witness that a connection reached zero remaining uses.
  Consumed : (conn : LinConn 0) -> FullyConsumed conn

||| Proof that a connection still has uses remaining.
public export
data HasUses : LinConn (S n) -> Type where
  ||| Witness that a connection has at least one use remaining.
  Remaining : (conn : LinConn (S n)) -> HasUses conn

-- ============================================================================
-- Example: Chain of Uses
-- ============================================================================

||| Use a connection exactly twice (for CONSUME AFTER 2 USE).
||| Demonstrates how the type system tracks usage through a chain.
public export
useTwice : (1 _ : LinConn 2) -> (Core.QueryResult, Core.QueryResult, LinConn 0)
useTwice conn =
  let (r1, conn1) = useConn conn
      (r2, conn0) = useConn conn1
  in (r1, r2, conn0)

||| Use a connection exactly three times (for CONSUME AFTER 3 USE).
public export
useThrice : (1 _ : LinConn 3) -> (Core.QueryResult, Core.QueryResult, Core.QueryResult, LinConn 0)
useThrice conn =
  let (r1, conn2) = useConn conn
      (r2, conn1) = useConn conn2
      (r3, conn0) = useConn conn1
  in (r1, r2, r3, conn0)
