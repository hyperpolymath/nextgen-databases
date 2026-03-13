// SPDX-License-Identifier: PMPL-1.0-or-later
// Lith Studio - Proof Assistant Component (Phase 4)

// Proof obligation types
module ProofObligation = {
  type status =
    | Pending
    | Proved
    | Failed(string)
    | NeedsHelp

  type t = {
    id: string,
    description: string,
    formalStatement: string,
    status: status,
    suggestedTactic: option<string>,
    explanation: string,
  }
}

// Constraint violation explanation
module ConstraintViolation = {
  type severity = Error | Warning | Info

  type suggestedFix = {
    description: string,
    code: string,
    confidence: int,
  }

  type t = {
    field: string,
    constraint_: string,
    value: string,
    severity: severity,
    explanation: string,
    suggestedFixes: array<suggestedFix>,
  }
}

// Proof tactic
module Tactic = {
  type t = {
    name: string,
    description: string,
    applicableTo: array<string>,
  }

  let commonTactics = [
    {
      name: "omega",
      description: "Solves linear arithmetic goals automatically",
      applicableTo: ["BoundedNat", "number constraints", "inequalities"],
    },
    {
      name: "simp",
      description: "Simplifies using rewrite rules",
      applicableTo: ["equality", "definitions", "simple expressions"],
    },
    {
      name: "decide",
      description: "Decides decidable propositions",
      applicableTo: ["boolean expressions", "finite checks"],
    },
    {
      name: "rfl",
      description: "Proves by reflexivity (things equal to themselves)",
      applicableTo: ["equality", "identity"],
    },
    {
      name: "exact",
      description: "Provides the exact proof term",
      applicableTo: ["any goal with known proof"],
    },
  ]
}

// Proof explanation component
module ProofExplanation = {
  @react.component
  let make = (~obligation: ProofObligation.t) => {
    let statusClass = switch obligation.status {
    | ProofObligation.Proved => "status-proved"
    | ProofObligation.Failed(_) => "status-failed"
    | ProofObligation.NeedsHelp => "status-help"
    | ProofObligation.Pending => "status-pending"
    }

    let statusText = switch obligation.status {
    | ProofObligation.Proved => "\u2713 Proved"
    | ProofObligation.Failed(reason) => "\u2717 Failed: " ++ reason
    | ProofObligation.NeedsHelp => "? Needs your input"
    | ProofObligation.Pending => "... Pending"
    }

    <div className={`proof-obligation ${statusClass}`}>
      <div className="proof-header">
        <span className="proof-id"> {React.string(obligation.id)} </span>
        <span className="proof-status"> {React.string(statusText)} </span>
      </div>

      <div className="proof-description">
        <h4> {React.string("What we need to prove:")} </h4>
        <p> {React.string(obligation.description)} </p>
      </div>

      <div className="proof-formal">
        <h4> {React.string("Formal statement (Lean 4):")} </h4>
        <pre className="code-block"> {React.string(obligation.formalStatement)} </pre>
      </div>

      <div className="proof-explanation">
        <h4> {React.string("In plain English:")} </h4>
        <p> {React.string(obligation.explanation)} </p>
      </div>

      {switch obligation.suggestedTactic {
      | Some(tactic) =>
        <div className="suggested-tactic">
          <h4> {React.string("Suggested approach:")} </h4>
          <code> {React.string(tactic)} </code>
          <button className="btn btn-primary btn-small">
            {React.string("Apply This")}
          </button>
        </div>
      | None => React.null
      }}
    </div>
  }
}

// Violation explanation component
module ViolationExplanation = {
  @react.component
  let make = (~violation: ConstraintViolation.t, ~onApplyFix: string => unit) => {
    let severityClass = switch violation.severity {
    | ConstraintViolation.Error => "severity-error"
    | ConstraintViolation.Warning => "severity-warning"
    | ConstraintViolation.Info => "severity-info"
    }

    <div className={`constraint-violation ${severityClass}`}>
      <div className="violation-header">
        <span className="violation-field"> {React.string(violation.field)} </span>
        <span className="violation-severity">
          {React.string(
            switch violation.severity {
            | ConstraintViolation.Error => "Error"
            | ConstraintViolation.Warning => "Warning"
            | ConstraintViolation.Info => "Info"
            },
          )}
        </span>
      </div>

      <div className="violation-details">
        <p>
          <strong> {React.string("Constraint: ")} </strong>
          {React.string(violation.constraint_)}
        </p>
        <p>
          <strong> {React.string("Your value: ")} </strong>
          <code> {React.string(violation.value)} </code>
        </p>
      </div>

      <div className="violation-explanation">
        <h4> {React.string("Why this failed:")} </h4>
        <p> {React.string(violation.explanation)} </p>
      </div>

      {if Array.length(violation.suggestedFixes) > 0 {
        <div className="suggested-fixes">
          <h4> {React.string("Suggested fixes:")} </h4>
          {violation.suggestedFixes
          ->Array.mapWithIndex((fix, i) =>
            <div key={Int.toString(i)} className="suggested-fix">
              <p> {React.string(fix.description)} </p>
              <div className="fix-code">
                <code> {React.string(fix.code)} </code>
                <span className="fix-confidence">
                  {React.string(`${Int.toString(fix.confidence)}% confidence`)}
                </span>
              </div>
              <button
                className="btn btn-secondary btn-small"
                onClick={_ => onApplyFix(fix.code)}>
                {React.string("Apply Fix")}
              </button>
            </div>
          )
          ->React.array}
        </div>
      } else {
        React.null
      }}
    </div>
  }
}

// Tactic reference
module TacticReference = {
  @react.component
  let make = () => {
    <div className="tactic-reference">
      <h3> {React.string("Common Proof Tactics")} </h3>
      <p className="hint">
        {React.string("These are the building blocks for proving constraints in FBQLdt.")}
      </p>
      <div className="tactics-list">
        {Tactic.commonTactics
        ->Array.map(tactic =>
          <div key={tactic.name} className="tactic-item">
            <code className="tactic-name"> {React.string(tactic.name)} </code>
            <p className="tactic-desc"> {React.string(tactic.description)} </p>
            <div className="tactic-applies">
              <span> {React.string("Use for: ")} </span>
              {tactic.applicableTo
              ->Array.map(a => <span key={a} className="tag"> {React.string(a)} </span>)
              ->React.array}
            </div>
          </div>
        )
        ->React.array}
      </div>
    </div>
  }
}

// Main component
@react.component
let make = () => {
  // Example proof obligations for demo
  let (obligations, _setObligations) = React.useState(() => [
    {
      ProofObligation.id: "score_bounds",
      description: "Prove that the PROMPT score is between 0 and 100",
      formalStatement: "theorem score_valid : 0 <= prompt_score && prompt_score <= 100",
      status: ProofObligation.Proved,
      suggestedTactic: Some("omega"),
      explanation: "This score must be a percentage. The 'omega' tactic can automatically verify arithmetic bounds like this.",
    },
    {
      ProofObligation.id: "rationale_nonempty",
      description: "Prove that the rationale field is not empty",
      formalStatement: "theorem rationale_valid : rationale.length > 0",
      status: ProofObligation.NeedsHelp,
      suggestedTactic: Some("simp [String.length]"),
      explanation: "For audit compliance, every piece of evidence needs a rationale explaining why it was added.",
    },
  ])

  let (violations, _setViolations) = React.useState(() => [
    {
      ConstraintViolation.field: "prompt_score",
      constraint_: "BoundedNat 0 100",
      value: "150",
      severity: ConstraintViolation.Error,
      explanation: "The value 150 exceeds the maximum allowed value of 100. PROMPT scores represent percentages and must be between 0 and 100.",
      suggestedFixes: [
        {
          ConstraintViolation.description: "Cap at maximum value",
          code: "prompt_score = 100",
          confidence: 90,
        },
        {
          ConstraintViolation.description: "Normalize to percentage",
          code: "prompt_score = 150 * 100 / 200  -- If 150 was out of 200",
          confidence: 60,
        },
      ],
    },
  ])

  let (activeTab, setActiveTab) = React.useState(() => "obligations")

  let handleApplyFix = (code: string) => {
    Console.log2("Applying fix:", code)
    // TODO: Call Tauri command to apply fix
  }

  <section className="proof-assistant">
    <h2> {React.string("Proof Assistant")} </h2>
    <p className="section-hint">
      {React.string(
        "FBQLdt uses dependent types to verify constraints at compile time. This assistant helps you understand and resolve proof obligations.",
      )}
    </p>

    <div className="tabs">
      <button
        className={`tab ${activeTab == "obligations" ? "active" : ""}`}
        onClick={_ => setActiveTab(_ => "obligations")}>
        {React.string("Proof Obligations")}
      </button>
      <button
        className={`tab ${activeTab == "violations" ? "active" : ""}`}
        onClick={_ => setActiveTab(_ => "violations")}>
        {React.string("Constraint Violations")}
      </button>
      <button
        className={`tab ${activeTab == "tactics" ? "active" : ""}`}
        onClick={_ => setActiveTab(_ => "tactics")}>
        {React.string("Tactic Reference")}
      </button>
    </div>

    <div className="tab-content">
      {switch activeTab {
      | "obligations" =>
        <div className="obligations-list">
          {if Array.length(obligations) == 0 {
            <div className="empty-state">
              <p> {React.string("No proof obligations. Your schema is fully verified!")} </p>
            </div>
          } else {
            obligations
            ->Array.map(o => <ProofExplanation key={o.id} obligation={o} />)
            ->React.array
          }}
        </div>
      | "violations" =>
        <div className="violations-list">
          {if Array.length(violations) == 0 {
            <div className="empty-state">
              <p> {React.string("No constraint violations. All data passes validation!")} </p>
            </div>
          } else {
            violations
            ->Array.mapWithIndex((v, i) =>
              <ViolationExplanation
                key={Int.toString(i)} violation={v} onApplyFix={handleApplyFix}
              />
            )
            ->React.array
          }}
        </div>
      | "tactics" => <TacticReference />
      | _ => React.null
      }}
    </div>
  </section>
}
