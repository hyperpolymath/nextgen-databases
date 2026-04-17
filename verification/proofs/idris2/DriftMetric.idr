-- SPDX-License-Identifier: PMPL-1.0-or-later
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
-- DriftMetric.idr - Formal proof that the VeriSimDB drift metric is a proper
-- metric (reflexivity, symmetry, triangle inequality) and that threshold
-- detection is sound.
--
-- V8 in standards/docs/proofs/spec-templates/T1-critical/verisimdb.md.
--
-- Corresponds to: rust-core/verisim-drift/src/calculator.rs.
--
-- Model: each Octad modality emits a fixed-width feature vector over Bool
-- (feature-present / feature-absent). Drift is Hamming distance:
-- the count of feature positions where two snapshots disagree.
-- This is a metric (non-negative, reflexive, symmetric, triangle-inequal)
-- and the threshold-detection predicate is sound by construction.

module DriftMetric

import Data.Nat
import Data.Vect

%default total

------------------------------------------------------------------------
-- Boolean xor primitive
------------------------------------------------------------------------

||| Exclusive or on Bool: True iff arguments differ.
public export
bxor : Bool -> Bool -> Bool
bxor False False = False
bxor False True  = True
bxor True  False = True
bxor True  True  = False

||| xor is commutative.
public export
bxorCommutative : (a, b : Bool) -> bxor a b = bxor b a
bxorCommutative False False = Refl
bxorCommutative False True  = Refl
bxorCommutative True  False = Refl
bxorCommutative True  True  = Refl

||| Self-xor is always False (a bit never differs from itself).
public export
bxorSelfZero : (a : Bool) -> bxor a a = False
bxorSelfZero False = Refl
bxorSelfZero True  = Refl

------------------------------------------------------------------------
-- Counting True bits
------------------------------------------------------------------------

||| Convert a Bool to 0 or 1.
public export
ifB : Bool -> Nat
ifB False = 0
ifB True  = 1

||| Count True bits in a Bool vector.
public export
countTrue : {n : Nat} -> Vect n Bool -> Nat
countTrue [] = 0
countTrue (True  :: xs) = S (countTrue xs)
countTrue (False :: xs) = countTrue xs

||| countTrue on a single element.
public export
countTrueSingle : (b : Bool) -> countTrue [b] = ifB b
countTrueSingle False = Refl
countTrueSingle True  = Refl

------------------------------------------------------------------------
-- Drift metric: Hamming distance
------------------------------------------------------------------------

||| A modality snapshot: presence/absence of n features.
public export
State : (n : Nat) -> Type
State n = Vect n Bool

||| Drift is the count of positions where two states disagree.
||| This is Hamming distance on Bool vectors.
public export
drift : {n : Nat} -> State n -> State n -> Nat
drift xs ys = countTrue (zipWith bxor xs ys)

------------------------------------------------------------------------
-- Metric axiom 1: identity of indiscernibles (d(x, x) = 0)
------------------------------------------------------------------------

||| Drift from a state to itself is zero.
||| Every position xor-against-itself is False, so no bits are counted.
public export
driftSelf : {n : Nat} -> (xs : State n) -> drift xs xs = 0
driftSelf [] = Refl
driftSelf (False :: xs) =
  -- zipWith head: bxor False False = False, so LHS = countTrue (False :: rest)
  rewrite driftSelf xs in Refl
driftSelf (True :: xs) =
  -- zipWith head: bxor True True = False, so LHS = countTrue (False :: rest)
  rewrite driftSelf xs in Refl

------------------------------------------------------------------------
-- Metric axiom 2: symmetry (d(x, y) = d(y, x))
------------------------------------------------------------------------

||| Pointwise symmetry of zipWith bxor: xs xor ys = ys xor xs at each position.
||| Qualified `DriftMetric.bxor` prevents implicit binding of the lowercase name.
public export
zipWithBxorSym : {n : Nat} -> (xs, ys : Vect n Bool)
              -> zipWith DriftMetric.bxor xs ys = zipWith DriftMetric.bxor ys xs
zipWithBxorSym [] [] = Refl
zipWithBxorSym (x :: xs) (y :: ys) =
  rewrite bxorCommutative x y in
  rewrite zipWithBxorSym xs ys in
  Refl

||| Drift is symmetric: swapping the two states gives the same count.
public export
driftSym : {n : Nat} -> (xs, ys : State n) -> drift xs ys = drift ys xs
driftSym xs ys = cong countTrue (zipWithBxorSym xs ys)

------------------------------------------------------------------------
-- Metric axiom 3: triangle inequality
------------------------------------------------------------------------

||| Per-position triangle inequality on xor:
|||   if x != z, then x != y or y != z.
||| Equivalently: ifB (bxor x z) <= ifB (bxor x y) + ifB (bxor y z).
||| Exhaustive over the 8 Bool combinations.
public export
xorTriangleBit : (x, y, z : Bool)
              -> LTE (ifB (bxor x z)) (ifB (bxor x y) + ifB (bxor y z))
xorTriangleBit False False False = LTEZero
xorTriangleBit False False True  = LTESucc LTEZero     -- (F,F,T): L=1, R=0+1
xorTriangleBit False True  False = LTEZero             -- (F,T,F): L=0, R=1+1
xorTriangleBit False True  True  = LTESucc LTEZero     -- (F,T,T): L=1, R=1+0
xorTriangleBit True  False False = LTESucc LTEZero     -- (T,F,F): L=1, R=1+0
xorTriangleBit True  False True  = LTEZero             -- (T,F,T): L=0, R=1+1
xorTriangleBit True  True  False = LTESucc LTEZero     -- (T,T,F): L=1, R=0+1
xorTriangleBit True  True  True  = LTEZero

||| Monotonicity of addition on both sides.
plusLteMonoBoth : {c : Nat} -> LTE a c -> LTE b d -> LTE (a + b) (c + d)
plusLteMonoBoth LTEZero q = go q
  where
    go : {c' : Nat} -> LTE b d -> LTE b (c' + d)
    go {c' = Z}      prf = prf
    go {c' = S c''}  prf = lteSuccRight (go {c' = c''} prf)
plusLteMonoBoth (LTESucc p) q = LTESucc (plusLteMonoBoth p q)

||| Helper: countTrue of a cons = ifB head + countTrue tail.
public export
countTrueCons : {n : Nat} -> (b : Bool) -> (rest : Vect n Bool)
             -> countTrue (b :: rest) = ifB b + countTrue rest
countTrueCons False rest = Refl
countTrueCons True  rest = Refl

||| Rearrangement used in the triangle step:
|||   (a + c) + (b + d) = (a + b) + (c + d)
||| via associativity and commutativity on Nat.
plusSwap : (a, b, c, d : Nat) -> (a + c) + (b + d) = (a + b) + (c + d)
plusSwap a b c d =
  rewrite sym (plusAssociative a c (b + d)) in
  rewrite plusAssociative c b d in
  rewrite plusCommutative c b in
  rewrite sym (plusAssociative b c d) in
  rewrite plusAssociative a b (c + d) in
  Refl

||| Triangle inequality:
|||   drift x z <= drift x y + drift y z
||| Proof: per-position case split on (x_i, y_i, z_i), combined with
|||        monotonicity of Nat addition over vector zipWith.
public export
driftTriangle : {n : Nat}
             -> (xs, ys, zs : State n)
             -> LTE (drift xs zs) (drift xs ys + drift ys zs)
driftTriangle [] [] [] = LTEZero
driftTriangle (x :: xs) (y :: ys) (z :: zs) =
  let
      -- Per-position bit inequality.
      bitPrf : LTE (ifB (bxor x z)) (ifB (bxor x y) + ifB (bxor y z))
      bitPrf = xorTriangleBit x y z
      -- Recursive inequality on the tails.
      tailPrf : LTE (drift xs zs) (drift xs ys + drift ys zs)
      tailPrf = driftTriangle xs ys zs
      -- Combine them: bit + tail on both sides.
      combined : LTE (ifB (bxor x z) + drift xs zs)
                     ((ifB (bxor x y) + ifB (bxor y z)) +
                      (drift xs ys + drift ys zs))
      combined = plusLteMonoBoth bitPrf tailPrf
      -- Re-associate the RHS: (xy + yz) + (txy + tyz) = (xy + txy) + (yz + tyz).
      rearranged : LTE (ifB (bxor x z) + drift xs zs)
                       ((ifB (bxor x y) + drift xs ys) +
                        (ifB (bxor y z) + drift ys zs))
      rearranged =
        -- plusSwap a b c d : (a+c)+(b+d) = (a+b)+(c+d).
        -- With a=xy, b=yz, c=drift_xy, d=drift_yz: the LHS is the goal's
        -- shape and the RHS is combined's shape. Rewriting turns the goal
        -- into combined's type, then combined discharges it.
        rewrite plusSwap (ifB (bxor x y)) (ifB (bxor y z))
                         (drift xs ys) (drift ys zs)
        in combined
      -- LHS rewrites to drift (x::xs) (z::zs), and each RHS summand to
      -- drift (_::_) (_::_), via countTrueCons.
      lhsEq : drift (x :: xs) (z :: zs) = ifB (bxor x z) + drift xs zs
      lhsEq = countTrueCons (bxor x z) (zipWith bxor xs zs)
      rhsEq1 : drift (x :: xs) (y :: ys) = ifB (bxor x y) + drift xs ys
      rhsEq1 = countTrueCons (bxor x y) (zipWith bxor xs ys)
      rhsEq2 : drift (y :: ys) (z :: zs) = ifB (bxor y z) + drift ys zs
      rhsEq2 = countTrueCons (bxor y z) (zipWith bxor ys zs)
  in
  rewrite lhsEq in
  rewrite rhsEq1 in
  rewrite rhsEq2 in
  rearranged

------------------------------------------------------------------------
-- Threshold soundness
------------------------------------------------------------------------

||| Drift-detection predicate: fires when drift strictly exceeds threshold.
public export
driftExceeds : {n : Nat} -> State n -> State n -> (threshold : Nat) -> Bool
driftExceeds xs ys threshold =
  case isLTE (S threshold) (drift xs ys) of
    Yes _ => True
    No  _ => False

||| Threshold soundness: if drift strictly exceeds the threshold, the
||| detector fires. This is the intended direction — false positives
||| are impossible by construction (the `isLTE` branch decides exactly).
public export
driftExceedsSound : {n : Nat} -> (xs, ys : State n) -> (t : Nat)
                 -> LTE (S t) (drift xs ys)
                 -> driftExceeds xs ys t = True
driftExceedsSound xs ys t prf with (isLTE (S t) (drift xs ys))
  _ | Yes _ = Refl
  _ | No contra = absurd (contra prf)

||| Classical contrapositive on LTE over Nat: if S b does not fit under a,
||| then a fits under b. The `No` branch of `isLTE` supplies exactly this
||| negation, so the converse soundness proof below reduces to an application.
public export
notSuccLTEImpliesLTE : (a, b : Nat) -> Not (LTE (S b) a) -> LTE a b
notSuccLTEImpliesLTE Z _ _ = LTEZero
notSuccLTEImpliesLTE (S a') Z contra = absurd (contra (LTESucc LTEZero))
notSuccLTEImpliesLTE (S a') (S b') contra =
  LTESucc (notSuccLTEImpliesLTE a' b' (\lt => contra (LTESucc lt)))

||| Converse soundness: if the detector doesn't fire, drift does not exceed
||| the threshold. Together with driftExceedsSound this characterises the
||| predicate completely.
public export
driftExceedsComplete : {n : Nat} -> (xs, ys : State n) -> (t : Nat)
                    -> driftExceeds xs ys t = False
                    -> LTE (drift xs ys) t
driftExceedsComplete xs ys t prf with (isLTE (S t) (drift xs ys))
  _ | Yes _     = absurd prf
  _ | No contra = notSuccLTEImpliesLTE (drift xs ys) t contra
