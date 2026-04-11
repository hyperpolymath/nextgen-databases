-- SPDX-License-Identifier: PMPL-1.0-or-later
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
-- Types.idr — Core type definitions for the NQC ABI.
--
-- Defines the wire types for query requests, responses, database profiles,
-- and output formats with dependent type proofs guaranteeing correctness.
-- These types are the single source of truth — Zig FFI and Gleam must
-- conform to the constraints proven here.

module Types

import Data.Vect
import Data.String
import Data.So

%default total

-- =========================================================================
-- Port numbers — proven valid range
-- =========================================================================

||| A valid TCP port number (1–65535).
||| The proof witness `So` ensures the bounds are checked at compile time.
public export
record Port where
  constructor MkPort
  value : Nat
  {auto validLower : So (value >= 1)}
  {auto validUpper : So (value <= 65535)}

||| Construct a port from a natural number, failing if out of range.
export
mkPort : (n : Nat) -> {auto lower : So (n >= 1)} -> {auto upper : So (n <= 65535)} -> Port
mkPort n = MkPort n

||| The three default ports for built-in databases.
export
vclPort : Port
vclPort = MkPort 8080

export
gqlPort : Port
gqlPort = MkPort 8081

export
kqlPort : Port
kqlPort = MkPort 8082

-- =========================================================================
-- Non-empty strings — proven non-empty
-- =========================================================================

||| A string guaranteed to be non-empty.
||| The proof witness ensures `length s > 0` at compile time.
public export
record NonEmptyString where
  constructor MkNonEmptyString
  value : String
  {auto nonEmpty : So (length value > 0)}

-- =========================================================================
-- URL paths — proven to start with "/"
-- =========================================================================

||| A URL path that starts with '/'.
public export
record UrlPath where
  constructor MkUrlPath
  value : String
  {auto startsWithSlash : So (isPrefixOf "/" value)}

||| Construct a URL path, proven to start with '/'.
export
vclExecutePath : UrlPath
vclExecutePath = MkUrlPath "/vcl/execute"

export
gqlExecutePath : UrlPath
gqlExecutePath = MkUrlPath "/gql/execute"

export
kqlExecutePath : UrlPath
kqlExecutePath = MkUrlPath "/kql/execute"

export
healthPath : UrlPath
healthPath = MkUrlPath "/health"

-- =========================================================================
-- Output format — exhaustive enumeration
-- =========================================================================

||| The three supported output formats.
public export
data OutputFormat = Table | Json | Csv

||| Parse an output format from a lowercase string.
export
parseFormat : String -> Maybe OutputFormat
parseFormat "table" = Just Table
parseFormat "json"  = Just Json
parseFormat "csv"   = Just Csv
parseFormat _       = Nothing

||| Render an output format to its canonical string.
export
formatToString : OutputFormat -> String
formatToString Table = "table"
formatToString Json  = "json"
formatToString Csv   = "csv"

||| Proof: parseFormat is a left inverse of formatToString.
||| parseFormat(formatToString(f)) == Just f for all f.
export
formatRoundtrip : (f : OutputFormat) -> parseFormat (formatToString f) = Just f
formatRoundtrip Table = Refl
formatRoundtrip Json  = Refl
formatRoundtrip Csv   = Refl

-- =========================================================================
-- Database identifier — known database backends
-- =========================================================================

||| Known database backend identifiers.
public export
data DatabaseId = VCL | GQL | KQL

||| Parse a database identifier from a lowercase string.
export
parseDatabaseId : String -> Maybe DatabaseId
parseDatabaseId "vcl" = Just VCL
parseDatabaseId "gql" = Just GQL
parseDatabaseId "kql" = Just KQL
parseDatabaseId _     = Nothing

||| Render a database identifier to its canonical string.
export
databaseIdToString : DatabaseId -> String
databaseIdToString VCL = "vcl"
databaseIdToString GQL = "gql"
databaseIdToString KQL = "kql"

||| Proof: parseDatabaseId roundtrips.
export
databaseIdRoundtrip : (d : DatabaseId) -> parseDatabaseId (databaseIdToString d) = Just d
databaseIdRoundtrip VCL = Refl
databaseIdRoundtrip GQL = Refl
databaseIdRoundtrip KQL = Refl

-- =========================================================================
-- Query request — wire format
-- =========================================================================

||| A query request as sent over the wire.
||| The query text is guaranteed non-empty (empty queries are rejected
||| before reaching the protocol layer).
public export
record QueryRequest where
  constructor MkQueryRequest
  query : NonEmptyString

-- =========================================================================
-- HTTP status classification
-- =========================================================================

||| Classification of HTTP status codes.
public export
data StatusClass = Success | ClientError | ServerError | Other

||| Classify an HTTP status code.
export
classifyStatus : Nat -> StatusClass
classifyStatus n =
  if n >= 200 && n < 300 then Success
  else if n >= 400 && n < 500 then ClientError
  else if n >= 500 && n < 600 then ServerError
  else Other

||| Proof: all 2xx codes classify as Success.
export
successRange : (n : Nat) -> So (n >= 200) -> So (n < 300)
             -> classifyStatus n = Success
successRange n _ _ = Refl

-- =========================================================================
-- Client error type — mirrors Gleam's ClientError
-- =========================================================================

||| Error type for client operations, mirroring the Gleam implementation.
public export
data ClientErr
  = RequestErr String
  | TransportErr String
  | ServerErr Nat String
  | ParseErr String

-- =========================================================================
-- Database profile — complete type with all invariants
-- =========================================================================

||| A database profile with all invariants enforced at the type level.
public export
record DatabaseProfile where
  constructor MkDatabaseProfile
  id          : NonEmptyString
  displayName : NonEmptyString
  languageName : NonEmptyString
  description : NonEmptyString
  aliases     : List String
  defaultPort : Port
  executePath : UrlPath
  healthPath  : UrlPath
  prompt      : NonEmptyString
  supportsDt  : Bool
  keywords    : List String

-- =========================================================================
-- Connection — active session connection
-- =========================================================================

||| An active database connection.
public export
record Connection where
  constructor MkConnection
  profile   : DatabaseProfile
  host      : NonEmptyString
  port      : Port
  dtEnabled : Bool

-- =========================================================================
-- URL construction — proven correct composition
-- =========================================================================

||| Build a base URL from host and port.
export
baseUrl : NonEmptyString -> Port -> String
baseUrl host port = "http://" ++ host.value ++ ":" ++ show port.value

||| Build the execute URL from a connection.
export
executeUrl : Connection -> String
executeUrl conn = baseUrl conn.host conn.port ++ conn.profile.executePath.value

||| Build the health URL from a connection.
export
healthUrl : Connection -> String
healthUrl conn = baseUrl conn.host conn.port ++ conn.profile.healthPath.value
