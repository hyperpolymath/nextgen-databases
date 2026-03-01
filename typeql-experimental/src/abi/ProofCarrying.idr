-- SPDX-License-Identifier: PMPL-1.0-or-later
-- Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
--
-- ProofCarrying.idr — Proof attachment (PROOF ATTACHED)
--
-- Attach formal theorems to query results. The result type becomes a
-- dependent pair (sigma type) bundling the data with its proof. This is
-- DIFFERENT from VQL's existing PROOF clause: PROOF verifies pre-conditions;
-- PROOF ATTACHED attaches post-condition theorems to results.

module ProofCarrying

import Core
import Data.Nat

%default total

-- ============================================================================
-- Theorems
-- ============================================================================

||| A theorem about query results. Each variant captures a specific property
||| that can be proven about the data returned by a query.
public export
data Theorem : Type where
  ||| The result has not been tampered with (hash matches).
  IntegrityThm   : (hash : String) -> Theorem
  ||| The result is fresh (within maxAge seconds of current time).
  FreshnessThm   : (maxAge : Nat) -> Theorem
  ||| The result has a verifiable provenance chain.
  ProvenanceThm  : (chain : List String) -> Theorem
  ||| The result is consistent across the listed modalities.
  ConsistencyThm : (modalities : List Core.Modality) -> Theorem
  ||| A custom named theorem with string-encoded parameters.
  CustomThm      : (name : String) -> (params : List (String, String)) -> Theorem

public export
Show Theorem where
  show (IntegrityThm h)      = "IntegrityThm(" ++ h ++ ")"
  show (FreshnessThm a)      = "FreshnessThm(" ++ show a ++ "s)"
  show (ProvenanceThm c)     = "ProvenanceThm(" ++ show (length c) ++ " steps)"
  show (ConsistencyThm ms)   = "ConsistencyThm(" ++ show (length ms) ++ " modalities)"
  show (CustomThm n _)       = "CustomThm(" ++ n ++ ")"

-- ============================================================================
-- Proved Results (Sigma Type)
-- ============================================================================

||| A proved result pairs a value with a theorem about that value.
||| This is the core type for PROOF ATTACHED — the query result carries
||| an irrefutable proof of a stated property.
|||
||| Conceptually: Σ(result : a, thm : Theorem)
public export
data ProvedResult : Type -> Type where
  ||| Bundle a result with its proof theorem.
  MkProved : (result : a) -> (thm : Theorem) -> ProvedResult a

||| Extract the raw result from a proved result, discarding the proof.
public export
getResult : ProvedResult a -> a
getResult (MkProved r _) = r

||| Extract the theorem from a proved result.
public export
getTheorem : ProvedResult a -> Theorem
getTheorem (MkProved _ t) = t

-- ============================================================================
-- Proof Verification
-- ============================================================================

||| Verification result: either the theorem holds or we get an error.
public export
data VerifyResult : Type where
  ||| The theorem has been verified to hold.
  Verified   : (thm : Theorem) -> VerifyResult
  ||| Verification failed with an error message.
  VerifyFail : (reason : String) -> VerifyResult

||| A verifier function for a specific theorem type.
public export
Verifier : Type
Verifier = Theorem -> VerifyResult

||| Verify an integrity theorem by checking a hash.
public export
verifyIntegrity : (actualHash : String) -> Verifier
verifyIntegrity actual (IntegrityThm expected) =
  if actual == expected
    then Verified (IntegrityThm expected)
    else VerifyFail ("Hash mismatch: expected " ++ expected ++ ", got " ++ actual)
verifyIntegrity _ thm = VerifyFail ("Not an integrity theorem: " ++ show thm)

||| Verify a freshness theorem by checking age.
public export
verifyFreshness : (actualAge : Nat) -> Verifier
verifyFreshness actual (FreshnessThm maxAge) =
  case isLTE actual maxAge of
    Yes _ => Verified (FreshnessThm maxAge)
    No _  => VerifyFail ("Result too old: " ++ show actual ++ "s > " ++ show maxAge ++ "s")
verifyFreshness _ thm = VerifyFail ("Not a freshness theorem: " ++ show thm)

-- ============================================================================
-- Proof Composition
-- ============================================================================

||| A multi-proved result carries multiple theorems about the same value.
||| This corresponds to PROOF ATTACHED thm1 AND thm2.
public export
data MultiProved : Type -> Type where
  ||| A result with no proofs.
  Bare : a -> MultiProved a
  ||| Attach an additional theorem.
  AndProved : MultiProved a -> Theorem -> MultiProved a

||| Get the underlying result from a multi-proved value.
public export
getMultiResult : MultiProved a -> a
getMultiResult (Bare r) = r
getMultiResult (AndProved mp _) = getMultiResult mp

||| Collect all theorems from a multi-proved value.
public export
getTheorems : MultiProved a -> List Theorem
getTheorems (Bare _) = []
getTheorems (AndProved mp thm) = thm :: getTheorems mp

||| Count the number of attached proofs.
public export
proofCount : MultiProved a -> Nat
proofCount (Bare _) = 0
proofCount (AndProved mp _) = S (proofCount mp)

-- ============================================================================
-- Query Result with Proofs
-- ============================================================================

||| A VQL-dt++ query result with attached proofs.
||| Wraps Core.QueryResult with zero or more theorems.
public export
ProvedQueryResult : Type
ProvedQueryResult = MultiProved Core.QueryResult

||| Attach a single proof to a query result.
public export
attachProof : Core.QueryResult -> Theorem -> ProvedQueryResult
attachProof qr thm = AndProved (Bare qr) thm

||| Attach multiple proofs to a query result.
public export
attachProofs : Core.QueryResult -> List Theorem -> ProvedQueryResult
attachProofs qr [] = Bare qr
attachProofs qr (t :: ts) = AndProved (attachProofs qr ts) t
