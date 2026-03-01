-- SPDX-License-Identifier: PMPL-1.0-or-later
-- Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
--
-- TestLinear.idr — Type-level tests for Linear types extension
--
-- These are compile-time tests: if this module type-checks, the tests pass.
-- The type system enforces that connections are used exactly the declared
-- number of times.

module TestLinear

import Core
import Linear

%default total

-- ============================================================================
-- Test: Single-use connection (CONSUME AFTER 1 USE)
-- ============================================================================

-- Create a single-use connection, use it once, close it.
-- This should type-check because we use the connection exactly once.
testSingleUse : ()
testSingleUse =
  let conn = openOnce 42
      (_, conn0) = useConn conn
  in closeConn conn0

-- ============================================================================
-- Test: Multi-use connection (CONSUME AFTER 2 USE)
-- ============================================================================

-- Create a dual-use connection, use it twice, close it.
testDualUse : ()
testDualUse =
  let conn = openConn 42 2
      (_, conn1) = useConn conn
      (_, conn0) = useConn conn1
  in closeConn conn0

-- ============================================================================
-- Test: useTwice helper
-- ============================================================================

-- Verify the useTwice function type-checks with a LinConn 2.
testUseTwice : (QueryResult, QueryResult, LinConn 0)
testUseTwice = useTwice (openConn 42 2)

-- ============================================================================
-- Test: useThrice helper
-- ============================================================================

-- Verify the useThrice function type-checks with a LinConn 3.
testUseThrice : (QueryResult, QueryResult, QueryResult, LinConn 0)
testUseThrice = useThrice (openConn 42 3)

-- ============================================================================
-- Test: FullyConsumed proof
-- ============================================================================

-- Verify we can construct a FullyConsumed proof for a depleted connection.
testFullyConsumed : FullyConsumed (MkLinConn 0)
testFullyConsumed = Consumed (MkLinConn 0)

-- ============================================================================
-- Test: HasUses proof
-- ============================================================================

-- Verify we can construct a HasUses proof for a live connection.
testHasUses : HasUses (MkLinConn {remaining = 3} 42)
testHasUses = Remaining (MkLinConn 42)

-- ============================================================================
-- Negative test (commented — would fail to type-check, as expected):
-- ============================================================================

-- The following would NOT type-check because we try to use a single-use
-- connection twice:
--
-- testDoubleUse : ()
-- testDoubleUse =
--   let conn = openOnce 42
--       (_, conn0) = useConn conn
--       (_, conn1) = useConn conn   -- ERROR: conn already consumed
--   in closeConn conn1
