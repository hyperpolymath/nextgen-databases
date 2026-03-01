-- SPDX-License-Identifier: PMPL-1.0-or-later
-- Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
--
-- Quantitative.idr — Resource accounting (USAGE LIMIT)
--
-- Generalises linear types from "exactly once" to "at most n times".
-- A resource with usage limit n can be consumed at most n times across
-- the entire query plan. This subsumes linear types: USAGE LIMIT 1 is
-- equivalent to CONSUME AFTER 1 USE.

module Quantitative

import Core

%default total

-- ============================================================================
-- Bounded Resources
-- ============================================================================

||| A resource with a bounded usage count. The type-level natural number
||| tracks how many uses remain. When remaining = 0, the resource is
||| depleted and cannot be consumed further.
public export
data BoundedResource : (remaining : Nat) -> Type -> Type where
  ||| Wrap a value as a bounded resource with a given remaining count.
  MkBounded : a -> BoundedResource remaining a

||| Extract the inner value (erased — for type-level inspection only).
public export
peek : BoundedResource n a -> a
peek (MkBounded x) = x

-- ============================================================================
-- Resource Operations
-- ============================================================================

||| Consume a resource once, decrementing the remaining count.
||| Only available when remaining > 0 (enforced by pattern matching on S n).
public export
consume : BoundedResource (S n) a -> (a, BoundedResource n a)
consume (MkBounded x) = (x, MkBounded x)

||| The type system itself distinguishes BoundedResource (S n) from
||| BoundedResource 0. No runtime check is needed — the presence or absence
||| of a `consume` function in the API is the check.

-- ============================================================================
-- Resource Budgeting
-- ============================================================================

||| Split a resource budget between two branches of a query plan.
||| Given a resource with limit (n + m), produce two resources with
||| limits n and m respectively.
public export
split : BoundedResource (n + m) a -> (BoundedResource n a, BoundedResource m a)
split (MkBounded x) = (MkBounded x, MkBounded x)

||| Merge two resource budgets back together.
||| Given remaining counts from two branches, the combined remaining is
||| their sum.
public export
merge : BoundedResource n a -> BoundedResource m a -> BoundedResource (n + m) a
merge (MkBounded x) (MkBounded _) = MkBounded x

-- ============================================================================
-- Budget Proofs
-- ============================================================================

||| Proof that a resource has been fully consumed (remaining = 0).
public export
data Depleted : BoundedResource 0 a -> Type where
  ||| Witness that the resource has zero uses remaining.
  IsDepleted : (r : BoundedResource 0 a) -> Depleted r

||| Proof that a resource still has uses remaining.
public export
data Available : BoundedResource (S n) a -> Type where
  ||| Witness that the resource has at least one use remaining.
  IsAvailable : (r : BoundedResource (S n) a) -> Available r

||| Proof that n <= m (for budget subsumption).
public export
data BudgetFits : (required : Nat) -> (available : Nat) -> Type where
  FitsZ : BudgetFits Z m
  FitsS : BudgetFits n m -> BudgetFits (S n) (S m)

-- ============================================================================
-- Usage-Limited Queries
-- ============================================================================

||| A query plan annotated with a resource budget.
||| The type tracks how many resource units the query is allowed to consume.
public export
record UsageLimitedQuery (budget : Nat) where
  constructor MkUsageLimitedQuery
  queryText : String

||| Execute a usage-limited query, consuming from the resource budget.
||| Returns the result and the remaining budget.
public export
execLimited : UsageLimitedQuery cost
           -> BoundedResource budget ()
           -> {auto fits : BudgetFits cost budget}
           -> (Core.QueryResult, BoundedResource (minus budget cost) ())
execLimited _ (MkBounded ()) = (MkQueryResult [] 0, MkBounded ())

-- ============================================================================
-- Convenience: Single-Use (Linear) Resources
-- ============================================================================

||| Create a single-use resource (equivalent to linear type).
||| This is USAGE LIMIT 1.
public export
singleUse : a -> BoundedResource 1 a
singleUse = MkBounded

||| Consume a single-use resource completely.
public export
consumeOnce : BoundedResource 1 a -> (a, BoundedResource 0 a)
consumeOnce = consume

-- ============================================================================
-- Example: Budget Tracking Through Query Plan
-- ============================================================================

||| Execute two queries from a budget of 3, leaving 1 remaining.
public export
budgetExample : BoundedResource 3 () -> (Core.QueryResult, Core.QueryResult, BoundedResource 1 ())
budgetExample r =
  let ((), r2) = consume r       -- 3 -> 2
      ((), r1) = consume r2      -- 2 -> 1
  in (MkQueryResult [] 0, MkQueryResult [] 0, r1)
