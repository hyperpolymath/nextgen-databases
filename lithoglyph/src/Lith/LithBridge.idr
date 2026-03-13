-- SPDX-License-Identifier: PMPL-1.0-or-later
-- SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell (@hyperpolymath)
--
-- LithBridge.idr - Type definitions with proofs for Lith Lith.Bridge ABI
-- Media-Type: text/x-idris

module Lith.LithBridge

import Data.So
import Data.Bits
import Data.String
import Data.List
-- Available in lib/proven/ (install with: idris2 --install lib/proven/proven.ipkg)
-- import Proven.SafeString  -- NonEmptyString, validateNonEmpty
-- import Proven.SafePath    -- SafePath, validatePath
-- import Proven.SafeJson    -- ValidJson, validateJson
-- import Proven.SafeSQL     -- SafeQuery, validateQuery

%default total

--------------------------------------------------------------------------------
-- Core Handle Types (Opaque, Non-Null)
--------------------------------------------------------------------------------

||| Non-null database handle
||| @ ptr The pointer value (guaranteed non-zero)
public export
data FdbDb : Type where
  MkFdbDb : (ptr : Bits64) -> {auto 0 nonNull : So (ptr /= 0)} -> FdbDb

||| Non-null transaction handle
||| Transactions are ACID-compliant with rollback via journal inverses
public export
data FdbTxn : Type where
  MkFdbTxn : (ptr : Bits64) -> {auto 0 nonNull : So (ptr /= 0)} -> FdbTxn

||| Non-null cursor handle for query results
public export
data FdbCursor : Type where
  MkFdbCursor : (ptr : Bits64) -> {auto 0 nonNull : So (ptr /= 0)} -> FdbCursor

||| Non-null collection handle
public export
data FdbCollection : Type where
  MkFdbCollection : (ptr : Bits64) -> {auto 0 nonNull : So (ptr /= 0)} -> FdbCollection

||| Non-null schema handle
public export
data FdbSchema : Type where
  MkFdbSchema : (ptr : Bits64) -> {auto 0 nonNull : So (ptr /= 0)} -> FdbSchema

||| Non-null journal handle
public export
data FdbJournal : Type where
  MkFdbJournal : (ptr : Bits64) -> {auto 0 nonNull : So (ptr /= 0)} -> FdbJournal

||| Non-null migration handle
public export
data FdbMigration : Type where
  MkFdbMigration : (ptr : Bits64) -> {auto 0 nonNull : So (ptr /= 0)} -> FdbMigration

--------------------------------------------------------------------------------
-- Status Codes
--------------------------------------------------------------------------------

||| Result status codes for FFI operations
public export
data FdbStatus : Type where
  ||| Operation succeeded
  StatusOk : FdbStatus
  ||| Invalid argument provided
  StatusInvalidArg : FdbStatus
  ||| Database file not found
  StatusNotFound : FdbStatus
  ||| Permission denied
  StatusPermissionDenied : FdbStatus
  ||| Database already exists
  StatusAlreadyExists : FdbStatus
  ||| Constraint violation
  StatusConstraintViolation : FdbStatus
  ||| Type mismatch
  StatusTypeMismatch : FdbStatus
  ||| Out of memory
  StatusOutOfMemory : FdbStatus
  ||| I/O error
  StatusIOError : FdbStatus
  ||| Corruption detected
  StatusCorruption : FdbStatus
  ||| Transaction conflict (optimistic concurrency control)
  StatusConflict : FdbStatus
  ||| Internal error
  StatusInternalError : FdbStatus

||| Convert status to integer for FFI
public export
statusToInt : FdbStatus -> Int32
statusToInt StatusOk = 0
statusToInt StatusInvalidArg = 1
statusToInt StatusNotFound = 2
statusToInt StatusPermissionDenied = 3
statusToInt StatusAlreadyExists = 4
statusToInt StatusConstraintViolation = 5
statusToInt StatusTypeMismatch = 6
statusToInt StatusOutOfMemory = 7
statusToInt StatusIOError = 8
statusToInt StatusCorruption = 9
statusToInt StatusConflict = 10
statusToInt StatusInternalError = 11

--------------------------------------------------------------------------------
-- Block Storage Types (Form.Blocks)
--------------------------------------------------------------------------------

||| Block identifier (4 KiB fixed-size blocks)
public export
BlockId : Type
BlockId = Bits64

||| Block size in bytes (4096 bytes = 4 KiB)
public export %inline
blockSize : Nat
blockSize = 4096

||| Block size constant as Integer (avoids Nat reduction overhead)
public export %inline
blockSizeInt : Integer
blockSizeInt = 4096

||| Block header magic number (identifies Lith blocks)
public export
BlockMagic : Type
BlockMagic = Bits32

||| Block type identifier
public export
data BlockType : Type where
  BlockTypeFree : BlockType
  BlockTypeDocument : BlockType
  BlockTypeEdge : BlockType
  BlockTypeSchema : BlockType
  BlockTypeJournal : BlockType
  BlockTypeMigration : BlockType

||| Convert block type to integer
public export
blockTypeToInt : BlockType -> Bits8
blockTypeToInt BlockTypeFree = 0
blockTypeToInt BlockTypeDocument = 1
blockTypeToInt BlockTypeEdge = 2
blockTypeToInt BlockTypeSchema = 3
blockTypeToInt BlockTypeJournal = 4
blockTypeToInt BlockTypeMigration = 5

||| CRC32C checksum (Castagnoli polynomial)
public export
Checksum : Type
Checksum = Bits32

--------------------------------------------------------------------------------
-- Journal Types (Form.Journal)
--------------------------------------------------------------------------------

||| Journal sequence number (monotonically increasing)
public export
SequenceNumber : Type
SequenceNumber = Bits64

||| Journal operation type
public export
data JournalOp : Type where
  OpInsert : JournalOp
  OpUpdate : JournalOp
  OpDelete : JournalOp
  OpNormalize : JournalOp
  OpMigrate : JournalOp

||| Convert operation to integer
public export
journalOpToInt : JournalOp -> Bits8
journalOpToInt OpInsert = 0
journalOpToInt OpUpdate = 1
journalOpToInt OpDelete = 2
journalOpToInt OpNormalize = 3
journalOpToInt OpMigrate = 4

||| Journal entry with provenance
public export
record JournalEntry where
  constructor MkJournalEntry
  sequence : SequenceNumber
  operation : JournalOp
  timestamp : Bits64  -- Unix timestamp (milliseconds)
  actorId : String    -- Actor who performed the operation
  rationale : String  -- Rationale for the operation
  forwardPayload : String  -- What was done (CBOR-encoded)
  inversePayload : String  -- How to undo (CBOR-encoded)
  {auto 0 actorNonEmpty : So (length actorId > 0)}
  {auto 0 rationaleNonEmpty : So (length rationale > 0)}

--------------------------------------------------------------------------------
-- Provenance Tracking (Form.Model)
--------------------------------------------------------------------------------

||| Actor identifier (non-empty)
public export
ActorId : Type
ActorId = String  -- TODO: Replace with Proven.SafeString.NonEmptyString (lib/proven/)

||| Rationale (non-empty)
public export
Rationale : Type
Rationale = String  -- TODO: Replace with Proven.SafeString.NonEmptyString (lib/proven/)

||| Unix timestamp (milliseconds since epoch)
public export
Timestamp : Type
Timestamp = Bits64

||| Confidence score [0.0, 1.0] for data quality
public export
record Confidence where
  constructor MkConfidence
  value : Double
  {auto 0 lowerBound : So (value >= 0.0)}
  {auto 0 upperBound : So (value <= 1.0)}

||| PROMPT dimension score [0, 100]
public export
data PromptDimension : Type where
  MkPromptDimension : (value : Nat) -> {auto 0 valid : So (value <= 100)} -> PromptDimension

||| PROMPT scores for research-grade data quality
public export
record PromptScores where
  constructor MkPromptScores
  provenance : PromptDimension
  replicability : PromptDimension
  objectivity : PromptDimension
  methodology : PromptDimension
  publication : PromptDimension
  transparency : PromptDimension

--------------------------------------------------------------------------------
-- Normal Form Types (Form.Normalizer)
--------------------------------------------------------------------------------

||| Normal form levels
public export
data NormalForm : Type where
  NF_None : NormalForm         -- Not normalized
  NF_1NF : NormalForm          -- First normal form
  NF_2NF : NormalForm          -- Second normal form
  NF_3NF : NormalForm          -- Third normal form
  NF_BCNF : NormalForm         -- Boyce-Codd normal form
  NF_4NF : NormalForm          -- Fourth normal form
  NF_5NF : NormalForm          -- Fifth normal form

||| Convert normal form to integer
public export
normalFormToInt : NormalForm -> Bits8
normalFormToInt NF_None = 0
normalFormToInt NF_1NF = 1
normalFormToInt NF_2NF = 2
normalFormToInt NF_3NF = 3
normalFormToInt NF_BCNF = 4
normalFormToInt NF_4NF = 5
normalFormToInt NF_5NF = 6

||| Functional dependency (X → Y)
public export
record FunctionalDependency where
  constructor MkFD
  determinant : List String  -- Attributes on left side
  dependent : List String    -- Attributes on right side
  {auto 0 determinantNonEmpty : So (length determinant > 0)}
  {auto 0 dependentNonEmpty : So (length dependent > 0)}

||| Proof that a schema is in a specific normal form
public export
0 InNormalForm : List FunctionalDependency -> NormalForm -> Type
InNormalForm fds nf = ()  -- Placeholder for actual proof

--------------------------------------------------------------------------------
-- Migration Types
--------------------------------------------------------------------------------

||| Three-phase migration protocol
public export
data MigrationPhase : Type where
  PhaseAnnounce : MigrationPhase  -- Phase 1: Announce migration
  PhaseShadow : MigrationPhase    -- Phase 2: Shadow mode (dual writes)
  PhaseCommit : MigrationPhase    -- Phase 3: Commit and cleanup

||| Convert migration phase to integer
public export
migrationPhaseToInt : MigrationPhase -> Bits8
migrationPhaseToInt PhaseAnnounce = 0
migrationPhaseToInt PhaseShadow = 1
migrationPhaseToInt PhaseCommit = 2

||| Migration with proof of lossless transformation
public export
record Migration where
  constructor MkMigration
  fromNF : NormalForm
  toNF : NormalForm
  transformations : List FunctionalDependency
  losslessProof : String  -- CBOR-encoded Lean 4 proof
  {auto 0 progressProof : So (normalFormToInt toNF >= normalFormToInt fromNF)}

--------------------------------------------------------------------------------
-- FFI Result Type
--------------------------------------------------------------------------------

||| Result type for FFI operations
public export
record FdbResult (a : Type) where
  constructor MkFdbResult
  status : FdbStatus
  value : Maybe a
  errorMessage : Maybe String

||| Smart constructor for success result
public export
ok : a -> FdbResult a
ok v = MkFdbResult StatusOk (Just v) Nothing

||| Smart constructor for error result
public export
err : FdbStatus -> String -> FdbResult a
err s msg = MkFdbResult s Nothing (Just msg)

--------------------------------------------------------------------------------
-- Integration with Proven Library
--------------------------------------------------------------------------------

||| Check whether a substring occurs anywhere in a string.
||| Uses unpack to avoid reliance on Data.String.isInfixOf which
||| may not be available in all Idris2 versions.
covering
containsSubstr : String -> String -> Bool
containsSubstr needle haystack =
  let ns = unpack needle
      hs = unpack haystack
  in go ns hs
  where
    ||| Check if one char list is a prefix of another.
    covering
    startsWith : List Char -> List Char -> Bool
    startsWith [] _ = True
    startsWith _ [] = False
    startsWith (n :: ns') (h :: hs') = n == h && startsWith ns' hs'

    ||| Slide through the haystack looking for the needle.
    covering
    go : List Char -> List Char -> Bool
    go _ [] = False
    go ns' hs'@(_ :: rest) = startsWith ns' hs' || go ns' rest

||| Validate database path using inline checks.
||| Returns Nothing if the path is invalid, or Just the validated path.
||| Checks: non-empty, no ".." traversal, does not start with "/".
||| TODO: Replace with Proven.SafePath.validatePath (lib/proven/) which
||| returns a SafePath carrying a dependent-type proof.
public export
covering
validateDbPath : String -> Maybe String
validateDbPath path =
  if length path == 0 then Nothing
  else if containsSubstr ".." path then Nothing
  else if isPrefixOf "/" path then Nothing
  else Just path

||| Validate FQL query using inline checks.
||| Returns Nothing if the query is invalid, or Just the validated query.
||| Checks: non-empty, no obvious injection patterns (semicolons, comment
||| markers, DROP/DELETE keywords in uppercase).
||| TODO: Replace with Proven.SafeSQL.validateQuery (lib/proven/) which
||| returns a SafeQuery carrying a dependent-type proof.
public export
covering
validateFqlQuery : String -> Maybe String
validateFqlQuery query =
  if length query == 0 then Nothing
  else if containsSubstr ";" query then Nothing
  else if containsSubstr "--" query then Nothing
  else if containsSubstr "/*" query then Nothing
  else if containsSubstr "DROP " (toUpper query) then Nothing
  else if containsSubstr "DELETE " (toUpper query) then Nothing
  else if containsSubstr "TRUNCATE " (toUpper query) then Nothing
  else Just query

||| Parse JSON document using inline structural validation.
||| Returns Nothing if the string does not look like valid JSON,
||| or Just the string if it passes basic structural checks.
||| Checks: non-empty, starts with '{' or '[', ends with matching
||| '}' or ']', balanced brace/bracket count.
||| TODO: Replace with Proven.SafeJson.validateJson (lib/proven/) which
||| returns a ValidJson carrying a dependent-type proof.
public export
covering
parseJsonDocument : String -> Maybe String
parseJsonDocument jsonStr =
  let trimmed = trim jsonStr
  in if length trimmed == 0 then Nothing
     else let chars = unpack trimmed
          in case chars of
               ('{' :: _) =>
                 if isSuffixOf "}" trimmed && balancedBraces chars 0 0
                   then Just trimmed
                   else Nothing
               ('[' :: _) =>
                 if isSuffixOf "]" trimmed && balancedBraces chars 0 0
                   then Just trimmed
                   else Nothing
               _ => Nothing
  where
    ||| Count braces and brackets to check balance.
    ||| Returns True if both counts are zero at the end.
    covering
    balancedBraces : List Char -> Int -> Int -> Bool
    balancedBraces [] braces brackets = braces == 0 && brackets == 0
    balancedBraces (c :: cs) braces brackets =
      if braces < 0 || brackets < 0 then False
      else case c of
        '{' => balancedBraces cs (braces + 1) brackets
        '}' => balancedBraces cs (braces - 1) brackets
        '[' => balancedBraces cs braces (brackets + 1)
        ']' => balancedBraces cs braces (brackets - 1)
        _   => balancedBraces cs braces brackets

||| Validate actor ID (non-empty string)
public export
validateActorId : String -> Maybe ActorId
validateActorId s = if length s > 0 then Just s else Nothing

||| Validate rationale (non-empty string)
public export
validateRationale : String -> Maybe Rationale
validateRationale s = if length s > 0 then Just s else Nothing

--------------------------------------------------------------------------------
-- CBOR Serialization Tags
--------------------------------------------------------------------------------

||| Semantic tags for CBOR encoding (RFC 8949)
public export
data CborTag : Type where
  TagDocument : CborTag
  TagEdge : CborTag
  TagSchema : CborTag
  TagJournalEntry : CborTag
  TagFunctionalDependency : CborTag
  TagProofBlob : CborTag
  TagPromptScores : CborTag
  TagMigration : CborTag

||| Convert tag to integer
public export
tagToInt : CborTag -> Bits32
tagToInt TagDocument = 2000
tagToInt TagEdge = 2001
tagToInt TagSchema = 2002
tagToInt TagJournalEntry = 2003
tagToInt TagFunctionalDependency = 2004
tagToInt TagProofBlob = 2005
tagToInt TagPromptScores = 2006
tagToInt TagMigration = 2007
