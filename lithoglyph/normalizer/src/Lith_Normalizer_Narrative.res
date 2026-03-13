// SPDX-License-Identifier: PMPL-1.0-or-later
// Form.Normalizer - Narrative Template System
//
// Generates human-readable explanations for normalization operations.
// Part of Lith's "database where the database is part of the story" philosophy.

// ============================================================
// Core Types
// ============================================================

type attribute = string
type confidence = float

type functionalDependency = {
  determinant: array<attribute>,
  dependent: array<attribute>,
  confidence: confidence,
  discoveredAt: option<int>,
  sampleSize: option<int>,
}

type violationType =
  | PartialDependency
  | TransitiveDependency
  | NonSuperkeyDeterminant
  | MultiValuedDependency

type normalFormViolation = {
  fd: functionalDependency,
  violationType: violationType,
  explanation: string,
}

type normalForm =
  | FirstNF
  | SecondNF
  | ThirdNF
  | BCNF
  | FourthNF
  | FifthNF

type normalizationProposal = {
  sourceSchema: array<attribute>,
  targetSchemas: array<array<attribute>>,
  transformation: string,
  inverse: string,
  equivalenceProof: string,
}

type denormalizationProposal = {
  sourceSchemas: array<array<attribute>>,
  targetSchema: array<attribute>,
  joinAttributes: array<attribute>,
  performanceRationale: string,
}

type migrationPhase =
  | Announce
  | Shadow
  | Commit

type migrationState = {
  phase: migrationPhase,
  affectedQueries: int,
  rewriteRules: int,
  compatViews: int,
  journalEntry: int,
}

type discoveryResult = {
  collection: string,
  exactFDs: array<functionalDependency>,
  probableFDs: array<functionalDependency>,
  dataWarnings: array<functionalDependency>,
  sampleRows: int,
  sampleAttributes: int,
}

// ============================================================
// Template Configuration
// ============================================================

type verbosity =
  | Minimal
  | Standard
  | Detailed
  | Debug

type audience =
  | Developer
  | DBA
  | BusinessAnalyst
  | Agent

type templateConfig = {
  verbosity: verbosity,
  audience: audience,
  includeProofs: bool,
  includeMetrics: bool,
  maxExamples: int,
}

let defaultConfig: templateConfig = {
  verbosity: Standard,
  audience: Developer,
  includeProofs: false,
  includeMetrics: true,
  maxExamples: 3,
}

// ============================================================
// Helper Functions
// ============================================================

let joinAttributes = (attrs: array<attribute>): string => {
  switch attrs->Array.length {
  | 0 => "(empty)"
  | 1 => attrs[0]->Option.getOr("")
  | _ => "{" ++ attrs->Array.join(", ") ++ "}"
  }
}

let confidenceLabel = (conf: confidence): string => {
  if conf >= 0.99 {
    "EXACT"
  } else if conf >= 0.95 {
    "PROBABLE"
  } else if conf >= 0.80 {
    "WEAK"
  } else {
    "DATA QUALITY WARNING"
  }
}

let confidenceEmoji = (conf: confidence): string => {
  if conf >= 0.99 {
    ""
  } else if conf >= 0.95 {
    ""
  } else {
    ""
  }
}

let normalFormName = (nf: normalForm): string => {
  switch nf {
  | FirstNF => "First Normal Form (1NF)"
  | SecondNF => "Second Normal Form (2NF)"
  | ThirdNF => "Third Normal Form (3NF)"
  | BCNF => "Boyce-Codd Normal Form (BCNF)"
  | FourthNF => "Fourth Normal Form (4NF)"
  | FifthNF => "Fifth Normal Form (5NF)"
  }
}

let violationTypeName = (vt: violationType): string => {
  switch vt {
  | PartialDependency => "Partial Dependency"
  | TransitiveDependency => "Transitive Dependency"
  | NonSuperkeyDeterminant => "Non-Superkey Determinant"
  | MultiValuedDependency => "Multi-Valued Dependency"
  }
}

let phaseName = (phase: migrationPhase): string => {
  switch phase {
  | Announce => "ANNOUNCE"
  | Shadow => "SHADOW"
  | Commit => "COMMIT"
  }
}

// ============================================================
// FD Narrative Templates
// ============================================================

let fdNarrativeMinimal = (fd: functionalDependency): string => {
  let det = fd.determinant->joinAttributes
  let dep = fd.dependent->joinAttributes
  `${det} -> ${dep}`
}

let fdNarrativeStandard = (fd: functionalDependency): string => {
  let det = fd.determinant->joinAttributes
  let dep = fd.dependent->joinAttributes
  let confLabel = fd.confidence->confidenceLabel

  if fd.confidence >= 0.99 {
    `${det} uniquely determines ${dep}`
  } else {
    `${det} likely determines ${dep} [${confLabel}: ${(fd.confidence *. 100.0)->Float.toFixed(~digits=1)}%]`
  }
}

let fdNarrativeDetailed = (fd: functionalDependency): string => {
  let det = fd.determinant->joinAttributes
  let dep = fd.dependent->joinAttributes
  let confLabel = fd.confidence->confidenceLabel

  let base = `Functional Dependency: ${det} -> ${dep}\n`
  let confidence = `  Confidence: ${(fd.confidence *. 100.0)->Float.toFixed(~digits=2)}% (${confLabel})\n`

  let discovery = switch fd.discoveredAt {
  | Some(seq) => `  Discovered at journal entry: #${seq->Int.toString}\n`
  | None => ""
  }

  let sample = switch fd.sampleSize {
  | Some(n) => `  Sample size: ${n->Int.toString} records\n`
  | None => ""
  }

  let interpretation = if fd.confidence >= 0.99 {
    `  Interpretation: Knowing ${det} always uniquely identifies ${dep}.\n`
  } else if fd.confidence >= 0.95 {
    `  Interpretation: ${det} strongly predicts ${dep}, but there may be exceptions.\n` ++
    `  Recommendation: Review outliers before treating as exact FD.\n`
  } else {
    `  Interpretation: Weak correlation between ${det} and ${dep}.\n` ++
    `  Recommendation: Investigate data quality issues.\n`
  }

  base ++ confidence ++ discovery ++ sample ++ interpretation
}

let fdNarrative = (fd: functionalDependency, config: templateConfig): string => {
  switch config.verbosity {
  | Minimal => fd->fdNarrativeMinimal
  | Standard => fd->fdNarrativeStandard
  | Detailed | Debug => fd->fdNarrativeDetailed
  }
}

// ============================================================
// Violation Narrative Templates
// ============================================================

let violationNarrativeStandard = (v: normalFormViolation): string => {
  let vtype = v.violationType->violationTypeName
  let det = v.fd.determinant->joinAttributes
  let dep = v.fd.dependent->joinAttributes

  switch v.violationType {
  | PartialDependency =>
    `2NF VIOLATION (${vtype}): ${det} is a partial key that determines non-prime attribute(s) ${dep}`
  | TransitiveDependency =>
    `3NF VIOLATION (${vtype}): Non-superkey ${det} determines non-prime ${dep}`
  | NonSuperkeyDeterminant =>
    `BCNF VIOLATION (${vtype}): ${det} is not a superkey but determines ${dep}`
  | MultiValuedDependency =>
    `4NF VIOLATION (${vtype}): Multi-valued dependency ${det} ->> ${dep}`
  }
}

let violationNarrativeDetailed = (v: normalFormViolation): string => {
  let base = v->violationNarrativeStandard ++ "\n"

  let explanation = `  Explanation: ${v.explanation}\n`

  let remedy = switch v.violationType {
  | PartialDependency =>
    `  Remedy: Decompose by extracting ${v.fd.determinant->joinAttributes} and ${v.fd.dependent->joinAttributes} into separate table.\n`
  | TransitiveDependency =>
    `  Remedy: Create separate table with ${v.fd.determinant->joinAttributes} as key determining ${v.fd.dependent->joinAttributes}.\n`
  | NonSuperkeyDeterminant =>
    `  Remedy: Decompose into (${v.fd.determinant->joinAttributes} ∪ ${v.fd.dependent->joinAttributes}) and (original - ${v.fd.dependent->joinAttributes}).\n`
  | MultiValuedDependency =>
    `  Remedy: Create separate table for the multi-valued relationship.\n`
  }

  base ++ explanation ++ remedy
}

let violationNarrative = (v: normalFormViolation, config: templateConfig): string => {
  switch config.verbosity {
  | Minimal | Standard => v->violationNarrativeStandard
  | Detailed | Debug => v->violationNarrativeDetailed
  }
}

// ============================================================
// Discovery Result Narrative
// ============================================================

let discoveryNarrative = (result: discoveryResult, config: templateConfig): string => {
  let header = `FUNCTIONAL DEPENDENCY DISCOVERY REPORT\n` ++
               `${"=".repeat(60)}\n\n` ++
               `Collection: ${result.collection}\n\n`

  let metrics = if config.includeMetrics {
    `Sample Information:\n` ++
    `  Records analyzed: ${result.sampleRows->Int.toString}\n` ++
    `  Attributes examined: ${result.sampleAttributes->Int.toString}\n\n`
  } else {
    ""
  }

  let exactSection = if result.exactFDs->Array.length > 0 {
    `EXACT FUNCTIONAL DEPENDENCIES (confidence >= 99%):\n` ++
    result.exactFDs
      ->Array.slice(~start=0, ~end=config.maxExamples)
      ->Array.map(fd => `  - ${fd->fdNarrative(config)}`)
      ->Array.join("\n") ++
    (if result.exactFDs->Array.length > config.maxExamples {
      `\n  ... and ${(result.exactFDs->Array.length - config.maxExamples)->Int.toString} more\n`
    } else {
      "\n"
    }) ++ "\n"
  } else {
    `EXACT FUNCTIONAL DEPENDENCIES: (none discovered)\n\n`
  }

  let probableSection = if result.probableFDs->Array.length > 0 {
    `PROBABLE FUNCTIONAL DEPENDENCIES (95% <= confidence < 99%):\n` ++
    `These require confirmation before use in schema design.\n` ++
    result.probableFDs
      ->Array.slice(~start=0, ~end=config.maxExamples)
      ->Array.map(fd => `  - ${fd->fdNarrative(config)}`)
      ->Array.join("\n") ++
    (if result.probableFDs->Array.length > config.maxExamples {
      `\n  ... and ${(result.probableFDs->Array.length - config.maxExamples)->Int.toString} more\n`
    } else {
      "\n"
    }) ++ "\n"
  } else {
    ""
  }

  let warningSection = if result.dataWarnings->Array.length > 0 {
    `DATA QUALITY WARNINGS (confidence < 95%):\n` ++
    `These indicate potential data quality issues.\n` ++
    result.dataWarnings
      ->Array.slice(~start=0, ~end=config.maxExamples)
      ->Array.map(fd => `  - ${fd->fdNarrative(config)}`)
      ->Array.join("\n") ++
    (if result.dataWarnings->Array.length > config.maxExamples {
      `\n  ... and ${(result.dataWarnings->Array.length - config.maxExamples)->Int.toString} more\n`
    } else {
      "\n"
    }) ++ "\n"
  } else {
    ""
  }

  header ++ metrics ++ exactSection ++ probableSection ++ warningSection
}

// ============================================================
// Normalization Proposal Narrative
// ============================================================

let normalizationNarrative = (proposal: normalizationProposal, targetNF: normalForm, config: templateConfig): string => {
  let header = `NORMALIZATION PROPOSAL\n` ++
               `${"=".repeat(60)}\n\n` ++
               `Target: ${targetNF->normalFormName}\n\n`

  let sourceDesc = `Source Schema:\n` ++
                   `  ${proposal.sourceSchema->joinAttributes}\n\n`

  let targetDesc = `Proposed Decomposition:\n` ++
                   proposal.targetSchemas
                     ->Array.mapWithIndex((schema, i) => `  Table ${(i + 1)->Int.toString}: ${schema->joinAttributes}`)
                     ->Array.join("\n") ++
                   "\n\n"

  let transformation = `Transformation:\n` ++
                       `  Forward: ${proposal.transformation}\n` ++
                       `  Inverse: ${proposal.inverse}\n\n`

  let proof = if config.includeProofs {
    `Equivalence Proof:\n` ++
    `  ${proposal.equivalenceProof}\n\n`
  } else {
    ""
  }

  let narrative = switch config.audience {
  | Developer | DBA =>
    `Technical Summary:\n` ++
    `  This decomposition eliminates redundancy while preserving all data.\n` ++
    `  The original relation can be reconstructed via natural join on common attributes.\n`
  | BusinessAnalyst =>
    `Business Impact:\n` ++
    `  This change improves data consistency by ensuring each fact is stored once.\n` ++
    `  Query patterns may need adjustment, but data integrity will be stronger.\n`
  | Agent =>
    `Agent Instructions:\n` ++
    `  Execute: APPLY NORMALIZATION <proposal-id> WITH ROLLBACK POINT "pre-normalization"\n` ++
    `  Verify: Check dependent queries for compatibility\n`
  }

  header ++ sourceDesc ++ targetDesc ++ transformation ++ proof ++ narrative
}

// ============================================================
// Denormalization Proposal Narrative
// ============================================================

let denormalizationNarrative = (proposal: denormalizationProposal, config: templateConfig): string => {
  let header = `INTENTIONAL DENORMALIZATION PROPOSAL\n` ++
               `${"=".repeat(60)}\n\n`

  let warning = `NOTE: This is an INTENTIONAL denormalization for performance reasons.\n` ++
                `      The operation is fully reversible.\n\n`

  let sourceDesc = `Source Schemas (${proposal.sourceSchemas->Array.length->Int.toString} tables):\n` ++
                   proposal.sourceSchemas
                     ->Array.mapWithIndex((schema, i) => `  ${(i + 1)->Int.toString}. ${schema->joinAttributes}`)
                     ->Array.join("\n") ++
                   "\n\n"

  let targetDesc = `Merged Schema:\n` ++
                   `  ${proposal.targetSchema->joinAttributes}\n\n`

  let joinDesc = `Join Attributes:\n` ++
                 `  ${proposal.joinAttributes->joinAttributes}\n\n`

  let rationale = `Performance Rationale:\n` ++
                  `  ${proposal.performanceRationale}\n\n`

  let tradeoffs = `Trade-offs:\n` ++
                  `  + Faster reads: Single table scan instead of joins\n` ++
                  `  + Simpler queries: No JOIN clauses needed\n` ++
                  `  - More storage: Redundant data stored\n` ++
                  `  - Update anomalies: Must update multiple rows for changes\n` ++
                  `  - Write overhead: Triggers/logic needed to maintain consistency\n\n`

  let reversal = `Reversal:\n` ++
                 `  Execute: SPLIT ${proposal.targetSchema->joinAttributes} ON ${proposal.joinAttributes->joinAttributes}\n` ++
                 `  This recreates the original normalized structure.\n`

  header ++ warning ++ sourceDesc ++ targetDesc ++ joinDesc ++ rationale ++ tradeoffs ++ reversal
}

// ============================================================
// Migration State Narrative
// ============================================================

let migrationNarrative = (state: migrationState, config: templateConfig): string => {
  let phaseEmoji = switch state.phase {
  | Announce => ""
  | Shadow => ""
  | Commit => ""
  }

  let header = `MIGRATION STATUS: ${phaseEmoji} ${state.phase->phaseName}\n` ++
               `${"=".repeat(60)}\n\n` ++
               `Journal Entry: #${state.journalEntry->Int.toString}\n\n`

  let phaseDesc = switch state.phase {
  | Announce =>
    `Phase: ANNOUNCE (Warning Period)\n` ++
    `  All affected queries have been identified.\n` ++
    `  No schema changes have been applied yet.\n` ++
    `  Safe to abort without data loss.\n\n`
  | Shadow =>
    `Phase: SHADOW (Compatibility Layer Active)\n` ++
    `  Both old and new schemas exist simultaneously.\n` ++
    `  Queries are being automatically rewritten.\n` ++
    `  Compatibility views provide backward compatibility.\n` ++
    `  Still safe to abort (old schema intact).\n\n`
  | Commit =>
    `Phase: COMMIT (Migration Complete)\n` ++
    `  Old schema has been removed.\n` ++
    `  Query rewrites are now permanent.\n` ++
    `  Rollback requires explicit restore operation.\n\n`
  }

  let metrics = if config.includeMetrics {
    `Metrics:\n` ++
    `  Affected queries: ${state.affectedQueries->Int.toString}\n` ++
    `  Rewrite rules: ${state.rewriteRules->Int.toString}\n` ++
    `  Compatibility views: ${state.compatViews->Int.toString}\n\n`
  } else {
    ""
  }

  let nextSteps = switch state.phase {
  | Announce =>
    `Next Steps:\n` ++
    `  1. Review affected queries list\n` ++
    `  2. Test query rewrites in staging\n` ++
    `  3. Execute: ADVANCE MIGRATION TO SHADOW\n` ++
    `  Or abort: ABORT MIGRATION #${state.journalEntry->Int.toString}\n`
  | Shadow =>
    `Next Steps:\n` ++
    `  1. Monitor query performance during shadow period\n` ++
    `  2. Verify no application errors\n` ++
    `  3. Execute: ADVANCE MIGRATION TO COMMIT\n` ++
    `  Or abort: ABORT MIGRATION #${state.journalEntry->Int.toString}\n`
  | Commit =>
    `Migration complete. Old structure is no longer accessible.\n` ++
    `To restore: CREATE ROLLBACK POINT and restore from backup.\n`
  }

  header ++ phaseDesc ++ metrics ++ nextSteps
}

// ============================================================
// Public API
// ============================================================

let narrateFD = fdNarrative
let narrateViolation = violationNarrative
let narrateDiscovery = discoveryNarrative
let narrateNormalization = normalizationNarrative
let narrateDenormalization = denormalizationNarrative
let narrateMigration = migrationNarrative
