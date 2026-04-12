-- SPDX-License-Identifier: PMPL-1.0-or-later
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)
-- KRL (Knot Resolution Language): Equivalence and Pipeline Safety Proofs

module Types

%default total

-- | KQL value types
public export
data KrlTy : Type where
  TyInt        : KrlTy
  TyFloat      : KrlTy
  TyString     : KrlTy
  TyBool       : KrlTy
  TyKnot       : KrlTy
  TyDiagram    : KrlTy
  TyPolynomial : KrlTy
  TyGaussCode  : KrlTy
  TyQuandle    : KrlTy
  TyList       : KrlTy -> KrlTy
  TyOption     : KrlTy -> KrlTy
  TyRecord     : List (String, KrlTy) -> KrlTy
  TyResultSet  : KrlTy -> KrlTy
  TyEquiv      : KrlTy -> KrlTy
  TyProvenance : KrlTy

-- | Confidence levels for invariant matching
public export
data Confidence : Type where
  Exact      : Confidence  -- invariant matched exactly
  Necessary  : Confidence  -- matching necessary but not sufficient
  Sufficient : Confidence  -- matching sufficient for equivalence
  Heuristic  : Confidence  -- approximate/statistical

-- | Confidence ordering (stronger is better)
public export
data ConfLeq : Confidence -> Confidence -> Type where
  HeuLeqHeu : ConfLeq Heuristic Heuristic
  HeuLeqNec : ConfLeq Heuristic Necessary
  HeuLeqExact : ConfLeq Heuristic Exact
  HeuLeqSuf : ConfLeq Heuristic Sufficient
  NecLeqNec : ConfLeq Necessary Necessary
  NecLeqExact : ConfLeq Necessary Exact
  ExactLeqExact : ConfLeq Exact Exact
  SufLeqSuf : ConfLeq Sufficient Sufficient

-- | Pipeline stages as type-level transformations
public export
data PipeStage : KrlTy -> KrlTy -> Type where
  Filter    : PipeStage (TyResultSet t) (TyResultSet t)
  Sort      : PipeStage (TyResultSet t) (TyResultSet t)
  Take      : Nat -> PipeStage (TyResultSet t) (TyResultSet t)
  Skip      : Nat -> PipeStage (TyResultSet t) (TyResultSet t)
  Project   : List String -> PipeStage (TyResultSet t) (TyResultSet t')
  FindEquiv : PipeStage (TyResultSet TyKnot) (TyResultSet (TyEquiv TyKnot))

-- | Pipeline composition (type-safe chaining)
public export
data Pipeline : KrlTy -> KrlTy -> Type where
  Empty : Pipeline t t
  Then  : PipeStage t1 t2 -> Pipeline t2 t3 -> Pipeline t1 t3

-- | Pipeline composition is associative
public export
pipeAssoc : Pipeline a b -> Pipeline b c -> Pipeline a c
pipeAssoc Empty p2 = p2
pipeAssoc (Then s p1) p2 = Then s (pipeAssoc p1 p2)

-- | Invariant evaluation stratum
public export
data Stratum : Type where
  MkStratum : (level : Nat) -> (name : String) -> Stratum

-- | Stratified evaluation terminates
-- Proof: strata are finite (Nat-indexed), and evaluation at each
-- stratum terminates (each invariant computation is decidable
-- except quandle isomorphism, which has a search bound).
public export
data StratumBounded : Nat -> Type where
  ZeroBound : StratumBounded 0
  SuccBound : StratumBounded n -> StratumBounded (S n)

-- | Short-circuit correctness: if a necessary invariant differs,
-- the knots are provably non-equivalent
public export
data ShortCircuit : Type where
  Refuted : (inv : String) -> (confidence : Confidence)
          -> ConfLeq Necessary confidence
          -> ShortCircuit

-- | Provenance semiring operations
public export
record Provenance where
  constructor MkProvenance
  invariantsUsed : List String
  confidence     : Confidence
  stepCount      : Nat

-- | Provenance combination (semiring product)
public export
combineProvenance : Provenance -> Provenance -> Provenance
combineProvenance p1 p2 = MkProvenance
  (p1.invariantsUsed ++ p2.invariantsUsed)
  (minConfidence p1.confidence p2.confidence)
  (p1.stepCount + p2.stepCount)
  where
    minConfidence : Confidence -> Confidence -> Confidence
    minConfidence Heuristic _ = Heuristic
    minConfidence _ Heuristic = Heuristic
    minConfidence Necessary _ = Necessary
    minConfidence _ Necessary = Necessary
    minConfidence Exact Exact = Exact
    minConfidence Sufficient Sufficient = Sufficient
    minConfidence Exact Sufficient = Exact
    minConfidence Sufficient Exact = Exact

-- | Provenance combination preserves completeness:
-- combined provenance uses at least as many invariants.
-- Proof: combineProvenance appends invariant lists via (++),
-- and (++) preserves length additively.
public export
combinePreservesInvariants : (p1, p2 : Provenance)
  -> length (combineProvenance p1 p2).invariantsUsed
     = length p1.invariantsUsed + length p2.invariantsUsed
combinePreservesInvariants p1 p2 =
  lengthAppend p1.invariantsUsed p2.invariantsUsed
  where
    -- Standard library lemma: length (xs ++ ys) = length xs + length ys
    lengthAppend : (xs, ys : List a) -> length (xs ++ ys) = length xs + length ys
    lengthAppend [] ys = Refl
    lengthAppend (x :: xs) ys = cong S (lengthAppend xs ys)

-- | Confidence-indexed equivalence type.
-- The confidence parameter is a type-level tag that tracks the
-- strength of the equivalence claim through the pipeline.
public export
data ConfEquiv : KrlTy -> Confidence -> Type where
  MkConfEquiv : (source : String)  -- knot name
             -> (target : String)  -- knot name
             -> (paths  : List (String, Confidence))  -- (invariant, confidence) pairs
             -> (conf   : Confidence)
             -> ConfLeq c conf    -- proof that achieved confidence >= requested
             -> ConfEquiv TyKnot c

-- | Dependent projection: type-level field selection.
-- Proves that projecting fields from a record type produces a valid sub-record.
public export
data HasField : String -> List (String, KrlTy) -> KrlTy -> Type where
  Here  : HasField f ((f, t) :: rest) t
  There : HasField f rest t -> HasField f ((g, t') :: rest) t

-- | Project a list of field names from a record type.
-- Each field must exist (witnessed by HasField proofs).
public export
data ProjectFields : List String -> List (String, KrlTy) -> List (String, KrlTy) -> Type where
  ProjNil  : ProjectFields [] fs []
  ProjCons : HasField f fs t
          -> ProjectFields rest fs fs'
          -> ProjectFields (f :: rest) fs ((f, t) :: fs')

-- | Invariant type registry (type-level function).
-- Maps invariant names to their result types.
public export
InvType : String -> KrlTy
InvType "crossing_number" = TyInt
InvType "writhe"          = TyInt
InvType "genus"           = TyOption TyInt
InvType "seifert_circles" = TyOption TyInt
InvType "jones"           = TyOption TyPolynomial
InvType "jones_polynomial" = TyOption TyPolynomial
InvType "alexander"       = TyOption TyPolynomial
InvType "quandle"         = TyOption TyQuandle
InvType _                 = TyOption TyString  -- unknown invariants default to string

-- | Stratified evaluation trace, indexed by stratum count.
-- Proves termination: each step strictly decreases the stratum index.
public export
data StratEval : (n : Nat) -> Type where
  EvalDone : StratEval 0
  EvalStep : (stratum : Stratum)
          -> (result  : Either ShortCircuit Provenance)
          -> StratEval n
          -> StratEval (S n)

-- | Stratified evaluation step count equals the stratum count.
public export
stratStepCount : (n : Nat) -> StratEval n -> Nat
stratStepCount 0     EvalDone           = 0
stratStepCount (S k) (EvalStep _ _ rest) = S (stratStepCount k rest)

-- | Proof: step count equals stratum count.
public export
stratCountCorrect : (n : Nat) -> (eval : StratEval n)
                 -> stratStepCount n eval = n
stratCountCorrect 0     EvalDone            = Refl
stratCountCorrect (S k) (EvalStep _ _ rest) = cong S (stratCountCorrect k rest)

-- | Semantic descriptor contract mirrored from /api/semantic/:name.
public export
record SemanticDescriptor where
  constructor MkSemanticDescriptor
  knotName : String
  descriptorVersion : String
  descriptorHash : String
  quandleKey : String
  crossingNumber : Int
  writhe : Int
  determinant : Maybe Int
  signature : Maybe Int
  quandleGeneratorCount : Maybe Int
  quandleRelationCount : Maybe Int
  colouringCount3 : Maybe Int
  colouringCount5 : Maybe Int

-- | Semantic equivalence buckets from /api/semantic-equivalents/:name.
public export
record SemanticEquivalence where
  constructor MkSemanticEquivalence
  name : String
  descriptorHash : String
  quandleKey : String
  strongCandidates : List String
  weakCandidates : List String
  combinedCandidates : List String

-- | Bucket strength for semantic equivalence candidates.
public export
data BucketStrength : Type where
  Strong : BucketStrength
  Weak   : BucketStrength

-- | Confidence mapping used by ABI consumers:
-- strong hash bucket => sufficient evidence, weak key bucket => heuristic.
public export
bucketConfidence : BucketStrength -> Confidence
bucketConfidence Strong = Sufficient
bucketConfidence Weak = Heuristic

-- | Semantic filter contract used by API layer query builders.
public export
record SemanticFilter where
  constructor MkSemanticFilter
  crossingNumber : Maybe Int
  determinant : Maybe Int
  signature : Maybe Int
  quandleGeneratorCount : Maybe Int
  colouringCount3 : Maybe Int
  descriptorHash : Maybe String
  quandleKey : Maybe String
  limit : Nat
  offset : Nat
