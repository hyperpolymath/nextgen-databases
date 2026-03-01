-- SPDX-License-Identifier: PMPL-1.0-or-later
-- Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
--
-- Checker.idr — Unified type checker composing all six extensions
--
-- This module ties together the individual extension checkers into a
-- unified VQL-dt++ type checking pipeline. A query with any combination
-- of the 6 extension clauses is validated by composing the relevant checks.

module Checker

import Core
import Linear
import Session
import Effects
import Modal
import ProofCarrying
import Quantitative
import Data.Nat

%default total

-- ============================================================================
-- Extension Annotations
-- ============================================================================

||| A parsed VQL-dt++ query's extension annotations. Each field is optional
||| (None means the clause was not present in the query).
public export
record ExtensionAnnotations where
  constructor MkAnnotations
  ||| CONSUME AFTER n USE — resource counting
  consumeAfter  : Maybe Nat
  ||| WITH SESSION protocol — session protocol name
  sessionProto  : Maybe String
  ||| EFFECTS { ... } — declared effect set
  declaredEffects : Maybe (List EffectLabel)
  ||| IN TRANSACTION state — modal scope state
  txState       : Maybe String
  ||| PROOF ATTACHED theorem — proof attachment
  attachedProof : Maybe String
  ||| USAGE LIMIT n — resource budget
  usageLimit    : Maybe Nat

||| Empty annotations (no extension clauses present).
public export
noAnnotations : ExtensionAnnotations
noAnnotations = MkAnnotations Nothing Nothing Nothing Nothing Nothing Nothing

-- ============================================================================
-- Check Results
-- ============================================================================

||| Result of checking a single extension. Either passes or fails with
||| a descriptive error.
public export
CheckResult : Type
CheckResult = Either TQLError ()

||| Combine two check results. If either fails, the combined result fails.
public export
andCheck : CheckResult -> CheckResult -> CheckResult
andCheck (Left e) _ = Left e
andCheck _ (Left e) = Left e
andCheck (Right ()) (Right ()) = Right ()

-- ============================================================================
-- Individual Extension Checks
-- ============================================================================

||| Check the CONSUME AFTER clause. Validates that the usage count is
||| positive (CONSUME AFTER 0 USE is meaningless).
public export
checkConsume : Maybe Nat -> CheckResult
checkConsume Nothing = Right ()
checkConsume (Just Z) = Left (LinearityViolation "CONSUME AFTER 0 USE is invalid — must be positive")
checkConsume (Just (S _)) = Right ()

||| Check the WITH SESSION clause. Validates the protocol name is recognised.
public export
checkSession : Maybe String -> CheckResult
checkSession Nothing = Right ()
checkSession (Just "ReadOnlyProtocol") = Right ()
checkSession (Just "MutationProtocol") = Right ()
checkSession (Just "StreamProtocol")   = Right ()
checkSession (Just "BatchProtocol")    = Right ()
checkSession (Just name) = Left (SessionViolation ("Unknown protocol: " ++ name))

||| Check the EFFECTS clause. Validates that all effect names are recognised.
public export
checkEffects : Maybe (List EffectLabel) -> CheckResult
checkEffects Nothing = Right ()
checkEffects (Just []) = Left (EffectViolation "Empty effect set — use no clause instead")
checkEffects (Just (_ :: _)) = Right ()

||| Check the IN TRANSACTION clause. Validates the transaction state.
public export
checkModal : Maybe String -> CheckResult
checkModal Nothing = Right ()
checkModal (Just "Fresh")        = Right ()
checkModal (Just "Active")       = Right ()
checkModal (Just "Committed")    = Right ()
checkModal (Just "RolledBack")   = Right ()
checkModal (Just "ReadSnapshot") = Right ()
checkModal (Just name) = Left (ModalViolation ("Unknown transaction state: " ++ name))

||| Check the PROOF ATTACHED clause. Validates the theorem name is non-empty.
public export
checkProofAttached : Maybe String -> CheckResult
checkProofAttached Nothing = Right ()
checkProofAttached (Just "") = Left (ProofViolation "PROOF ATTACHED requires a theorem name")
checkProofAttached (Just _) = Right ()

||| Check the USAGE LIMIT clause. Validates the limit is positive and
||| consistent with CONSUME AFTER if both are present.
public export
checkUsage : Maybe Nat -> Maybe Nat -> CheckResult
checkUsage Nothing Nothing = Right ()
checkUsage (Just Z) _ = Left (UsageViolation "USAGE LIMIT 0 is invalid — must be positive")
checkUsage (Just (S _)) _ = Right ()
checkUsage Nothing _ = Right ()

-- ============================================================================
-- Unified Checker
-- ============================================================================

||| Run all extension checks on a set of annotations. Returns Right ()
||| if all checks pass, or Left with the first error encountered.
public export
checkAll : ExtensionAnnotations -> CheckResult
checkAll ann =
  andCheck (checkConsume ann.consumeAfter)
    (andCheck (checkSession ann.sessionProto)
      (andCheck (checkEffects ann.declaredEffects)
        (andCheck (checkModal ann.txState)
          (andCheck (checkProofAttached ann.attachedProof)
            (checkUsage ann.usageLimit ann.consumeAfter)))))

-- ============================================================================
-- Cross-Extension Consistency
-- ============================================================================

||| Check that CONSUME AFTER and USAGE LIMIT are consistent when both present.
||| USAGE LIMIT should be >= CONSUME AFTER (since CONSUME is per-connection
||| while USAGE is per-query-plan).
public export
checkConsistency : ExtensionAnnotations -> CheckResult
checkConsistency ann =
  case (ann.consumeAfter, ann.usageLimit) of
    (Just consume, Just limit) =>
      case isLTE consume limit of
        Yes _ => Right ()
        No  _ => Left (UsageViolation
          ("USAGE LIMIT (" ++ show limit ++ ") must be >= CONSUME AFTER ("
           ++ show consume ++ ")"))
    _ => Right ()

||| Full validation: individual checks + cross-extension consistency.
public export
validate : ExtensionAnnotations -> CheckResult
validate ann = andCheck (checkAll ann) (checkConsistency ann)

-- ============================================================================
-- Example: Validate a maximal query
-- ============================================================================

||| Example annotations for a query using all 6 extensions.
public export
maximalAnnotations : ExtensionAnnotations
maximalAnnotations = MkAnnotations
  (Just 1)                           -- CONSUME AFTER 1 USE
  (Just "ReadOnlyProtocol")          -- WITH SESSION ReadOnlyProtocol
  (Just [Read, Cite])                -- EFFECTS { Read, Cite }
  (Just "Active")                    -- IN TRANSACTION Active
  (Just "IntegrityTheorem")          -- PROOF ATTACHED IntegrityTheorem
  (Just 100)                         -- USAGE LIMIT 100

||| Validate the maximal example. Should pass.
public export
maximalCheck : CheckResult
maximalCheck = validate maximalAnnotations
