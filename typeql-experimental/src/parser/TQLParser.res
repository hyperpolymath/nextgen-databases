// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// TQLParser.res — Parser for VQL-dt++ extended syntax
//
// Implements parser combinators for the six new VQL-dt++ clauses:
// 1. CONSUME AFTER n USE       — Linear types
// 2. WITH SESSION protocol     — Session types
// 3. EFFECTS { e1, e2, ... }   — Effect systems
// 4. IN TRANSACTION state      — Modal types
// 5. PROOF ATTACHED theorem    — Proof-carrying code
// 6. USAGE LIMIT n             — Quantitative type theory
//
// Follows the same combinator pattern as VeriSimDB's VQLParser.res.

// ============================================================================
// Parser Combinators (same pattern as VQLParser.res)
// ============================================================================

module Parser = {
  type parseError = {
    message: string,
    position: int,
  }

  type parseResult<'a> = Result<('a, int), parseError>

  type parser<'a> = string => parseResult<'a>

  // Basic combinators
  let pure = (value: 'a): parser<'a> => {
    _input => Ok((value, 0))
  }

  let fail = (message: string): parser<'a> => {
    _input => Error({message, position: 0})
  }

  let map = (p: parser<'a>, f: 'a => 'b): parser<'b> => {
    input => {
      switch p(input) {
      | Ok((value, consumed)) => Ok((f(value), consumed))
      | Error(e) => Error(e)
      }
    }
  }

  let bind = (p: parser<'a>, f: 'a => parser<'b>): parser<'b> => {
    input => {
      switch p(input) {
      | Ok((value, consumed)) => {
          let remaining = Js.String2.sliceToEnd(input, ~from=consumed)
          switch f(value)(remaining) {
          | Ok((value2, consumed2)) => Ok((value2, consumed + consumed2))
          | Error(e) => Error({...e, position: e.position + consumed})
          }
        }
      | Error(e) => Error(e)
      }
    }
  }

  let \"<|>" = (p1: parser<'a>, p2: parser<'a>): parser<'a> => {
    input => {
      switch p1(input) {
      | Ok(result) => Ok(result)
      | Error(_) => p2(input)
      }
    }
  }

  // Whitespace handling
  let ws: parser<unit> = input => {
    let trimmed = Js.String2.trimStart(input)
    let consumed = Js.String2.length(input) - Js.String2.length(trimmed)
    Ok(((), consumed))
  }

  let lexeme = (p: parser<'a>): parser<'a> => {
    bind(p, value => map(ws, _ => value))
  }

  // String matching (case-insensitive for keywords)
  let string = (s: string): parser<string> => {
    input => {
      let len = Js.String2.length(s)
      let prefix = Js.String2.slice(input, ~from=0, ~to_=len)
      if Js.String2.toUpperCase(prefix) == Js.String2.toUpperCase(s) {
        Ok((s, len))
      } else {
        Error({message: `Expected "${s}"`, position: 0})
      }
    }
  }

  let keyword = (k: string): parser<string> => {
    lexeme(string(k))
  }

  // Regex-based parsers
  let regex = (pattern: string): parser<string> => {
    input => {
      let re = Js.Re.fromStringWithFlags(pattern, ~flags="i")
      switch Js.Re.exec_(re, input) {
      | Some(result) => {
          let matched = Js.Re.captures(result)[0]
          switch Js.Nullable.toOption(matched) {
          | Some(str) => Ok((str, Js.String2.length(str)))
          | None => Error({message: `Regex ${pattern} failed`, position: 0})
          }
        }
      | None => Error({message: `Regex ${pattern} failed`, position: 0})
      }
    }
  }

  let identifier: parser<string> = lexeme(regex("^[a-zA-Z_][a-zA-Z0-9_]*"))

  let integer: parser<int> = {
    input => {
      let intStr = lexeme(regex("^[0-9]+"))
      switch intStr(input) {
      | Ok((str, consumed)) => {
          switch Belt.Int.fromString(str) {
          | Some(n) => Ok((n, consumed))
          | None => Error({message: "Invalid integer", position: 0})
          }
        }
      | Error(e) => Error(e)
      }
    }
  }

  let stringLiteral: parser<string> = {
    input => {
      let quoted = lexeme(regex("^\"([^\"\\\\]|\\\\.)*\""))
      switch quoted(input) {
      | Ok((str, consumed)) => {
          let unquoted = Js.String2.slice(str, ~from=1, ~to_=Js.String2.length(str) - 1)
          Ok((unquoted, consumed))
        }
      | Error(e) => Error(e)
      }
    }
  }

  let sepBy = (p: parser<'a>, sep: parser<'b>): parser<array<'a>> => {
    input => {
      switch p(input) {
      | Ok((first, consumed1)) => {
          let rec loop = (remaining, acc, totalConsumed) => {
            let parseRest = bind(sep, _ => p)
            switch parseRest(remaining) {
            | Ok((value, consumed2)) => {
                let newRemaining = Js.String2.sliceToEnd(remaining, ~from=consumed2)
                loop(newRemaining, acc->Js.Array2.concat([value]), totalConsumed + consumed2)
              }
            | Error(_) => Ok((acc, totalConsumed))
            }
          }
          let remaining = Js.String2.sliceToEnd(input, ~from=consumed1)
          loop(remaining, [first], consumed1)
        }
      | Error(e) => Error(e)
      }
    }
  }

  let optional = (p: parser<'a>): parser<option<'a>> => {
    input => {
      switch p(input) {
      | Ok((value, consumed)) => Ok((Some(value), consumed))
      | Error(_) => Ok((None, 0))
      }
    }
  }
}

// ============================================================================
// Extension Clause Parsers
// ============================================================================

module ExtensionParsers = {
  open Parser
  open TQLAst

  // --------------------------------------------------------------------------
  // 1. CONSUME AFTER n USE — Linear Types
  // --------------------------------------------------------------------------

  let consumeClause: parser<usageSpec> = {
    bind(keyword("CONSUME"), _ =>
      bind(keyword("AFTER"), _ =>
        bind(integer, count =>
          map(keyword("USE"), _ => {
            TQLAst.count: count,
          })
        )
      )
    )
  }

  // --------------------------------------------------------------------------
  // 2. WITH SESSION protocol — Session Types
  // --------------------------------------------------------------------------

  let sessionProtocol: parser<sessionProtocol> = {
    let readOnly = map(keyword("ReadOnlyProtocol"), _ => ReadOnlyProtocol)
    let mutation = map(keyword("MutationProtocol"), _ => MutationProtocol)
    let stream = map(keyword("StreamProtocol"), _ => StreamProtocol)
    let batch = map(keyword("BatchProtocol"), _ => BatchProtocol)
    let custom = map(identifier, name => CustomProtocol(name))

    \"<|>"(readOnly, \"<|>"(mutation, \"<|>"(stream, \"<|>"(batch, custom))))
  }

  let sessionClause: parser<sessionProtocol> = {
    bind(keyword("WITH"), _ =>
      bind(keyword("SESSION"), _ =>
        sessionProtocol
      )
    )
  }

  // --------------------------------------------------------------------------
  // 3. EFFECTS { e1, e2, ... } — Effect Systems
  // --------------------------------------------------------------------------

  let effectLabel: parser<effectLabel> = {
    let read = map(keyword("Read"), _ => ReadEffect)
    let write = map(keyword("Write"), _ => WriteEffect)
    let cite = map(keyword("Cite"), _ => CiteEffect)
    let audit = map(keyword("Audit"), _ => AuditEffect)
    let transform = map(keyword("Transform"), _ => TransformEffect)
    let federate = map(keyword("Federate"), _ => FederateEffect)
    let custom = map(identifier, name => CustomEffect(name))

    \"<|>"(read, \"<|>"(write, \"<|>"(cite, \"<|>"(audit, \"<|>"(transform, \"<|>"(federate, custom))))))
  }

  let effectsClause: parser<effectDecl> = {
    bind(keyword("EFFECTS"), _ =>
      bind(keyword("{"), _ =>
        bind(sepBy(effectLabel, keyword(",")), effects =>
          map(keyword("}"), _ => {
            TQLAst.effects: effects,
          })
        )
      )
    )
  }

  // --------------------------------------------------------------------------
  // 4. IN TRANSACTION state — Modal Types
  // --------------------------------------------------------------------------

  let transactionState: parser<transactionState> = {
    let fresh = map(keyword("Fresh"), _ => TxFresh)
    let active = map(keyword("Active"), _ => TxActive)
    let committed = map(keyword("Committed"), _ => TxCommitted)
    let rolledBack = map(keyword("RolledBack"), _ => TxRolledBack)
    let readSnapshot = map(keyword("ReadSnapshot"), _ => TxReadSnapshot)
    let custom = map(identifier, name => TxCustom(name))

    \"<|>"(fresh, \"<|>"(active, \"<|>"(committed, \"<|>"(rolledBack, \"<|>"(readSnapshot, custom)))))
  }

  let modalClause: parser<modalDecl> = {
    bind(keyword("IN"), _ =>
      bind(keyword("TRANSACTION"), _ =>
        map(transactionState, state => {
          TQLAst.state: state,
        })
      )
    )
  }

  // --------------------------------------------------------------------------
  // 5. PROOF ATTACHED theorem — Proof-Carrying Code
  // --------------------------------------------------------------------------

  let theoremParams: parser<array<(string, string)>> = {
    bind(keyword("("), _ =>
      bind(sepBy(
        bind(identifier, key =>
          bind(keyword("="), _ =>
            map(stringLiteral, value => (key, value))
          )
        ),
        keyword(","),
      ), params =>
        map(keyword(")"), _ => params)
      )
    )
  }

  let proofAttachedClause: parser<theoremRef> = {
    bind(keyword("PROOF"), _ =>
      bind(keyword("ATTACHED"), _ =>
        bind(identifier, name =>
          map(optional(theoremParams), params => {
            TQLAst.name: name,
            params: params,
          })
        )
      )
    )
  }

  // --------------------------------------------------------------------------
  // 6. USAGE LIMIT n — Quantitative Type Theory
  // --------------------------------------------------------------------------

  let usageLimitClause: parser<usageLimit> = {
    bind(keyword("USAGE"), _ =>
      bind(keyword("LIMIT"), _ =>
        map(integer, limit => {
          TQLAst.limit: limit,
        })
      )
    )
  }

  // --------------------------------------------------------------------------
  // Combined: Parse all extension clauses (all optional)
  // --------------------------------------------------------------------------

  let extensionAnnotations: parser<extensionAnnotations> = {
    bind(optional(consumeClause), consume =>
      bind(optional(sessionClause), session =>
        bind(optional(effectsClause), effects =>
          bind(optional(modalClause), modal =>
            bind(optional(proofAttachedClause), proof =>
              map(optional(usageLimitClause), usage => {
                consumeAfter: consume,
                sessionProtocol: session,
                declaredEffects: effects,
                modalScope: modal,
                proofAttached: proof,
                usageLimit: usage,
              })
            )
          )
        )
      )
    )
  }
}

// ============================================================================
// Public API
// ============================================================================

type parseError = Parser.parseError

// Parse just the extension annotations (after the base VQL query).
// Input should be the remainder of the query string after the base VQL
// grammar has been parsed.
let parseExtensions = (input: string): Result<TQLAst.extensionAnnotations, parseError> => {
  let p = Parser.bind(Parser.ws, _ => ExtensionParsers.extensionAnnotations)
  switch p(input) {
  | Ok((annotations, _consumed)) => Ok(annotations)
  | Error(e) => Error(e)
  }
}

// Validate parsed extension annotations for semantic correctness.
// Checks:
// - CONSUME AFTER count must be positive
// - USAGE LIMIT must be positive
// - USAGE LIMIT >= CONSUME AFTER when both present
let validateExtensions = (ann: TQLAst.extensionAnnotations): Result<TQLAst.extensionAnnotations, string> => {
  // Check CONSUME AFTER is positive
  switch ann.consumeAfter {
  | Some({count}) if count <= 0 =>
    Error("CONSUME AFTER count must be positive, got " ++ Belt.Int.toString(count))
  | _ => {
      // Check USAGE LIMIT is positive
      switch ann.usageLimit {
      | Some({limit}) if limit <= 0 =>
        Error("USAGE LIMIT must be positive, got " ++ Belt.Int.toString(limit))
      | _ => {
          // Cross-check: USAGE LIMIT >= CONSUME AFTER
          switch (ann.consumeAfter, ann.usageLimit) {
          | (Some({count}), Some({limit})) if limit < count =>
            Error(
              "USAGE LIMIT (" ++ Belt.Int.toString(limit) ++
              ") must be >= CONSUME AFTER (" ++ Belt.Int.toString(count) ++ ")"
            )
          | _ => Ok(ann)
          }
        }
      }
    }
  }
}

// Parse and validate extension annotations in one step.
let parseAndValidateExtensions = (input: string): Result<TQLAst.extensionAnnotations, string> => {
  switch parseExtensions(input) {
  | Ok(ann) => validateExtensions(ann)
  | Error(e) => Error(e.message)
  }
}
