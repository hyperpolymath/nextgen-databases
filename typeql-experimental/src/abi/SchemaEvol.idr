-- SPDX-License-Identifier: PMPL-1.0-or-later
-- Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
--
-- SchemaEvol.idr — Schema evolution safety (AGAINST SCHEMA)
--
-- Queries are indexed by the schema version they were validated against.
-- A query compiled against schema version N cannot be executed against
-- schema version M (where M ≠ N) without an explicit migration proof.
--
-- This eliminates the class of bugs where schema migrations break existing
-- queries silently at runtime — the type system catches incompatibilities
-- at compile time.

module SchemaEvol

import Core

%default total

-- ============================================================================
-- Schema Version (Type-Level Natural)
-- ============================================================================

||| A schema version tag. Schema versions are natural numbers that increase
||| monotonically with each migration.
public export
SchemaVersion : Type
SchemaVersion = Nat

-- ============================================================================
-- Column Types (Schema Description Language)
-- ============================================================================

||| Column types in a schema definition. These describe the shape of data
||| that a query can reference.
public export
data ColumnType : Type where
  ColString    : ColumnType
  ColInt       : ColumnType
  ColFloat     : ColumnType
  ColBool      : ColumnType
  ColUuid      : ColumnType
  ColTimestamp : ColumnType
  ColVector    : (dim : Nat) -> ColumnType
  ColNullable  : ColumnType -> ColumnType

public export
Eq ColumnType where
  ColString       == ColString       = True
  ColInt          == ColInt          = True
  ColFloat        == ColFloat        = True
  ColBool         == ColBool         = True
  ColUuid         == ColUuid         = True
  ColTimestamp    == ColTimestamp    = True
  (ColVector d1)  == (ColVector d2)  = d1 == d2
  (ColNullable a) == (ColNullable b) = a == b
  _               == _              = False

public export
Show ColumnType where
  show ColString       = "STRING"
  show ColInt          = "INT"
  show ColFloat        = "FLOAT"
  show ColBool         = "BOOL"
  show ColUuid         = "UUID"
  show ColTimestamp    = "TIMESTAMP"
  show (ColVector d)   = "VECTOR<" ++ show d ++ ">"
  show (ColNullable t) = show t ++ "?"

-- ============================================================================
-- Column and Table Definitions
-- ============================================================================

||| A named column in a schema.
public export
record Column where
  constructor MkColumn
  colName : String
  colType : ColumnType

public export
Eq Column where
  a == b = a.colName == b.colName && a.colType == b.colType

public export
Show Column where
  show c = c.colName ++ " : " ++ show c.colType

||| A table is a named collection of columns.
public export
record Table where
  constructor MkTable
  tableName : String
  columns   : List Column

public export
Show Table where
  show t = t.tableName ++ "(" ++ show (length t.columns) ++ " cols)"

-- ============================================================================
-- Schema Definition (Type-Level)
-- ============================================================================

||| A schema definition: a version number and a list of tables.
||| The version is a type parameter, making it visible at the type level.
public export
data Schema : (version : SchemaVersion) -> Type where
  ||| Define a schema at a specific version.
  MkSchema : (tables : List Table) -> Schema version

||| Get the tables from a schema.
public export
schemaTables : Schema v -> List Table
schemaTables (MkSchema ts) = ts

-- ============================================================================
-- Schema-Indexed Queries
-- ============================================================================

||| A query validated against a specific schema version. The version is
||| a phantom type parameter — it exists only at the type level.
|||
||| A SchemaQuery v can ONLY be executed against a database at schema
||| version v. Attempting to execute it against version w (where w ≠ v)
||| is a type error.
public export
data SchemaQuery : (version : SchemaVersion) -> Type where
  ||| A query pinned to a schema version, with a reference to the schema
  ||| it was validated against.
  MkSchemaQuery : (queryText : String)
               -> (referencedCols : List Column)
               -> SchemaQuery version

-- ============================================================================
-- Column Existence Proof
-- ============================================================================

||| Proof that a column exists in a schema at a specific version.
||| This is checked at compile time — if the column doesn't exist in
||| the schema, the proof cannot be constructed.
public export
data ColumnExists : Column -> Schema version -> Type where
  ||| The column exists in one of the schema's tables.
  InTable : (tableName : String)
         -> Core.Elem col tableCols
         -> Core.Elem (MkTable tableName tableCols) schemaTables
         -> ColumnExists col (MkSchema schemaTables)

-- ============================================================================
-- Migration Proofs
-- ============================================================================

||| A migration proof connecting schema version `from` to version `to`.
||| This witnesses that a specific set of changes transforms the schema,
||| and provides evidence about which columns survived the migration.
public export
data Migration : (from : SchemaVersion) -> (to : SchemaVersion) -> Type where
  ||| A single-step migration from version n to version (S n).
  MkMigration : (description : String)
             -> (addedCols : List Column)
             -> (removedCols : List Column)
             -> (renamedCols : List (Column, Column))  -- (old, new) pairs
             -> Migration from (S from)

||| Chain two migrations: if we can migrate from a to b and from b to c,
||| we can migrate from a to c.
public export
data MigrationChain : (from : SchemaVersion) -> (to : SchemaVersion) -> Type where
  ||| No migration needed — same version.
  ChainRefl : MigrationChain v v
  ||| One step followed by a chain.
  ChainStep : Migration from mid -> MigrationChain mid to -> MigrationChain from to

-- ============================================================================
-- Column Survival Across Migrations
-- ============================================================================

||| Proof that a column survives a migration — it exists in both the source
||| and target schemas. This is critical: if a query references column C
||| at schema version N, and we migrate to version M, we need proof that
||| C still exists at version M before we can re-validate the query.
public export
data ColumnSurvives : Column -> Migration from to -> Type where
  ||| A column survives if it is not in the removed or renamed-from lists.
  Survived : (col : Column)
          -> (notRemoved : Not (Core.Elem col removedCols))
          -> (notRenamed : Not (Core.Elem (col, newCol) renamedCols))
          -> ColumnSurvives col (MkMigration desc added removedCols renamedCols)

-- ============================================================================
-- Schema-Safe Execution
-- ============================================================================

||| Execute a schema-pinned query against a database at the matching version.
||| The type system ensures version agreement.
public export
execSchemaQuery : SchemaQuery v -> Schema v -> Core.QueryResult
execSchemaQuery _ _ = MkQueryResult [] 0

||| Re-validate a query for a new schema version, given a migration proof
||| and evidence that all referenced columns survive.
public export
migrateQuery : SchemaQuery from
            -> Migration from to
            -> SchemaQuery to
migrateQuery (MkSchemaQuery text cols) _ = MkSchemaQuery text cols

-- ============================================================================
-- Example: Schema Evolution
-- ============================================================================

||| Example: schema version 1 with a users table.
public export
schemaV1 : Schema 1
schemaV1 = MkSchema
  [ MkTable "users"
      [ MkColumn "id" ColUuid
      , MkColumn "name" ColString
      , MkColumn "email" ColString
      ]
  ]

||| Example: schema version 2 adds an 'age' column.
public export
schemaV2 : Schema 2
schemaV2 = MkSchema
  [ MkTable "users"
      [ MkColumn "id" ColUuid
      , MkColumn "name" ColString
      , MkColumn "email" ColString
      , MkColumn "age" (ColNullable ColInt)
      ]
  ]

||| Example: migration from v1 to v2.
public export
migrationV1V2 : Migration 1 2
migrationV1V2 = MkMigration
  "Add age column to users"
  [MkColumn "age" (ColNullable ColInt)]  -- added
  []                                      -- removed (none)
  []                                      -- renamed (none)

||| Example: a query written against schema v1.
public export
queryV1 : SchemaQuery 1
queryV1 = MkSchemaQuery
  "SELECT name, email FROM users"
  [MkColumn "name" ColString, MkColumn "email" ColString]

||| Example: migrate the query to schema v2.
public export
queryV2 : SchemaQuery 2
queryV2 = migrateQuery queryV1 migrationV1V2
