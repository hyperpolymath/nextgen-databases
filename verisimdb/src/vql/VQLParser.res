// SPDX-License-Identifier: PMPL-1.0-or-later
// VQL Slipstream Parser - Untyped AST
// Phase 1: Simple parser for slipstream queries (no dependent types)

// ============================================================================
// AST Types
// ============================================================================

module AST = {
  type modality =
    | Graph
    | Vector
    | Tensor
    | Semantic
    | Document
    | Temporal
    | Provenance
    | Spatial
    | All

  type source =
    | Hexad(string)  // UUID
    | Federation(string, option<driftPolicy>)  // pattern, drift policy
    | Store(string)  // store ID
    | Reflect  // Meta-circular: query the query store itself

  and driftPolicy =
    | Strict
    | Repair
    | Tolerate
    | Latest

  type operator =
    | Eq
    | Neq
    | Gt
    | Lt
    | Gte
    | Lte
    | Like
    | Contains
    | Matches

  type condition =
    | Simple(simpleCondition)
    | And(condition, condition)
    | Or(condition, condition)
    | Not(condition)

  and simpleCondition =
    | FulltextContains(string)
    | FulltextMatches(string)
    | FieldCondition(string, operator, literal)
    | VectorSimilar(array<float>, option<float>)  // embedding, threshold
    | GraphPattern(string)  // SPARQL-like pattern (simplified)
    // Phase 2: Cross-modal conditions
    | CrossModalFieldCompare(modality, string, operator, modality, string)
      // e.g., WHERE DOCUMENT.severity > GRAPH.centrality
    | ModalityDrift(modality, modality, float)
      // e.g., WHERE DRIFT(VECTOR, DOCUMENT) > 0.3
    | ModalityExists(modality)
      // e.g., WHERE VECTOR EXISTS
    | ModalityNotExists(modality)
      // e.g., WHERE TENSOR NOT EXISTS
    | ModalityConsistency(modality, modality, string)
      // e.g., WHERE CONSISTENT(VECTOR, SEMANTIC) USING COSINE

  and literal =
    | String(string)
    | Int(int)
    | Float(float)
    | Bool(bool)
    | Array(array<literal>)

  // Field reference: DOCUMENT.name, GRAPH.predicate, etc.
  type fieldRef = {
    modality: modality,
    field: string,
  }

  // Aggregate functions (SQL-compatible)
  type aggregateFunc =
    | Count
    | Sum
    | Avg
    | Min
    | Max

  // Aggregate expression in SELECT
  type aggregateExpr =
    | CountAll                              // COUNT(*)
    | AggregateField(aggregateFunc, fieldRef) // AVG(DOCUMENT.severity)

  // Sort direction for ORDER BY
  type sortDirection =
    | Asc
    | Desc

  // ORDER BY item
  type orderByItem = {
    field: fieldRef,
    direction: sortDirection,
  }

  type query = {
    modalities: array<modality>,
    projections: option<array<fieldRef>>,       // Column selection: DOCUMENT.name, DOCUMENT.severity
    aggregates: option<array<aggregateExpr>>,   // COUNT(*), SUM(DOCUMENT.severity)
    source: source,
    where: option<condition>,
    groupBy: option<array<fieldRef>>,           // GROUP BY DOCUMENT.name
    having: option<condition>,                  // HAVING COUNT(*) > 5
    proof: option<array<proofSpec>>,
    orderBy: option<array<orderByItem>>,        // ORDER BY DOCUMENT.severity DESC
    limit: option<int>,
    offset: option<int>,
  }

  and proofSpec = {
    proofType: proofType,
    contractName: string,
    customParams: option<array<(string, string)>>,  // WITH (key=value, ...) for Custom proofs
  }

  and proofType =
    | Existence
    | Citation
    | Access
    | Integrity
    | Provenance
    | Custom

  // Phase 3: Mutation types (INSERT / UPDATE / DELETE)
  type modalityData =
    | DocumentData(array<(string, literal)>) // field-value pairs
    | VectorData(array<float>) // embedding
    | GraphData(string, string) // edge_type, target_hexad_id
    | TensorData(array<literal>) // tensor values
    | SemanticData(string) // contract name
    | TemporalData(string) // timestamp
    | ProvenanceData(array<(string, literal)>) // event_type, actor, description, source
    | SpatialData(array<(string, literal)>) // latitude, longitude, altitude, geometry_type

  type mutation =
    | Insert({
        modalities: array<modalityData>,
        proof: option<array<proofSpec>>,
      })
    | Update({
        hexadId: string,
        sets: array<(fieldRef, literal)>,
        proof: option<array<proofSpec>>,
      })
    | Delete({
        hexadId: string,
        proof: option<array<proofSpec>>,
      })

  type statement =
    | Query(query)
    | Mutation(mutation)
}

// ============================================================================
// Parser Combinators
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
    input => Ok((value, 0))
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

  let (<|>) = (p1: parser<'a>, p2: parser<'a>): parser<'a> => {
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

  // String matching
  let string = (s: string): parser<string> => {
    input => {
      if Js.String2.startsWith(input, s) {
        Ok((s, Js.String2.length(s)))
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

  let uuid: parser<string> = lexeme(
    regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")
  )

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

  let float: parser<float> = {
    input => {
      let floatStr = lexeme(regex("^[0-9]+\\.[0-9]+"))
      switch floatStr(input) {
      | Ok((str, consumed)) => {
          switch Belt.Float.fromString(str) {
          | Some(f) => Ok((f, consumed))
          | None => Error({message: "Invalid float", position: 0})
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
          // Remove quotes
          let unquoted = Js.String2.slice(str, ~from=1, ~to_=Js.String2.length(str) - 1)
          Ok((unquoted, consumed))
        }
      | Error(e) => Error(e)
      }
    }
  }

  // Many combinator
  let rec many = (p: parser<'a>): parser<array<'a>> => {
    input => {
      switch p(input) {
      | Ok((value, consumed)) => {
          let remaining = Js.String2.sliceToEnd(input, ~from=consumed)
          switch many(p)(remaining) {
          | Ok((values, consumed2)) => Ok(([value]->Js.Array2.concat(values), consumed + consumed2))
          | Error(_) => Ok(([value], consumed))
          }
        }
      | Error(_) => Ok(([], 0))
      }
    }
  }

  let sepBy = (p: parser<'a>, sep: parser<'b>): parser<array<'a>> => {
    input => {
      switch p(input) {
      | Ok((first, consumed1)) => {
          let remaining = Js.String2.sliceToEnd(input, ~from=consumed1)
          let parseRest = bind(sep, _ => p)
          switch many(parseRest)(remaining) {
          | Ok((rest, consumed2)) => Ok(([first]->Js.Array2.concat(rest), consumed1 + consumed2))
          | Error(_) => Ok(([first], consumed1))
          }
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
// VQL Grammar Parsers
// ============================================================================

module Grammar = {
  open Parser
  open AST

  // Modality parser (octad: 8 modalities + All)
  let modality: parser<modality> = {
    let graph = map(keyword("GRAPH"), _ => Graph)
    let vector = map(keyword("VECTOR"), _ => Vector)
    let tensor = map(keyword("TENSOR"), _ => Tensor)
    let semantic = map(keyword("SEMANTIC"), _ => Semantic)
    let document = map(keyword("DOCUMENT"), _ => Document)
    let temporal = map(keyword("TEMPORAL"), _ => Temporal)
    let provenance = map(keyword("PROVENANCE"), _ => Provenance)
    let spatial = map(keyword("SPATIAL"), _ => Spatial)
    let all = map(keyword("*"), _ => All)

    graph <|> vector <|> tensor <|> semantic <|> document <|> temporal <|> provenance <|> spatial <|> all
  }

  let modalityList: parser<array<modality>> = sepBy(modality, keyword(","))

  // Field reference parser: DOCUMENT.name, GRAPH.predicate, etc.
  let fieldRef: parser<AST.fieldRef> = {
    bind(modality, mod =>
      bind(keyword("."), _ =>
        map(identifier, field => {
          AST.modality: mod,
          field: field,
        })
      )
    )
  }

  // Aggregate function name parser
  let aggregateFunc: parser<AST.aggregateFunc> = {
    let count = map(keyword("COUNT"), _ => AST.Count)
    let sum = map(keyword("SUM"), _ => AST.Sum)
    let avg = map(keyword("AVG"), _ => AST.Avg)
    let min_ = map(keyword("MIN"), _ => AST.Min)
    let max_ = map(keyword("MAX"), _ => AST.Max)

    count <|> sum <|> avg <|> min_ <|> max_
  }

  // Aggregate expression parser: COUNT(*) or AVG(DOCUMENT.severity)
  let aggregateExpr: parser<AST.aggregateExpr> = {
    let countAll = {
      bind(keyword("COUNT"), _ =>
        bind(keyword("("), _ =>
          bind(keyword("*"), _ =>
            map(keyword(")"), _ => AST.CountAll)
          )
        )
      )
    }

    let aggregateField = {
      bind(aggregateFunc, func =>
        bind(keyword("("), _ =>
          bind(fieldRef, ref =>
            map(keyword(")"), _ => AST.AggregateField(func, ref))
          )
        )
      )
    }

    countAll <|> aggregateField
  }

  // Extended select item: aggregate | field projection | bare modality
  type selectItem =
    | SelectAggregate(AST.aggregateExpr)
    | SelectField(AST.fieldRef)
    | SelectModality(AST.modality)

  let selectItem: parser<selectItem> = {
    let agg = map(aggregateExpr, a => SelectAggregate(a))
    let field = map(fieldRef, f => SelectField(f))
    let mod = map(modality, m => SelectModality(m))

    agg <|> field <|> mod
  }

  let selectItemList: parser<array<selectItem>> = sepBy(selectItem, keyword(","))

  // Classify select items into modalities, projections, and aggregates
  type classifiedSelect = {
    modalities: array<AST.modality>,
    projections: option<array<AST.fieldRef>>,
    aggregates: option<array<AST.aggregateExpr>>,
  }

  let classifySelect = (items: array<selectItem>): classifiedSelect => {
    let mods = []
    let projs = []
    let aggs = []

    items->Js.Array2.forEach(item => {
      switch item {
      | SelectModality(m) => mods->Js.Array2.push(m)->ignore
      | SelectField(f) => {
          projs->Js.Array2.push(f)->ignore
          // Also add the modality if not already present
          if !(mods->Js.Array2.some(m => m == f.modality)) {
            mods->Js.Array2.push(f.modality)->ignore
          }
        }
      | SelectAggregate(a) => {
          aggs->Js.Array2.push(a)->ignore
          // Add modality from aggregate field ref if present
          switch a {
          | AggregateField(_, ref) =>
            if !(mods->Js.Array2.some(m => m == ref.modality)) {
              mods->Js.Array2.push(ref.modality)->ignore
            }
          | CountAll => ()
          }
        }
      }
    })

    {
      modalities: mods,
      projections: if Js.Array2.length(projs) > 0 { Some(projs) } else { None },
      aggregates: if Js.Array2.length(aggs) > 0 { Some(aggs) } else { None },
    }
  }

  // SELECT clause (extended to support projections and aggregates)
  let selectClause: parser<classifiedSelect> = {
    map(bind(keyword("SELECT"), _ => selectItemList), items => classifySelect(items))
  }

  // Drift policy
  let driftPolicy: parser<driftPolicy> = {
    let strict = map(keyword("STRICT"), _ => Strict)
    let repair = map(keyword("REPAIR"), _ => Repair)
    let tolerate = map(keyword("TOLERATE"), _ => Tolerate)
    let latest = map(keyword("LATEST"), _ => Latest)

    bind(keyword("WITH"), _ =>
      bind(keyword("DRIFT"), _ =>
        strict <|> repair <|> tolerate <|> latest
      )
    )
  }

  // Source parser
  let source: parser<source> = {
    let hexadSource = {
      bind(keyword("HEXAD"), _ =>
        map(uuid, id => Hexad(id))
      )
    }

    let federationSource = {
      bind(keyword("FEDERATION"), _ =>
        bind(identifier, pattern =>
          map(optional(driftPolicy), drift =>
            Federation(pattern, drift)
          )
        )
      )
    }

    let storeSource = {
      bind(keyword("STORE"), _ =>
        map(identifier, id => Store(id))
      )
    }

    hexadSource <|> federationSource <|> storeSource
  }

  // FROM clause
  let fromClause: parser<source> = {
    bind(keyword("FROM"), _ => source)
  }

  // Operators
  let operator: parser<operator> = {
    let eq = map(keyword("=="), _ => Eq)
    let neq = map(keyword("!="), _ => Neq)
    let gte = map(keyword(">="), _ => Gte)
    let lte = map(keyword("<="), _ => Lte)
    let gt = map(keyword(">"), _ => Gt)
    let lt = map(keyword("<"), _ => Lt)
    let like = map(keyword("LIKE"), _ => Like)
    let contains = map(keyword("CONTAINS"), _ => Contains)
    let matches = map(keyword("MATCHES"), _ => Matches)

    eq <|> neq <|> gte <|> lte <|> gt <|> lt <|> like <|> contains <|> matches
  }

  // Literals
  let rec literal: parser<literal> = {
    input => {
      let stringLit = map(stringLiteral, s => String(s))
      let intLit = map(integer, i => Int(i))
      let floatLit = map(float, f => Float(f))
      let boolLit = {
        let t = map(keyword("true"), _ => Bool(true))
        let f = map(keyword("false"), _ => Bool(false))
        t <|> f
      }

      let arrayLit = {
        bind(keyword("["), _ =>
          bind(sepBy(literal, keyword(",")), values =>
            map(keyword("]"), _ => Array(values))
          )
        )
      }

      let p = arrayLit <|> floatLit <|> intLit <|> stringLit <|> boolLit
      p(input)
    }
  }

  // Simple conditions
  let simpleCondition: parser<simpleCondition> = {
    let fulltextContains = {
      bind(keyword("FULLTEXT"), _ =>
        bind(keyword("CONTAINS"), _ =>
          map(stringLiteral, text => FulltextContains(text))
        )
      )
    }

    let fulltextMatches = {
      bind(keyword("FULLTEXT"), _ =>
        bind(keyword("MATCHES"), _ =>
          map(stringLiteral, pattern => FulltextMatches(pattern))
        )
      )
    }

    let fieldCondition = {
      bind(keyword("FIELD"), _ =>
        bind(identifier, field =>
          bind(operator, op =>
            map(literal, value => FieldCondition(field, op, value))
          )
        )
      )
    }

    let vectorSimilar = {
      bind(identifier, _field =>
        bind(keyword("SIMILAR"), _ =>
          bind(keyword("TO"), _ =>
            bind(literal, embedding =>
              map(optional(bind(keyword("WITHIN"), _ => float)), threshold => {
                // Extract floats from array literal
                let floats = switch embedding {
                | Array(arr) => arr->Js.Array2.map(lit =>
                    switch lit {
                    | Float(f) => f
                    | Int(i) => Belt.Int.toFloat(i)
                    | _ => 0.0
                    }
                  )
                | _ => []
                }
                VectorSimilar(floats, threshold)
              })
            )
          )
        )
      )
    }

    let graphPattern = {
      // Simplified: just capture the pattern as string for now
      map(stringLiteral, pattern => GraphPattern(pattern))
    }

    // Phase 2: Cross-modal conditions
    let driftCondition = {
      bind(keyword("DRIFT"), _ =>
        bind(keyword("("), _ =>
          bind(modality, mod1 =>
            bind(keyword(","), _ =>
              bind(modality, mod2 =>
                bind(keyword(")"), _ =>
                  bind(operator, _op =>
                    map(float, threshold =>
                      ModalityDrift(mod1, mod2, threshold)
                    )
                  )
                )
              )
            )
          )
        )
      )
    }

    let consistencyCondition = {
      bind(keyword("CONSISTENT"), _ =>
        bind(keyword("("), _ =>
          bind(modality, mod1 =>
            bind(keyword(","), _ =>
              bind(modality, mod2 =>
                bind(keyword(")"), _ =>
                  bind(keyword("USING"), _ =>
                    map(identifier, metric =>
                      ModalityConsistency(mod1, mod2, metric)
                    )
                  )
                )
              )
            )
          )
        )
      )
    }

    let existsCondition = {
      bind(modality, mod =>
        map(keyword("EXISTS"), _ =>
          ModalityExists(mod)
        )
      )
    }

    let notExistsCondition = {
      bind(modality, mod =>
        bind(keyword("NOT"), _ =>
          map(keyword("EXISTS"), _ =>
            ModalityNotExists(mod)
          )
        )
      )
    }

    // Cross-modal field compare: MODALITY1.field op MODALITY2.field
    let crossModalFieldCompare = {
      bind(modality, mod1 =>
        bind(keyword("."), _ =>
          bind(identifier, field1 =>
            bind(operator, op =>
              bind(modality, mod2 =>
                bind(keyword("."), _ =>
                  map(identifier, field2 =>
                    CrossModalFieldCompare(mod1, field1, op, mod2, field2)
                  )
                )
              )
            )
          )
        )
      )
    }

    driftCondition <|> consistencyCondition <|> notExistsCondition <|> existsCondition <|> crossModalFieldCompare <|> fulltextContains <|> fulltextMatches <|> fieldCondition <|> vectorSimilar <|> graphPattern
  }

  // Compound conditions
  let rec condition: parser<condition> = {
    input => {
      let simple = map(simpleCondition, c => Simple(c))

      let andCond = {
        bind(condition, left =>
          bind(keyword("AND"), _ =>
            map(condition, right => And(left, right))
          )
        )
      }

      let orCond = {
        bind(condition, left =>
          bind(keyword("OR"), _ =>
            map(condition, right => Or(left, right))
          )
        )
      }

      let notCond = {
        bind(keyword("NOT"), _ =>
          map(condition, c => Not(c))
        )
      }

      let p = andCond <|> orCond <|> notCond <|> simple
      p(input)
    }
  }

  // WHERE clause
  let whereClause: parser<condition> = {
    bind(keyword("WHERE"), _ => condition)
  }

  // PROOF clause
  let proofType: parser<proofType> = {
    let existence = map(keyword("EXISTENCE"), _ => Existence)
    let citation = map(keyword("CITATION"), _ => Citation)
    let access = map(keyword("ACCESS"), _ => Access)
    let integrity = map(keyword("INTEGRITY"), _ => Integrity)
    let provenance = map(keyword("PROVENANCE"), _ => Provenance)
    let custom = map(keyword("CUSTOM"), _ => Custom)

    existence <|> citation <|> access <|> integrity <|> provenance <|> custom
  }

  let proofSpec: parser<proofSpec> = {
    bind(proofType, pType =>
      bind(keyword("("), _ =>
        bind(identifier, contract =>
          map(keyword(")"), _ => {
            proofType: pType,
            contractName: contract,
          })
        )
      )
    )
  }

  // Multi-proof: PROOF spec1 AND spec2 AND spec3
  let proofClause: parser<array<proofSpec>> = {
    bind(keyword("PROOF"), _ =>
      sepBy(proofSpec, keyword("AND"))
    )
  }

  // LIMIT clause
  let limitClause: parser<int> = {
    bind(keyword("LIMIT"), _ => integer)
  }

  // OFFSET clause
  let offsetClause: parser<int> = {
    bind(keyword("OFFSET"), _ => integer)
  }

  // GROUP BY clause
  let groupByClause: parser<array<AST.fieldRef>> = {
    bind(keyword("GROUP"), _ =>
      bind(keyword("BY"), _ =>
        sepBy(fieldRef, keyword(","))
      )
    )
  }

  // HAVING clause (reuses condition parser — conditions on aggregates)
  let havingClause: parser<AST.condition> = {
    bind(keyword("HAVING"), _ => condition)
  }

  // Sort direction parser
  let sortDirection: parser<AST.sortDirection> = {
    let asc = map(keyword("ASC"), _ => AST.Asc)
    let desc = map(keyword("DESC"), _ => AST.Desc)

    asc <|> desc
  }

  // ORDER BY item: DOCUMENT.severity DESC | DOCUMENT.name (defaults to ASC)
  let orderByItem: parser<AST.orderByItem> = {
    bind(fieldRef, ref =>
      map(optional(sortDirection), dir => {
        AST.field: ref,
        direction: switch dir {
        | Some(d) => d
        | None => Asc
        },
      })
    )
  }

  // ORDER BY clause
  let orderByClause: parser<array<AST.orderByItem>> = {
    bind(keyword("ORDER"), _ =>
      bind(keyword("BY"), _ =>
        sepBy(orderByItem, keyword(","))
      )
    )
  }

  // Full query parser
  let query: parser<query> = {
    input => {
      // Parse in sequence:
      // SELECT ... FROM ... [WHERE ...] [GROUP BY ...] [HAVING ...]
      // [PROOF ...] [ORDER BY ...] [LIMIT ...] [OFFSET ...]
      let parseQuery = {
        bind(ws, _ =>
          bind(selectClause, classified =>
            bind(fromClause, src =>
              bind(optional(whereClause), whereCond =>
                bind(optional(groupByClause), groupBy =>
                  bind(optional(havingClause), having =>
                    bind(optional(proofClause), proof =>
                      bind(optional(orderByClause), orderBy =>
                        bind(optional(limitClause), lim =>
                          map(optional(offsetClause), off => {
                            modalities: classified.modalities,
                            projections: classified.projections,
                            aggregates: classified.aggregates,
                            source: src,
                            where: whereCond,
                            groupBy: groupBy,
                            having: having,
                            proof: proof,
                            orderBy: orderBy,
                            limit: lim,
                            offset: off,
                          })
                        )
                      )
                    )
                  )
                )
              )
            )
          )
        )
      }

      parseQuery(input)
    }
  }
}

// ============================================================================
// Public API
// ============================================================================

type parseError = Parser.parseError
type query = AST.query

let parse = (input: string): Result<query, parseError> => {
  switch Grammar.query(input) {
  | Ok((query, _consumed)) => Ok(query)
  | Error(e) => Error(e)
  }
}

let parseSlipstream = (input: string): Result<query, parseError> => {
  // Slipstream path: no proof clause allowed
  switch parse(input) {
  | Ok(query) => {
      switch query.proof {
      | Some(proofs) if Js.Array2.length(proofs) > 0 =>
        Error({message: "Slipstream queries cannot have PROOF clause", position: 0})
      | _ => Ok(query)
      }
    }
  | Error(e) => Error(e)
  }
}

let parseDependentType = (input: string): Result<query, parseError> => {
  // Dependent-type path: proof clause required
  switch parse(input) {
  | Ok(query) => {
      if query.proof->Belt.Option.isNone {
        Error({message: "Dependent-type queries require PROOF clause", position: 0})
      } else {
        Ok(query)
      }
    }
  | Error(e) => Error(e)
  }
}

// ============================================================================
// Phase 3: Mutation Parsers
// ============================================================================

type mutation = AST.mutation
type modalityData = AST.modalityData
type statement = AST.statement

module MutationParser = {
  open Parser
  open AST

  // Parse a single modality data entry
  let documentData: parser<modalityData> = {
    bind(keyword("DOCUMENT"), _ =>
      bind(keyword("("), _ =>
        bind(sepBy(
          bind(Grammar.identifier, field =>
            bind(keyword("="), _ =>
              map(Grammar.literal, value => (field, value))
            )
          ),
          keyword(","),
        ), fields =>
          map(keyword(")"), _ => DocumentData(fields))
        )
      )
    )
  }

  let vectorData: parser<modalityData> = {
    bind(keyword("VECTOR"), _ =>
      bind(keyword("("), _ =>
        bind(keyword("["), _ =>
          bind(sepBy(Grammar.float, keyword(",")), values =>
            bind(keyword("]"), _ =>
              map(keyword(")"), _ => VectorData(values))
            )
          )
        )
      )
    )
  }

  let graphData: parser<modalityData> = {
    bind(keyword("GRAPH"), _ =>
      bind(keyword("("), _ =>
        bind(Grammar.identifier, edgeType =>
          bind(keyword(","), _ =>
            bind(Grammar.identifier, targetId =>
              map(keyword(")"), _ => GraphData(edgeType, targetId))
            )
          )
        )
      )
    )
  }

  let tensorData: parser<modalityData> = {
    bind(keyword("TENSOR"), _ =>
      bind(keyword("("), _ =>
        bind(sepBy(Grammar.literal, keyword(",")), values =>
          map(keyword(")"), _ => TensorData(values))
        )
      )
    )
  }

  let semanticData: parser<modalityData> = {
    bind(keyword("SEMANTIC"), _ =>
      bind(keyword("("), _ =>
        bind(Grammar.identifier, contractName =>
          map(keyword(")"), _ => SemanticData(contractName))
        )
      )
    )
  }

  let temporalData: parser<modalityData> = {
    bind(keyword("TEMPORAL"), _ =>
      bind(keyword("("), _ =>
        bind(Grammar.stringLiteral, timestamp =>
          map(keyword(")"), _ => TemporalData(timestamp))
        )
      )
    )
  }

  // PROVENANCE(field=value, ...)
  let provenanceData: parser<modalityData> = {
    bind(keyword("PROVENANCE"), _ =>
      bind(keyword("("), _ =>
        bind(sepBy(
          bind(Grammar.identifier, key =>
            bind(keyword("="), _ =>
              map(Grammar.literal, value => (key, value))
            )
          ),
          keyword(",")
        ), fields =>
          map(keyword(")"), _ => ProvenanceData(fields))
        )
      )
    )
  }

  // SPATIAL(field=value, ...)
  let spatialData: parser<modalityData> = {
    bind(keyword("SPATIAL"), _ =>
      bind(keyword("("), _ =>
        bind(sepBy(
          bind(Grammar.identifier, key =>
            bind(keyword("="), _ =>
              map(Grammar.literal, value => (key, value))
            )
          ),
          keyword(",")
        ), fields =>
          map(keyword(")"), _ => SpatialData(fields))
        )
      )
    )
  }

  let modalityData: parser<modalityData> = {
    documentData <|> vectorData <|> graphData <|> tensorData <|> semanticData <|> temporalData <|> provenanceData <|> spatialData
  }

  // INSERT HEXAD WITH modalityData [, modalityData]* [PROOF ...]
  let insertMutation: parser<mutation> = {
    bind(keyword("INSERT"), _ =>
      bind(keyword("HEXAD"), _ =>
        bind(keyword("WITH"), _ =>
          bind(sepBy(modalityData, keyword(",")), data =>
            map(optional(Grammar.proofClause), proof =>
              Insert({
                modalities: data,
                proof: proof,
              })
            )
          )
        )
      )
    )
  }

  // UPDATE HEXAD uuid SET field = value [, field = value]* [PROOF ...]
  let updateMutation: parser<mutation> = {
    bind(keyword("UPDATE"), _ =>
      bind(keyword("HEXAD"), _ =>
        bind(uuid, id =>
          bind(keyword("SET"), _ =>
            bind(sepBy(
              bind(Grammar.fieldRef, field =>
                bind(keyword("="), _ =>
                  map(Grammar.literal, value => (field, value))
                )
              ),
              keyword(","),
            ), sets =>
              map(optional(Grammar.proofClause), proof =>
                Update({
                  hexadId: id,
                  sets: sets,
                  proof: proof,
                })
              )
            )
          )
        )
      )
    )
  }

  // DELETE HEXAD uuid [PROOF ...]
  let deleteMutation: parser<mutation> = {
    bind(keyword("DELETE"), _ =>
      bind(keyword("HEXAD"), _ =>
        bind(uuid, id =>
          map(optional(Grammar.proofClause), proof =>
            Delete({
              hexadId: id,
              proof: proof,
            })
          )
        )
      )
    )
  }

  let mutation: parser<mutation> = {
    insertMutation <|> updateMutation <|> deleteMutation
  }

  // Top-level statement: query or mutation
  let statement: parser<statement> = {
    input => {
      let queryP = map(Grammar.query, q => Query(q))
      let mutationP = map(mutation, m => Mutation(m))

      let p = bind(ws, _ => mutationP <|> queryP)
      p(input)
    }
  }
}

let parseMutation = (input: string): Result<AST.mutation, parseError> => {
  switch MutationParser.mutation(input) {
  | Ok((m, _consumed)) => Ok(m)
  | Error(e) => Error(e)
  }
}

let parseStatement = (input: string): Result<AST.statement, parseError> => {
  switch MutationParser.statement(input) {
  | Ok((s, _consumed)) => Ok(s)
  | Error(e) => Error(e)
  }
}

// ============================================================================
// Example Usage
// ============================================================================

/*
// Slipstream query
let slipstreamQuery = `
  SELECT GRAPH, VECTOR
  FROM FEDERATION /universities/*
  WHERE FULLTEXT CONTAINS "machine learning"
  LIMIT 100
`

switch parseSlipstream(slipstreamQuery) {
| Ok(query) => Js.Console.log(query)
| Error(e) => Js.Console.error(e.message)
}

// Dependent-type query
let dependentQuery = `
  SELECT GRAPH, VECTOR
  FROM HEXAD 550e8400-e29b-41d4-a716-446655440000
  WHERE h.embedding SIMILAR TO [0.1, 0.2, 0.3] WITHIN 0.9
    AND FULLTEXT CONTAINS "climate change"
  PROOF CITATION(CitationContract)
  LIMIT 50
`

switch parseDependentType(dependentQuery) {
| Ok(query) => Js.Console.log(query)
| Error(e) => Js.Console.error(e.message)
}

// SQL-compatible query with column projections, aggregates, ORDER BY, GROUP BY
let sqlCompatQuery = `
  SELECT DOCUMENT.name, DOCUMENT.severity, COUNT(*), AVG(DOCUMENT.severity)
  FROM FEDERATION /universities/*
  WHERE FIELD severity > 5
  GROUP BY DOCUMENT.name, DOCUMENT.severity
  HAVING FIELD count > 3
  ORDER BY DOCUMENT.severity DESC
  LIMIT 50
`

switch parseSlipstream(sqlCompatQuery) {
| Ok(query) => Js.Console.log(query)
| Error(e) => Js.Console.error(e.message)
}
*/
