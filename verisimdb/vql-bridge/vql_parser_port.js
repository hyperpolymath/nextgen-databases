#!/usr/bin/env -S deno run --allow-read
// SPDX-License-Identifier: PMPL-1.0-or-later
// VQL Parser Port — stdin/stdout JSON bridge for Elixir
//
// Reads JSON messages (one per line) from stdin, parses VQL queries
// using the compiled ReScript VQLParser, and writes JSON results to stdout.
//
// Protocol: newline-delimited JSON
//   Request:  {"id": 1, "action": "parse", "query": "SELECT ..."}
//   Response: {"id": 1, "ok": {...ast...}} or {"id": 1, "error": "..."}

// Import compiled ReScript VQL parser and type checker.
// The compiled JS output will be at ../src/vql/*.res.mjs (ReScript compiler output).
let VQLParser;
let VQLTypeChecker;
let VQLBidir;

try {
  VQLParser = await import("../src/vql/VQLParser.res.mjs");
} catch (_e) {
  try {
    // Legacy .bs.js suffix (older ReScript versions)
    VQLParser = await import("../src/vql/VQLParser.bs.js");
  } catch (_e2) {
    VQLParser = null;
  }
}

try {
  VQLTypeChecker = await import("../src/vql/VQLTypeChecker.res.mjs");
} catch (_e) {
  try {
    VQLTypeChecker = await import("../src/vql/VQLTypeChecker.bs.js");
  } catch (_e2) {
    VQLTypeChecker = null;
  }
}

try {
  VQLBidir = await import("../src/vql/VQLBidir.res.mjs");
} catch (_e) {
  try {
    VQLBidir = await import("../src/vql/VQLBidir.bs.js");
  } catch (_e2) {
    VQLBidir = null;
  }
}

/**
 * Minimal VQL parser fallback (when compiled ReScript is unavailable).
 * Produces AST compatible with VQLParser.res types.
 */
function fallbackParse(query) {
  const tokens = query.trim().split(/\s+/);
  let pos = 0;

  function peek() { return tokens[pos] || null; }
  function advance() { return tokens[pos++] || null; }
  function expect(t) {
    const got = advance();
    if (got?.toUpperCase() !== t.toUpperCase()) {
      throw new Error(`Expected "${t}", got "${got}" at position ${pos}`);
    }
    return got;
  }

  // SELECT clause (extended: supports MODALITY.field projections and aggregates)
  expect("SELECT");
  const modalities = [];
  const projections = [];
  const aggregates = [];
  const MODALITY_NAMES = ["GRAPH","VECTOR","TENSOR","SEMANTIC","DOCUMENT","TEMPORAL","PROVENANCE","SPATIAL"];
  const AGG_FUNCS = ["COUNT","SUM","AVG","MIN","MAX"];

  while (peek() && peek().toUpperCase() !== "FROM") {
    const tok = peek()?.replace(/,/g, "");
    const tokUp = tok?.toUpperCase();

    // Aggregate: COUNT(*) or FUNC(MODALITY.field)
    if (AGG_FUNCS.includes(tokUp)) {
      const func = advance().replace(/,/g, "").toUpperCase();
      if (peek() === "(" || peek()?.startsWith("(")) {
        let inner = advance().replace(/[()]/g, "");
        if (!inner && peek()) inner = advance().replace(/[()]/g, "");
        // consume closing ) if separate token
        if (peek() === ")") advance();

        if (inner === "*") {
          aggregates.push({ TAG: "CountAll" });
        } else if (inner.includes(".")) {
          const [mod, field] = inner.split(".", 2);
          aggregates.push({
            TAG: "AggregateField",
            func: func.charAt(0) + func.slice(1).toLowerCase(),
            modality: mod.charAt(0) + mod.slice(1).toLowerCase(),
            field: field
          });
          const modName = mod.charAt(0) + mod.slice(1).toLowerCase();
          if (!modalities.includes(modName)) modalities.push(modName);
        }
      }
      continue;
    }

    // MODALITY.field projection
    if (tok?.includes(".")) {
      const [mod, field] = tok.split(".", 2);
      if (MODALITY_NAMES.includes(mod.toUpperCase())) {
        advance(); // consume the token
        projections.push({
          modality: mod.charAt(0).toUpperCase() + mod.slice(1).toLowerCase(),
          field: field
        });
        const modName = mod.charAt(0).toUpperCase() + mod.slice(1).toLowerCase();
        if (!modalities.includes(modName)) modalities.push(modName);
        continue;
      }
    }

    // Bare modality or wildcard
    advance();
    if (tokUp === "*") modalities.push("All");
    else if (MODALITY_NAMES.includes(tokUp)) {
      modalities.push(tokUp.charAt(0) + tokUp.slice(1).toLowerCase());
    }
  }

  // FROM clause
  expect("FROM");
  let source;
  const sourceType = advance()?.toUpperCase();
  if (sourceType === "HEXAD") {
    source = { TAG: "Hexad", _0: advance() };
  } else if (sourceType === "FEDERATION") {
    const pattern = advance();
    let driftPolicy = null;
    if (peek()?.toUpperCase() === "WITH") {
      advance(); // WITH
      expect("DRIFT");
      const policy = advance()?.toUpperCase();
      driftPolicy = policy;
    }
    source = { TAG: "Federation", _0: pattern, _1: driftPolicy };
  } else if (sourceType === "STORE") {
    source = { TAG: "Store", _0: advance() };
  } else {
    throw new Error(`Unknown source type: ${sourceType}`);
  }

  // WHERE clause (simplified)
  let whereClause = null;
  if (peek()?.toUpperCase() === "WHERE") {
    advance(); // WHERE
    const condTokens = [];
    while (peek() && !["PROOF","LIMIT","OFFSET"].includes(peek()?.toUpperCase())) {
      condTokens.push(advance());
    }
    whereClause = { TAG: "Raw", _0: condTokens.join(" ") };
  }

  // GROUP BY clause
  let groupBy = null;
  if (peek()?.toUpperCase() === "GROUP") {
    advance(); // GROUP
    expect("BY");
    groupBy = [];
    while (peek() && !["HAVING","PROOF","ORDER","LIMIT","OFFSET"].includes(peek()?.toUpperCase())) {
      const tok = advance().replace(/,/g, "");
      if (tok.includes(".")) {
        const [mod, field] = tok.split(".", 2);
        groupBy.push({
          modality: mod.charAt(0).toUpperCase() + mod.slice(1).toLowerCase(),
          field: field
        });
      }
    }
  }

  // HAVING clause
  let having = null;
  if (peek()?.toUpperCase() === "HAVING") {
    advance(); // HAVING
    const havingTokens = [];
    while (peek() && !["PROOF","ORDER","LIMIT","OFFSET"].includes(peek()?.toUpperCase())) {
      havingTokens.push(advance());
    }
    having = { TAG: "Raw", _0: havingTokens.join(" ") };
  }

  // PROOF clause (multi-proof: PROOF spec AND spec AND spec)
  let proof = null;
  if (peek()?.toUpperCase() === "PROOF") {
    advance(); // PROOF
    const proofSpecs = [];
    while (peek() && !["ORDER","LIMIT","OFFSET"].includes(peek()?.toUpperCase())) {
      const proofType = advance();
      const contractRaw = advance()?.replace(/[()]/g, "") || "";
      proofSpecs.push({ proofType, contractName: contractRaw });
      // Check for AND to chain multiple proofs
      if (peek()?.toUpperCase() === "AND") {
        advance(); // AND
      } else {
        break;
      }
    }
    proof = proofSpecs.length > 0 ? proofSpecs : null;
  }

  // ORDER BY clause
  let orderBy = null;
  if (peek()?.toUpperCase() === "ORDER") {
    advance(); // ORDER
    expect("BY");
    orderBy = [];
    while (peek() && !["LIMIT","OFFSET"].includes(peek()?.toUpperCase())) {
      const tok = advance().replace(/,/g, "");
      if (tok.includes(".")) {
        const [mod, field] = tok.split(".", 2);
        let direction = "Asc";
        if (peek()?.toUpperCase() === "ASC") { advance(); direction = "Asc"; }
        else if (peek()?.toUpperCase() === "DESC") { advance(); direction = "Desc"; }
        orderBy.push({
          field: {
            modality: mod.charAt(0).toUpperCase() + mod.slice(1).toLowerCase(),
            field: field
          },
          direction: direction
        });
      }
    }
  }

  // LIMIT
  let limit = null;
  if (peek()?.toUpperCase() === "LIMIT") {
    advance();
    limit = parseInt(advance(), 10);
  }

  // OFFSET
  let offset = null;
  if (peek()?.toUpperCase() === "OFFSET") {
    advance();
    offset = parseInt(advance(), 10);
  }

  return {
    modalities,
    projections: projections.length > 0 ? projections : null,
    aggregates: aggregates.length > 0 ? aggregates : null,
    source,
    where: whereClause,
    groupBy,
    having,
    proof,
    orderBy,
    limit,
    offset,
  };
}

/**
 * Minimal VQL mutation parser fallback (INSERT / UPDATE / DELETE).
 * Produces AST compatible with VQLParser.res mutation types.
 */
function fallbackParseMutation(input) {
  const tokens = input.trim().split(/\s+/);
  let pos = 0;

  function peek() { return tokens[pos] || null; }
  function advance() { return tokens[pos++] || null; }
  function expect(t) {
    const got = advance();
    if (got?.toUpperCase() !== t.toUpperCase()) {
      throw new Error(`Expected "${t}", got "${got}" at position ${pos}`);
    }
    return got;
  }

  const cmd = advance()?.toUpperCase();

  if (cmd === "INSERT") {
    expect("HEXAD");
    expect("WITH");

    const MODALITY_NAMES = ["GRAPH","VECTOR","TENSOR","SEMANTIC","DOCUMENT","TEMPORAL","PROVENANCE","SPATIAL"];
    const modalityData = [];

    while (peek() && MODALITY_NAMES.includes(peek()?.toUpperCase())) {
      const mod = advance().toUpperCase();
      // Collect everything in parens
      if (peek()?.startsWith("(")) {
        let raw = advance();
        // Collect until closing paren
        while (raw && !raw.endsWith(")")) {
          raw += " " + advance();
        }
        raw = raw.replace(/^\(/, "").replace(/\)$/, "");
        modalityData.push({ modality: mod, raw });
      }
      // Skip comma between modality data
      if (peek() === ",") advance();
    }

    // Optional PROOF
    let proof = null;
    if (peek()?.toUpperCase() === "PROOF") {
      advance();
      const proofSpecs = [];
      while (peek()) {
        const proofType = advance();
        const contractRaw = advance()?.replace(/[()]/g, "") || "";
        proofSpecs.push({ proofType, contractName: contractRaw });
        if (peek()?.toUpperCase() === "AND") { advance(); } else { break; }
      }
      proof = proofSpecs.length > 0 ? proofSpecs : null;
    }

    return { TAG: "Insert", modalities: modalityData, proof };

  } else if (cmd === "UPDATE") {
    expect("HEXAD");
    const hexadId = advance();
    expect("SET");

    const sets = [];
    while (peek() && peek()?.toUpperCase() !== "PROOF") {
      const field = advance()?.replace(/,/g, "");
      if (peek() === "=") {
        advance(); // =
        const value = advance()?.replace(/,/g, "");
        sets.push({ field, value });
      } else {
        break;
      }
    }

    let proof = null;
    if (peek()?.toUpperCase() === "PROOF") {
      advance();
      const proofSpecs = [];
      while (peek()) {
        const proofType = advance();
        const contractRaw = advance()?.replace(/[()]/g, "") || "";
        proofSpecs.push({ proofType, contractName: contractRaw });
        if (peek()?.toUpperCase() === "AND") { advance(); } else { break; }
      }
      proof = proofSpecs.length > 0 ? proofSpecs : null;
    }

    return { TAG: "Update", hexadId, sets, proof };

  } else if (cmd === "DELETE") {
    expect("HEXAD");
    const hexadId = advance();

    let proof = null;
    if (peek()?.toUpperCase() === "PROOF") {
      advance();
      const proofSpecs = [];
      while (peek()) {
        const proofType = advance();
        const contractRaw = advance()?.replace(/[()]/g, "") || "";
        proofSpecs.push({ proofType, contractName: contractRaw });
        if (peek()?.toUpperCase() === "AND") { advance(); } else { break; }
      }
      proof = proofSpecs.length > 0 ? proofSpecs : null;
    }

    return { TAG: "Delete", hexadId, proof };

  } else {
    throw new Error(`Expected INSERT, UPDATE, or DELETE, got "${cmd}"`);
  }
}

/**
 * Parse a VQL statement (query or mutation) using fallback parser.
 */
function fallbackParseStatement(input) {
  const trimmed = input.trim();
  const firstWord = trimmed.split(/\s+/)[0]?.toUpperCase();

  if (["INSERT", "UPDATE", "DELETE"].includes(firstWord)) {
    return { TAG: "Mutation", _0: fallbackParseMutation(trimmed) };
  } else {
    return { TAG: "Query", _0: fallbackParse(trimmed) };
  }
}

/**
 * Parse a VQL query using the ReScript parser or fallback.
 */
function parseQuery(query, action) {
  if (VQLParser) {
    let result;
    switch (action) {
      case "parse_slipstream":
        result = VQLParser.parseSlipstream(query);
        break;
      case "parse_dependent":
        result = VQLParser.parseDependentType(query);
        break;
      case "parse_mutation":
        result = VQLParser.parseMutation(query);
        break;
      case "parse_statement":
        result = VQLParser.parseStatement(query);
        break;
      default:
        result = VQLParser.parse(query);
    }
    // ReScript Result type: { TAG: "Ok", _0: value } or { TAG: "Error", _0: error }
    if (result.TAG === "Ok") return { ok: result._0 };
    return { error: result._0.message || JSON.stringify(result._0) };
  }

  // Fallback parser
  switch (action) {
    case "parse_mutation":
      return { ok: fallbackParseMutation(query) };
    case "parse_statement":
      return { ok: fallbackParseStatement(query) };
    default:
      return { ok: fallbackParse(query) };
  }
}

// ---------------------------------------------------------------------------
// Type checking: invoke ReScript VQLBidir or extract obligations from AST
// ---------------------------------------------------------------------------

/**
 * Type-check a parsed VQL-DT AST.
 *
 * If compiled ReScript is available, delegates to VQLBidir.synthesizeQuery
 * for full bidirectional type inference. Otherwise, extracts proof obligations
 * directly from the AST's proof clause — a sound but less precise fallback.
 *
 * @param {object} ast - Parsed VQL query AST
 * @returns {{ ok: object } | { error: string }} - Type info or error
 */
function typecheckAST(ast) {
  // Try the full ReScript type checker first
  if (VQLBidir) {
    try {
      const result = VQLBidir.synthesizeQuery(ast);
      if (result.TAG === "Ok") {
        return { ok: result._0 };
      }
      return { error: result._0?.message || JSON.stringify(result._0) };
    } catch (e) {
      // If VQLBidir crashes, fall through to the lightweight fallback
    }
  }

  if (VQLTypeChecker) {
    try {
      const result = VQLTypeChecker.checkQuery(ast);
      if (result.TAG === "Ok") {
        return { ok: result._0 };
      }
      return { error: result._0?.message || JSON.stringify(result._0) };
    } catch (e) {
      // Fall through to lightweight fallback
    }
  }

  // Lightweight fallback: extract proof obligations from the AST directly.
  // This does NOT perform type inference — it only parses the PROOF clause
  // into a structured list of obligations with composition strategy.
  return { ok: fallbackTypecheck(ast) };
}

/**
 * Fallback type checking: extract proof obligations from an AST's proof clause.
 *
 * Returns a structure matching what VQLBidir.synthesizeQuery would produce:
 * { proof_obligations, composition_strategy, inferred_types }
 */
function fallbackTypecheck(ast) {
  const proofSpecs = ast.proof || ast.proofSpecs || null;
  const obligations = [];
  let compositionStrategy = "conjunction";

  if (Array.isArray(proofSpecs)) {
    for (const spec of proofSpecs) {
      const proofType = (spec.proofType || spec.TAG || "unknown").toUpperCase();
      const contractName = spec.contractName || spec.contract || spec._0 || null;

      // Map proof types to obligation records
      const PROOF_TIMES = {
        "EXISTENCE": 50, "CITATION": 100, "ACCESS": 150,
        "INTEGRITY": 200, "PROVENANCE": 300, "CUSTOM": 500,
        "ZKP": 400, "PROVEN": 350, "SANCTIFY": 200
      };

      obligations.push({
        type: proofType.toLowerCase(),
        contract: contractName,
        estimated_time_ms: PROOF_TIMES[proofType] || 200,
        privacy_level: spec.privacy_level || "public"
      });
    }

    // Multiple obligations default to conjunction (all must pass)
    compositionStrategy = obligations.length > 1 ? "conjunction" : "independent";
  } else if (proofSpecs && typeof proofSpecs === "object" && proofSpecs.raw) {
    // Raw proof string from built-in parser: "EXISTENCE(abc-123)"
    const raw = proofSpecs.raw;
    const matches = raw.matchAll(/(\w+)\(([^)]*)\)/g);
    for (const match of matches) {
      obligations.push({
        type: match[1].toLowerCase(),
        contract: match[2] || null,
        estimated_time_ms: 200,
        privacy_level: "public"
      });
    }
    compositionStrategy = obligations.length > 1 ? "conjunction" : "independent";
  }

  // Extract modality information for inferred_types
  const modalities = ast.modalities || [];
  const inferredTypes = {};
  for (const mod of modalities) {
    const modName = typeof mod === "string" ? mod.toLowerCase() : String(mod);
    inferredTypes[modName] = { _type: "modality_data" };
  }

  return {
    proof_obligations: obligations,
    composition_strategy: compositionStrategy,
    inferred_types: inferredTypes
  };
}

// ---------------------------------------------------------------------------
// Main loop: read lines from stdin, process, write to stdout
// ---------------------------------------------------------------------------

const decoder = new TextDecoder();
const encoder = new TextEncoder();

// Deno stdin reading
const buf = new Uint8Array(1_048_576);
let buffer = "";

async function main() {
  const stdin = Deno.stdin;
  const stdout = Deno.stdout;

  while (true) {
    const n = await stdin.read(buf);
    if (n === null) break; // EOF

    buffer += decoder.decode(buf.subarray(0, n));

    // Process complete lines
    let newlineIdx;
    while ((newlineIdx = buffer.indexOf("\n")) !== -1) {
      const line = buffer.slice(0, newlineIdx).trim();
      buffer = buffer.slice(newlineIdx + 1);

      if (!line) continue;

      try {
        const request = JSON.parse(line);
        const { id, action, query, ast } = request;

        try {
          let result;
          if (action === "typecheck") {
            // Type checking receives an AST (not a query string)
            result = typecheckAST(ast || query);
          } else {
            result = parseQuery(query, action);
          }
          const response = JSON.stringify({ id, ...result }) + "\n";
          await stdout.write(encoder.encode(response));
        } catch (e) {
          const response = JSON.stringify({ id, error: e.message }) + "\n";
          await stdout.write(encoder.encode(response));
        }
      } catch (e) {
        // Malformed JSON — skip
        const response = JSON.stringify({ id: 0, error: `Invalid JSON: ${e.message}` }) + "\n";
        await stdout.write(encoder.encode(response));
      }
    }
  }
}

main().catch(console.error);
