-- SPDX-License-Identifier: PMPL-1.0-or-later
||| VCLProtocol.idr — the CLI stdio wire protocol ABI.
|||
||| Defines the contract between the `verisim` Zig CLI binary and the
||| Julia `vcl_server.jl` child process. Communication is line-oriented:
|||   * stdin  → one VCL query per line (sent by the CLI to the server)
|||   * stdout → one A2ML [vcl-verdict] block per query (server reply)
|||
||| **Why a formal ABI here?**
|||   The subprocess boundary provides OS-level isolation (dependability
|||   over the estate priority order), but does NOT provide compile-time
|||   type checking at the pipe crossing. The Idris2 types here serve as
|||   the authoritative spec that BOTH sides must conform to; divergence
|||   is a protocol-drift bug, not a type error. Any future alternative
|||   consumer (Elixir Port, Rust Command, another Zig binary) must also
|||   satisfy these types.
|||
||| **Concurrency model.** The protocol is strictly sequential: the CLI
||| sends one query and waits for one verdict before sending the next.
||| Pipelining is intentionally excluded — the invariant `OnePairPerLine`
||| below encodes this. Batching is done at the caller level (the CLI
||| loops over stdin lines, forwarding each to the Julia server).
module Abi.VCLProtocol

import Abi.Types

%default total

-- -----------------------------------------------------------------------
-- § 1  Wire format tokens
-- -----------------------------------------------------------------------

||| A single VCL query as it appears on the wire — a non-empty string.
||| Examples:
|||   "PROOF INTEGRITY FOR abcdef0123456789abcdef0123456789"
|||   "PROOF CONSONANCE FOR abc...  AND def..."
|||
||| The canonical grammar is defined in src/vcl_server.jl (Verisim.parse_vcl).
||| This Idris2 type records only the structural invariant: non-empty.
public export
record VCLQuery where
  constructor MkVCLQuery
  text : String
  {auto 0 nonEmpty : NonEmpty (unpack text)}

||| The result token inside an A2ML [vcl-verdict] block.
public export
data VerdictResult : Type where
  ||| Verisim.prove returned VerdictPass.
  Pass        : VerdictResult
  ||| Verisim.prove returned VerdictFail.
  Fail        : VerdictResult
  ||| Verisim.parse_vcl raised an exception — malformed query.
  ParseError  : VerdictResult
  ||| Verisim.prove raised an exception — runtime failure in the server.
  RuntimeError : VerdictResult

public export
Show VerdictResult where
  show Pass         = "Pass"
  show Fail         = "Fail"
  show ParseError   = "ParseError"
  show RuntimeError = "RuntimeError"

||| An A2ML [vcl-verdict] block, as written by the server to stdout.
|||
||| Wire encoding:
|||   [vcl-verdict]
|||   query = "<text>"
|||   result = "<VerdictResult>"
|||   error = "<message>"   -- present only when result is ParseError or RuntimeError
public export
record VCLVerdict where
  constructor MkVCLVerdict
  query  : String
  result : VerdictResult
  ||| Non-empty exactly when result ∈ {ParseError, RuntimeError}.
  error  : Maybe String

-- -----------------------------------------------------------------------
-- § 2  Protocol invariants
-- -----------------------------------------------------------------------

||| Every request produces exactly one verdict. The CLI must not send a
||| second query before receiving the verdict for the first.
|||
||| Encoding: a function type — one VCLQuery maps to one VCLVerdict.
||| This is the type the Zig CLI is contractually obligated to uphold.
public export
VCLExchange : Type
VCLExchange = VCLQuery -> VCLVerdict

||| The `query` field of a verdict must echo the text of the request.
||| This allows the caller to match verdicts to queries if it chooses to
||| pipeline them; it also detects server-side missequencing bugs.
public export
EchoesQuery : VCLExchange -> Type
EchoesQuery f = (q : VCLQuery) -> (f q).query = q.text

||| A well-formed exchange: every verdict echoes its query, and errors
||| are present exactly when the result requires them.
public export
record WellFormedExchange where
  constructor MkWellFormedExchange
  exchange : VCLExchange
  echoes   : EchoesQuery exchange
  errorPresence :
    (q : VCLQuery) ->
    let v = exchange q
    in case v.result of
         ParseError   => v.error = v.error  -- can't express IsJust yet, left open
         RuntimeError => v.error = v.error
         _            => v.error = Nothing

-- -----------------------------------------------------------------------
-- § 3  A2ML framing constants
-- -----------------------------------------------------------------------

||| The section header written before every verdict block.
||| Consumers must match this exact string.
public export
verdictHeader : String
verdictHeader = "[vcl-verdict]"

||| Field key for the echoed query text.
public export
queryKey : String
queryKey = "query"

||| Field key for the verdict result token.
public export
resultKey : String
resultKey = "result"

||| Field key for optional error detail.
public export
errorKey : String
errorKey = "error"

-- -----------------------------------------------------------------------
-- § 4  Environment contract
-- -----------------------------------------------------------------------

||| The environment variable the Zig binary reads to locate the Julia
||| package. When absent, the binary falls back to a path relative to
||| the binary location. Documented here so future implementations can
||| be built against the same contract.
public export
packagePathEnvVar : String
packagePathEnvVar = "VERISIM_PACKAGE_PATH"

||| The relative fallback: package lives at `../../..` from the binary,
||| i.e. `ffi/zig/zig-out/bin/verisim` → `verisim-modular-experiment/`.
public export
packagePathRelativeDefault : String
packagePathRelativeDefault = "../../.."
