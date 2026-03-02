// SPDX-License-Identifier: PMPL-1.0-or-later

/**
 * VQL Error Types - Structured error representation
 *
 * Provides comprehensive error types for all VQL failure modes:
 * - Parse errors (syntax)
 * - Type errors (dependent-type verification)
 * - Runtime errors (execution)
 * - Modality-specific errors
 * - Federation errors
 */

type position = {
  line: int,
  column: int,
  offset: int,
}

type span = {
  start: position,
  end_: position,
}

// ============================================================================
// Parse Errors
// ============================================================================

type parseErrorKind =
  | UnexpectedToken({expected: array<string>, found: string})
  | UnterminatedString
  | InvalidNumber(string)
  | InvalidModality(string)
  | InvalidDriftPolicy(string)
  | InvalidProofType(string)
  | MissingFromClause
  | MissingSelectClause
  | InvalidGraphPattern(string)
  | InvalidVectorExpression(string)
  | InvalidSemanticContract(string)
  | InvalidAggregateExpression(string)
  | InvalidOrderByField(string)
  | InvalidGroupByField(string)
  | HavingWithoutGroupBy
  | AggregateWithoutGroupBy(string)

type parseError = {
  kind: parseErrorKind,
  span: span,
  source: string, // The original query string
  hint: option<string>,
}

// ============================================================================
// Type Errors (Dependent-Type Path)
// ============================================================================

type typeErrorKind =
  | ContractNotFound(string)
  | ContractViolation({contract: string, reason: string})
  | ProofGenerationFailed({contract: string, error: string})
  | ProofVerificationFailed({contract: string, reason: string})
  | TypeMismatch({expected: string, found: string})
  | MissingTypeAnnotation(string)
  | CircularDependency(array<string>)
  // Phase 1: Dependent type errors
  | SubtypingFailed({expected: string, got: string})
  | FieldTypeMismatch({field: string, expected: string, got: string})
  | OperatorTypeMismatch({op: string, leftType: string, rightType: string})
  | VectorDimensionMismatch({expected: int, got: int})
  | ProofObligationFailed({proofType: string, reason: string})
  | AggregateTypeMismatch({func: string, fieldType: string})
  | MultiProofConflict({proof1: string, proof2: string, reason: string})
  | UnknownField({modality: string, fieldName: string})
  // Phase 2: Cross-modal errors
  | CrossModalTypeMismatch({mod1: string, field1: string, mod2: string, field2: string, reason: string})
  | DriftRequiresNumeric({mod1: string, mod2: string})
  | ConsistencyMetricInvalid({mod1: string, mod2: string, metric: string})
  // Phase 3: Write path errors
  | InsertConflict(string)
  | UpdateNotFound(string)
  | DeleteNotFound(string)
  | ConstraintViolation({field: string, constraint: string, value: string})
  | WriteProofFailed({proofType: string, reason: string})
  | ReadOnlyStore(string)

type typeError = {
  kind: typeErrorKind,
  hexad_id: option<string>,
  modality: option<string>,
  context: string,
}

// ============================================================================
// Runtime Errors
// ============================================================================

type runtimeErrorKind =
  | StoreUnavailable({store_id: string, reason: string})
  | QueryTimeout({duration_ms: int, limit_ms: int})
  | DriftDetected({hexad_id: string, details: string})
  | PermissionDenied({user_id: option<string>, resource: string})
  | ResourceExhausted({resource: string, limit: string})
  | InvalidHexadId(string)
  | NetworkError({endpoint: string, status: option<int>})
  | InternalError(string)

type runtimeError = {
  kind: runtimeErrorKind,
  query_id: option<string>,
  timestamp: Js.Date.t,
  recoverable: bool,
}

// ============================================================================
// Modality-Specific Errors
// ============================================================================

type graphError =
  | MalformedRDF(string)
  | InvalidTriplePattern(string)
  | CycleDetected(array<string>)
  | PredicateNotFound(string)
  | TraversalDepthExceeded(int)

type vectorError =
  | DimensionMismatch({expected: int, found: int})
  | InvalidDistanceMetric(string)
  | EmbeddingNotFound(string)
  | ANNIndexUnavailable(string)

type tensorError =
  | ShapeMismatch({expected: array<int>, found: array<int>})
  | NumericOverflow(string)
  | InvalidOperation(string)
  | UnsupportedDtype(string)

type semanticError =
  | InvalidContract(string)
  | ZKPVerificationFailed(string)
  | WitnessGenerationFailed(string)
  | ContractExpired(string)

type documentError =
  | InvalidFullTextQuery(string)
  | UnsupportedLanguage(string)
  | IndexCorrupted(string)

type temporalError =
  | InvalidTimestamp(string)
  | VersionNotFound({hexad_id: string, timestamp: string})
  | MerkleVerificationFailed(string)
  | TemporalConflict(string)

type provenanceError =
  | ChainCorrupted({hexad_id: string, broken_at: int})
  | ChainNotFound(string)
  | InvalidProvenanceEvent(string)

type spatialError =
  | InvalidCoordinates({latitude: float, longitude: float})
  | InvalidBounds(string)
  | SpatialIndexError(string)

type modalityError =
  | GraphError(graphError)
  | VectorError(vectorError)
  | TensorError(tensorError)
  | SemanticError(semanticError)
  | DocumentError(documentError)
  | TemporalError(temporalError)
  | ProvenanceError(provenanceError)
  | SpatialError(spatialError)

// ============================================================================
// Federation Errors
// ============================================================================

type federationErrorKind =
  | RemoteStoreUnreachable({endpoint: string, timeout_ms: int})
  | PartialResults({succeeded: array<string>, failed: array<string>})
  | CrossOrgAccessDenied({org_id: string, resource: string})
  | ByzantineFaultDetected({suspicious_nodes: array<string>})
  | ConsensusTimeout({participants: int, duration_ms: int})
  | FederationPolicyViolation(string)

type federationError = {
  kind: federationErrorKind,
  federation_pattern: string,
  affected_stores: array<string>,
}

// ============================================================================
// Composite Error Type
// ============================================================================

type vqlError =
  | ParseError(parseError)
  | TypeError(typeError)
  | RuntimeError(runtimeError)
  | ModalityError(modalityError)
  | FederationError(federationError)
  | MultipleErrors(array<vqlError>)

// ============================================================================
// Error Formatting
// ============================================================================

let formatPosition = (pos: position): string => {
  `${pos.line->Int.toString}:${pos.column->Int.toString}`
}

let formatSpan = (span: span): string => {
  `${formatPosition(span.start)}-${formatPosition(span.end_)}`
}

let formatParseError = (err: parseError): string => {
  let kindStr = switch err.kind {
  | UnexpectedToken({expected, found}) =>
    `Expected ${expected->Array.joinWith(", ", x => `'${x}'`)}, found '${found}'`
  | UnterminatedString => "Unterminated string literal"
  | InvalidNumber(num) => `Invalid number: '${num}'`
  | InvalidModality(mod) => `Invalid modality: '${mod}'. Valid: GRAPH, VECTOR, TENSOR, SEMANTIC, DOCUMENT, TEMPORAL`
  | InvalidDriftPolicy(policy) => `Invalid drift policy: '${policy}'. Valid: STRICT, REPAIR, TOLERATE, LATEST`
  | InvalidProofType(proof) => `Invalid proof type: '${proof}'. Valid: EXISTENCE, CITATION, ACCESS, INTEGRITY, PROVENANCE`
  | MissingFromClause => "Missing FROM clause"
  | MissingSelectClause => "Missing SELECT clause"
  | InvalidGraphPattern(pattern) => `Invalid graph pattern: '${pattern}'`
  | InvalidVectorExpression(expr) => `Invalid vector expression: '${expr}'`
  | InvalidSemanticContract(contract) => `Invalid semantic contract: '${contract}'`
  | InvalidAggregateExpression(expr) => `Invalid aggregate expression: '${expr}'. Valid: COUNT(*), SUM(M.field), AVG(M.field), MIN(M.field), MAX(M.field)`
  | InvalidOrderByField(field) => `Invalid ORDER BY field: '${field}'. Use MODALITY.field format`
  | InvalidGroupByField(field) => `Invalid GROUP BY field: '${field}'. Use MODALITY.field format`
  | HavingWithoutGroupBy => "HAVING clause requires GROUP BY"
  | AggregateWithoutGroupBy(func) => `Aggregate function ${func} used without GROUP BY clause`
  }

  let hintStr = switch err.hint {
  | Some(hint) => `\n  Hint: ${hint}`
  | None => ""
  }

  `Parse Error at ${formatSpan(err.span)}: ${kindStr}${hintStr}`
}

let formatTypeError = (err: typeError): string => {
  let kindStr = switch err.kind {
  | ContractNotFound(contract) => `Contract not found: '${contract}'`
  | ContractViolation({contract, reason}) => `Contract '${contract}' violated: ${reason}`
  | ProofGenerationFailed({contract, error}) => `Failed to generate proof for '${contract}': ${error}`
  | ProofVerificationFailed({contract, reason}) => `Proof verification failed for '${contract}': ${reason}`
  | TypeMismatch({expected, found}) => `Type mismatch: expected ${expected}, found ${found}`
  | MissingTypeAnnotation(field) => `Missing type annotation for field: '${field}'`
  | CircularDependency(cycle) => `Circular dependency detected: ${cycle->Array.joinWith(" → ", x => x)}`
  // Phase 1
  | SubtypingFailed({expected, got}) =>
    `Subtyping failed: expected ${expected}, got ${got}`
  | FieldTypeMismatch({field, expected, got}) =>
    `Field '${field}' type mismatch: expected ${expected}, got ${got}`
  | OperatorTypeMismatch({op, leftType, rightType}) =>
    `Operator '${op}' cannot compare ${leftType} with ${rightType}`
  | VectorDimensionMismatch({expected, got}) =>
    `Vector dimension mismatch: expected ${expected->Int.toString}, got ${got->Int.toString}`
  | ProofObligationFailed({proofType, reason}) =>
    `Proof obligation '${proofType}' failed: ${reason}`
  | AggregateTypeMismatch({func, fieldType}) =>
    `Aggregate function ${func} cannot operate on ${fieldType}`
  | MultiProofConflict({proof1, proof2, reason}) =>
    `Proofs '${proof1}' and '${proof2}' conflict: ${reason}`
  | UnknownField({modality, fieldName}) =>
    `Unknown field '${fieldName}' for modality ${modality}`
  // Phase 2
  | CrossModalTypeMismatch({mod1, field1, mod2, field2, reason}) =>
    `Cross-modal type mismatch: ${mod1}.${field1} vs ${mod2}.${field2}: ${reason}`
  | DriftRequiresNumeric({mod1, mod2}) =>
    `DRIFT requires numeric/vector modalities: ${mod1}, ${mod2}`
  | ConsistencyMetricInvalid({mod1, mod2, metric}) =>
    `Metric '${metric}' not supported for ${mod1} and ${mod2}`
  // Phase 3
  | InsertConflict(hexadId) => `INSERT conflict: hexad '${hexadId}' already exists`
  | UpdateNotFound(hexadId) => `UPDATE failed: hexad '${hexadId}' not found`
  | DeleteNotFound(hexadId) => `DELETE failed: hexad '${hexadId}' not found`
  | ConstraintViolation({field, constraint, value}) =>
    `Constraint violation on '${field}': ${constraint} (value: ${value})`
  | WriteProofFailed({proofType, reason}) =>
    `Write proof '${proofType}' failed: ${reason}`
  | ReadOnlyStore(storeId) => `Store '${storeId}' is read-only`
  }

  let contextStr = switch (err.hexad_id, err.modality) {
  | (Some(hexad), Some(mod)) => ` [hexad: ${hexad}, modality: ${mod}]`
  | (Some(hexad), None) => ` [hexad: ${hexad}]`
  | (None, Some(mod)) => ` [modality: ${mod}]`
  | (None, None) => ""
  }

  `Type Error${contextStr}: ${kindStr}\n  Context: ${err.context}`
}

let formatRuntimeError = (err: runtimeError): string => {
  let kindStr = switch err.kind {
  | StoreUnavailable({store_id, reason}) => `Store '${store_id}' unavailable: ${reason}`
  | QueryTimeout({duration_ms, limit_ms}) => `Query timeout: exceeded ${limit_ms}ms (ran for ${duration_ms}ms)`
  | DriftDetected({hexad_id, details}) => `Drift detected for hexad '${hexad_id}': ${details}`
  | PermissionDenied({user_id, resource}) => {
      let user = switch user_id {
      | Some(id) => `user '${id}'`
      | None => "user"
      }
      `Permission denied: ${user} cannot access '${resource}'`
    }
  | ResourceExhausted({resource, limit}) => `Resource exhausted: ${resource} (limit: ${limit})`
  | InvalidHexadId(id) => `Invalid hexad ID: '${id}'`
  | NetworkError({endpoint, status}) => {
      let statusStr = switch status {
      | Some(code) => ` (HTTP ${code->Int.toString})`
      | None => ""
      }
      `Network error connecting to '${endpoint}'${statusStr}`
    }
  | InternalError(msg) => `Internal error: ${msg}`
  }

  let recoverable = if err.recoverable {
    " [recoverable]"
  } else {
    " [non-recoverable]"
  }

  `Runtime Error${recoverable}: ${kindStr}`
}

let formatModalityError = (err: modalityError): string => {
  switch err {
  | GraphError(ge) =>
    switch ge {
    | MalformedRDF(msg) => `Graph Error: Malformed RDF: ${msg}`
    | InvalidTriplePattern(pattern) => `Graph Error: Invalid triple pattern: '${pattern}'`
    | CycleDetected(path) => `Graph Error: Cycle detected: ${path->Array.joinWith(" → ", x => x)}`
    | PredicateNotFound(pred) => `Graph Error: Predicate not found: '${pred}'`
    | TraversalDepthExceeded(depth) => `Graph Error: Traversal depth exceeded: ${depth->Int.toString}`
    }
  | VectorError(ve) =>
    switch ve {
    | DimensionMismatch({expected, found}) => `Vector Error: Dimension mismatch: expected ${expected->Int.toString}, found ${found->Int.toString}`
    | InvalidDistanceMetric(metric) => `Vector Error: Invalid distance metric: '${metric}'`
    | EmbeddingNotFound(id) => `Vector Error: Embedding not found: '${id}'`
    | ANNIndexUnavailable(reason) => `Vector Error: ANN index unavailable: ${reason}`
    }
  | TensorError(te) =>
    switch te {
    | ShapeMismatch({expected, found}) => {
        let expStr = expected->Array.map(Int.toString)->Array.joinWith("×", x => x)
        let foundStr = found->Array.map(Int.toString)->Array.joinWith("×", x => x)
        `Tensor Error: Shape mismatch: expected [${expStr}], found [${foundStr}]`
      }
    | NumericOverflow(msg) => `Tensor Error: Numeric overflow: ${msg}`
    | InvalidOperation(op) => `Tensor Error: Invalid operation: '${op}'`
    | UnsupportedDtype(dtype) => `Tensor Error: Unsupported dtype: '${dtype}'`
    }
  | SemanticError(se) =>
    switch se {
    | InvalidContract(contract) => `Semantic Error: Invalid contract: '${contract}'`
    | ZKPVerificationFailed(reason) => `Semantic Error: ZKP verification failed: ${reason}`
    | WitnessGenerationFailed(reason) => `Semantic Error: Witness generation failed: ${reason}`
    | ContractExpired(contract) => `Semantic Error: Contract expired: '${contract}'`
    }
  | DocumentError(de) =>
    switch de {
    | InvalidFullTextQuery(query) => `Document Error: Invalid full-text query: '${query}'`
    | UnsupportedLanguage(lang) => `Document Error: Unsupported language: '${lang}'`
    | IndexCorrupted(index) => `Document Error: Index corrupted: '${index}'`
    }
  | TemporalError(te) =>
    switch te {
    | InvalidTimestamp(ts) => `Temporal Error: Invalid timestamp: '${ts}'`
    | VersionNotFound({hexad_id, timestamp}) => `Temporal Error: Version not found for hexad '${hexad_id}' at '${timestamp}'`
    | MerkleVerificationFailed(reason) => `Temporal Error: Merkle verification failed: ${reason}`
    | TemporalConflict(msg) => `Temporal Error: Temporal conflict: ${msg}`
    }
  }
}

let formatFederationError = (err: federationError): string => {
  let kindStr = switch err.kind {
  | RemoteStoreUnreachable({endpoint, timeout_ms}) => `Remote store unreachable: '${endpoint}' (timeout: ${timeout_ms->Int.toString}ms)`
  | PartialResults({succeeded, failed}) => {
      let succStr = succeeded->Array.joinWith(", ", x => x)
      let failStr = failed->Array.joinWith(", ", x => x)
      `Partial results: succeeded=[${succStr}], failed=[${failStr}]`
    }
  | CrossOrgAccessDenied({org_id, resource}) => `Cross-org access denied: org '${org_id}' cannot access '${resource}'`
  | ByzantineFaultDetected({suspicious_nodes}) => `Byzantine fault detected: suspicious nodes=[${suspicious_nodes->Array.joinWith(", ", x => x)}]`
  | ConsensusTimeout({participants, duration_ms}) => `Consensus timeout: ${participants->Int.toString} participants, ${duration_ms->Int.toString}ms`
  | FederationPolicyViolation(msg) => `Federation policy violation: ${msg}`
  }

  `Federation Error [${err.federation_pattern}]: ${kindStr}`
}

let format = (err: vqlError): string => {
  switch err {
  | ParseError(e) => formatParseError(e)
  | TypeError(e) => formatTypeError(e)
  | RuntimeError(e) => formatRuntimeError(e)
  | ModalityError(e) => formatModalityError(e)
  | FederationError(e) => formatFederationError(e)
  | MultipleErrors(errors) => {
      let header = `Multiple Errors (${errors->Array.length->Int.toString}):`
      let formatted = errors->Array.mapWithIndex((err, idx) => {
        `  ${(idx + 1)->Int.toString}. ${format(err)}`
      })
      [header]->Array.concat(formatted)->Array.joinWith("\n", x => x)
    }
  }
}

// ============================================================================
// Error Helpers
// ============================================================================

let isRecoverable = (err: vqlError): bool => {
  switch err {
  | RuntimeError(e) => e.recoverable
  | FederationError({kind: PartialResults(_)}) => true
  | FederationError({kind: RemoteStoreUnreachable(_)}) => true
  | _ => false
  }
}

let getErrorCode = (err: vqlError): string => {
  switch err {
  | ParseError(_) => "VQL_PARSE_ERROR"
  | TypeError(_) => "VQL_TYPE_ERROR"
  | RuntimeError({kind: StoreUnavailable(_)}) => "VQL_STORE_UNAVAILABLE"
  | RuntimeError({kind: QueryTimeout(_)}) => "VQL_QUERY_TIMEOUT"
  | RuntimeError({kind: DriftDetected(_)}) => "VQL_DRIFT_DETECTED"
  | RuntimeError({kind: PermissionDenied(_)}) => "VQL_PERMISSION_DENIED"
  | RuntimeError({kind: ResourceExhausted(_)}) => "VQL_RESOURCE_EXHAUSTED"
  | RuntimeError(_) => "VQL_RUNTIME_ERROR"
  | ModalityError(GraphError(_)) => "VQL_GRAPH_ERROR"
  | ModalityError(VectorError(_)) => "VQL_VECTOR_ERROR"
  | ModalityError(TensorError(_)) => "VQL_TENSOR_ERROR"
  | ModalityError(SemanticError(_)) => "VQL_SEMANTIC_ERROR"
  | ModalityError(DocumentError(_)) => "VQL_DOCUMENT_ERROR"
  | ModalityError(TemporalError(_)) => "VQL_TEMPORAL_ERROR"
  | FederationError(_) => "VQL_FEDERATION_ERROR"
  | MultipleErrors(_) => "VQL_MULTIPLE_ERRORS"
  }
}

let toJson = (err: vqlError): Js.Json.t => {
  Js.Dict.fromArray([
    ("error_code", Js.Json.string(getErrorCode(err))),
    ("message", Js.Json.string(format(err))),
    ("recoverable", Js.Json.boolean(isRecoverable(err))),
  ])->Js.Json.object_
}
