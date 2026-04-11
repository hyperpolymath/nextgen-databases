-- SPDX-License-Identifier: PMPL-1.0-or-later
-- Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
--
-- Injection.idr — Construction typing (SAFE PARAMS)
--
-- Queries are unforgeable by construction. Instead of string concatenation,
-- query structure is a typed AST and parameters are separately typed values.
-- The type system guarantees that user-supplied data can NEVER appear in
-- query structure positions — it is always confined to parameter slots.
--
-- This eliminates injection attacks at the type level: there is no string
-- concatenation path, so there is nothing to inject into.

module Injection

import Core

%default total

-- ============================================================================
-- Parameter Types (VCL-UT value domain)
-- ============================================================================

||| Types that query parameters can inhabit. These mirror VCL's value types
||| but exist as a SEPARATE domain from query structure types. The separation
||| is the key insight: structure and data live in different type universes.
public export
data ParamType : Type where
  PString    : ParamType
  PInt       : ParamType
  PFloat     : ParamType
  PBool      : ParamType
  PUuid      : ParamType
  PTimestamp : ParamType
  PVector    : (dim : Nat) -> ParamType
  PList      : ParamType -> ParamType

public export
Show ParamType where
  show PString       = "String"
  show PInt          = "Int"
  show PFloat        = "Float"
  show PBool         = "Bool"
  show PUuid         = "UUID"
  show PTimestamp    = "Timestamp"
  show (PVector d)   = "Vector<" ++ show d ++ ">"
  show (PList inner) = "List<" ++ show inner ++ ">"

public export
Eq ParamType where
  PString       == PString       = True
  PInt          == PInt          = True
  PFloat        == PFloat        = True
  PBool         == PBool         = True
  PUuid         == PUuid         = True
  PTimestamp    == PTimestamp    = True
  (PVector d1)  == (PVector d2)  = d1 == d2
  (PList a)     == (PList b)     = a == b
  _             == _             = False

-- ============================================================================
-- Named Parameters (Typed Bindings)
-- ============================================================================

||| A named parameter with a declared type. The name is used for binding
||| in the query template; the type constrains what values can be supplied.
public export
record TypedParam where
  constructor MkTypedParam
  paramName : String
  paramType : ParamType

public export
Show TypedParam where
  show p = "$" ++ p.paramName ++ " : " ++ show p.paramType

public export
Eq TypedParam where
  a == b = a.paramName == b.paramName && a.paramType == b.paramType

-- ============================================================================
-- Parameter Schema (Type-Level Parameter List)
-- ============================================================================

||| A parameter schema is a list of typed parameters. A query declares its
||| parameter schema, and execution requires supplying values matching this
||| schema exactly.
public export
ParamSchema : Type
ParamSchema = List TypedParam

||| The empty parameter schema — a query with no parameters.
public export
noParams : ParamSchema
noParams = []

-- ============================================================================
-- Safe Query Type (Unforgeable by Construction)
-- ============================================================================

||| A safe query is indexed by its parameter schema. The query structure
||| is an opaque AST — NOT a string. Parameters are typed slots within
||| the AST that can only be filled with correctly-typed values.
|||
||| The key invariant: there is no function `String -> SafeQuery schema`.
||| Queries can only be constructed via the SafeQuery constructors, which
||| build structure from typed fragments. This makes injection impossible
||| by construction — there is no path from untrusted input to query structure.
public export
data SafeQuery : (schema : ParamSchema) -> Type where
  ||| A simple SELECT query with typed parameter holes.
  SafeSelect : (modalities : List Modality)
            -> (hexad : HexadRef)
            -> SafeQuery schema

  ||| A SELECT with a WHERE clause containing a typed parameter reference.
  SafeWhere  : SafeQuery schema
            -> (paramRef : String)
            -> {auto inSchema : Core.Elem (MkTypedParam paramRef ty) schema}
            -> SafeQuery schema

  ||| A SELECT with a FULLTEXT predicate referencing a typed parameter.
  SafeFulltext : SafeQuery schema
              -> (paramRef : String)
              -> {auto inSchema : Core.Elem (MkTypedParam paramRef PString) schema}
              -> SafeQuery schema

  ||| Compose two safe queries (e.g., UNION).
  SafeCompose : SafeQuery schema -> SafeQuery schema -> SafeQuery schema

-- ============================================================================
-- Parameter Values (Runtime Bindings)
-- ============================================================================

||| A parameter value whose type matches the declared ParamType.
||| This is the runtime companion to TypedParam.
public export
data ParamValue : ParamType -> Type where
  StringVal    : String -> ParamValue PString
  IntVal       : Integer -> ParamValue PInt
  FloatVal     : Double -> ParamValue PFloat
  BoolVal      : Bool -> ParamValue PBool
  UuidVal      : String -> ParamValue PUuid
  TimestampVal : String -> ParamValue PTimestamp
  VectorVal    : Vect n Double -> ParamValue (PVector n)
  ListVal      : List (ParamValue inner) -> ParamValue (PList inner)

-- ============================================================================
-- Bound Parameters (Schema-Checked Value Set)
-- ============================================================================

||| A bound parameter set: every parameter in the schema has a corresponding
||| value of the correct type. This is a heterogeneous list indexed by the
||| parameter schema.
public export
data BoundParams : ParamSchema -> Type where
  ||| No parameters — matches the empty schema.
  NilParams  : BoundParams []
  ||| A parameter value cons'd onto the rest, matching the schema.
  ConsParams : ParamValue ty -> BoundParams rest
            -> BoundParams (MkTypedParam name ty :: rest)

-- ============================================================================
-- Safe Execution (Type-Safe Query Dispatch)
-- ============================================================================

||| Execute a safe query with bound parameters. The type system guarantees:
||| 1. The query structure is a valid AST (not a string).
||| 2. Every parameter slot is filled with a value of the correct type.
||| 3. No user-supplied data can appear in structural positions.
|||
||| Returns a query result — in a real implementation this would dispatch
||| to the VeriSimDB engine.
public export
executeSafe : SafeQuery schema -> BoundParams schema -> Core.QueryResult
executeSafe _ _ = MkQueryResult [] 0

-- ============================================================================
-- Safety Proofs
-- ============================================================================

||| Proof that a SafeQuery contains no string concatenation.
||| This is trivially true by construction — the SafeQuery type has no
||| constructor that accepts an arbitrary String as query structure.
||| The proof is the TYPE ITSELF: `String -> SafeQuery s` does not exist.

||| Proof that parameter values are confined to parameter slots.
||| A BoundParams indexed by schema `s` can only supply values at the
||| types declared in `s`. The type checker prevents supplying a String
||| where an Int is expected, or vice versa.
public export
paramTypesSafe : BoundParams schema -> ParamSchema
paramTypesSafe {schema} _ = schema

-- ============================================================================
-- Example: Safe Parameterised Query
-- ============================================================================

||| Example schema: a query that searches for a string in a hexad.
public export
searchSchema : ParamSchema
searchSchema = [ MkTypedParam "query" PString
               , MkTypedParam "maxResults" PInt
               ]

||| Example: construct a safe query against the search schema.
||| Note: there is no way to construct this query from a raw string.
public export
safeSearchQuery : SafeQuery Injection.searchSchema
safeSearchQuery =
  SafeFulltext
    (SafeSelect [Graph, Document] (MkHexadRef "550e8400-e29b-41d4-a716-446655440000"))
    "query"

||| Example: bind parameters and execute.
public export
safeSearchExample : Core.QueryResult
safeSearchExample =
  executeSafe safeSearchQuery
    (ConsParams (StringVal "climate change")
      (ConsParams (IntVal 50)
        NilParams))
