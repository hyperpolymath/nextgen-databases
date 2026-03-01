-- SPDX-License-Identifier: PMPL-1.0-or-later
-- Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
--
-- TestQuantitative.idr — Type-level tests for Quantitative types extension
--
-- Compile-time tests for bounded resource accounting. If this module
-- type-checks, the resource budget system is correct.

module TestQuantitative

import Core
import Quantitative

%default total

-- ============================================================================
-- Test: Create and consume a single-use resource
-- ============================================================================

testSingleConsume : ((), BoundedResource 0 ())
testSingleConsume =
  let r = singleUse ()
  in consumeOnce r

-- ============================================================================
-- Test: Create and consume a multi-use resource
-- ============================================================================

testMultiConsume : ((), (), BoundedResource 0 ())
testMultiConsume =
  let r = MkBounded {remaining = 2} ()
      (_, r1) = consume r   -- 2 -> 1
      (_, r0) = consume r1  -- 1 -> 0
  in ((), (), r0)

-- ============================================================================
-- Test: Budget tracking through query plan
-- ============================================================================

testBudgetTracking : (QueryResult, QueryResult, BoundedResource 1 ())
testBudgetTracking = budgetExample (MkBounded ())

-- ============================================================================
-- Test: Available resource can be consumed
-- ============================================================================

testConsumeFromThree : ((), BoundedResource 2 ())
testConsumeFromThree = consume (MkBounded {remaining = 3} ())

-- ============================================================================
-- Test: Depleted proof
-- ============================================================================

testDepleted : Depleted (MkBounded {remaining = 0} ())
testDepleted = IsDepleted (MkBounded ())

-- ============================================================================
-- Test: Available proof
-- ============================================================================

testAvailable : Available (MkBounded {remaining = 5} ())
testAvailable = IsAvailable (MkBounded ())

-- ============================================================================
-- Test: Split and merge
-- ============================================================================

-- Split a budget of 5 into (3, 2) and merge back.
testSplitMerge : BoundedResource 5 ()
testSplitMerge =
  let r = MkBounded {remaining = 5} ()
  in splitMergeIdentity r

-- ============================================================================
-- Test: BudgetFits proofs
-- ============================================================================

-- 0 fits in any budget
testFitsZero : BudgetFits 0 10
testFitsZero = FitsZ

-- 1 fits in budget of 1
testFitsOne : BudgetFits 1 1
testFitsOne = FitsS FitsZ

-- 2 fits in budget of 3
testFitsTwo : BudgetFits 2 3
testFitsTwo = FitsS (FitsS FitsZ)

-- ============================================================================
-- Test: peek preserves value
-- ============================================================================

testPeek : ()
testPeek = peek (MkBounded {remaining = 3} ())

-- ============================================================================
-- Negative test (commented — would fail to type-check, as expected):
-- ============================================================================

-- Cannot consume a depleted resource:
--
-- testBadConsume : ((), BoundedResource 0 ())
-- testBadConsume =
--   let r = MkBounded {remaining = 0} ()
--   in consume r  -- ERROR: No match for BoundedResource (S n) when n=0

-- Budget 1 does not fit in 0:
--
-- testBadFit : BudgetFits 1 0
-- testBadFit = ?impossible  -- Cannot construct this proof
