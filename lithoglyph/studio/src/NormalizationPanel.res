// SPDX-License-Identifier: PMPL-1.0-or-later
// Lith Studio - Schema Normalization Panel (Phase 5)

open Types

// Functional dependency
module FunctionalDependency = {
  type confidence = float

  type t = {
    determinant: array<string>,
    dependent: array<string>,
    confidence: confidence,
    discovered: bool, // true if discovered from data, false if declared
  }

  let toString = (fd: t): string => {
    let det = fd.determinant->Array.join(", ")
    let dep = fd.dependent->Array.join(", ")
    `{${det}} -> {${dep}}`
  }
}

// Normal forms
module NormalForm = {
  type t =
    | First
    | Second
    | Third
    | BCNF
    | Fourth
    | Fifth

  let toString = (nf: t): string =>
    switch nf {
    | First => "1NF"
    | Second => "2NF"
    | Third => "3NF"
    | BCNF => "BCNF"
    | Fourth => "4NF"
    | Fifth => "5NF"
    }

  let toFullName = (nf: t): string =>
    switch nf {
    | First => "First Normal Form"
    | Second => "Second Normal Form"
    | Third => "Third Normal Form"
    | BCNF => "Boyce-Codd Normal Form"
    | Fourth => "Fourth Normal Form"
    | Fifth => "Fifth Normal Form"
    }

  let description = (nf: t): string =>
    switch nf {
    | First => "All attributes contain only atomic values (no repeating groups)"
    | Second => "1NF + no partial dependencies (non-key attributes depend on entire key)"
    | Third => "2NF + no transitive dependencies (non-key attributes depend only on the key)"
    | BCNF => "Every determinant is a superkey"
    | Fourth => "BCNF + no multi-valued dependencies"
    | Fifth => "4NF + no join dependencies"
    }

  let all = [First, Second, Third, BCNF, Fourth, Fifth]
}

// Normalization proposal
module NormalizationProposal = {
  type tableChange = {
    name: string,
    fields: array<string>,
    reason: string,
  }

  type t = {
    id: string,
    currentNF: NormalForm.t,
    targetNF: NormalForm.t,
    violatingFDs: array<FunctionalDependency.t>,
    proposedTables: array<tableChange>,
    narrative: string,
    isLossless: bool,
    preservesFDs: bool,
  }
}

// Discovery state
type discoveryState =
  | NotStarted
  | Discovering
  | Discovered(array<FunctionalDependency.t>)
  | Error(string)

// FD visualization
module FDVisualization = {
  @react.component
  let make = (~fds: array<FunctionalDependency.t>) => {
    <div className="fd-list">
      {fds
      ->Array.mapWithIndex((fd, i) => {
        let confidenceClass = if fd.confidence >= 0.95 {
          "confidence-high"
        } else if fd.confidence >= 0.8 {
          "confidence-medium"
        } else {
          "confidence-low"
        }

        <div key={Int.toString(i)} className={`fd-item ${confidenceClass}`}>
          <div className="fd-expression">
            <span className="fd-determinant">
              {React.string(`{${fd.determinant->Array.join(", ")}}`)}
            </span>
            <span className="fd-arrow"> {React.string(" -> ")} </span>
            <span className="fd-dependent">
              {React.string(`{${fd.dependent->Array.join(", ")}}`)}
            </span>
          </div>
          <div className="fd-meta">
            <span className="fd-confidence">
              {React.string(`${Float.toFixed(fd.confidence *. 100.0, ~digits=1)}%`)}
            </span>
            {if fd.discovered {
              <span className="fd-source discovered"> {React.string("discovered")} </span>
            } else {
              <span className="fd-source declared"> {React.string("declared")} </span>
            }}
          </div>
        </div>
      })
      ->React.array}
    </div>
  }
}

// Normal form status visualization
module NFStatus = {
  @react.component
  let make = (~currentNF: NormalForm.t, ~violations: array<(NormalForm.t, string)>) => {
    let currentIndex = switch currentNF {
    | NormalForm.First => 0
    | NormalForm.Second => 1
    | NormalForm.Third => 2
    | NormalForm.BCNF => 3
    | NormalForm.Fourth => 4
    | NormalForm.Fifth => 5
    }

    <div className="nf-status">
      <h3> {React.string("Normal Form Analysis")} </h3>
      <div className="nf-ladder">
        {NormalForm.all
        ->Array.mapWithIndex((nf, i) => {
          let statusClass = if i < currentIndex {
            "nf-passed"
          } else if i == currentIndex {
            "nf-current"
          } else {
            "nf-pending"
          }

          let violation = violations->Array.find(((vnf, _)) => vnf == nf)

          <div key={Int.toString(i)} className={`nf-step ${statusClass}`}>
            <div className="nf-badge">
              {React.string(NormalForm.toString(nf))}
            </div>
            <div className="nf-info">
              <span className="nf-name"> {React.string(NormalForm.toFullName(nf))} </span>
              <span className="nf-desc"> {React.string(NormalForm.description(nf))} </span>
              {switch violation {
              | Some((_, reason)) =>
                <span className="nf-violation"> {React.string(reason)} </span>
              | None => React.null
              }}
            </div>
            <div className="nf-status-icon">
              {if i < currentIndex {
                React.string("\u2713")
              } else if i == currentIndex {
                React.string("\u25CF")
              } else {
                React.string("\u25CB")
              }}
            </div>
          </div>
        })
        ->React.array}
      </div>
    </div>
  }
}

// Proposal card
module ProposalCard = {
  @react.component
  let make = (~proposal: NormalizationProposal.t, ~onApply: unit => unit) => {
    <div className="proposal-card">
      <div className="proposal-header">
        <span className="proposal-transition">
          {React.string(
            `${NormalForm.toString(proposal.currentNF)} → ${NormalForm.toString(proposal.targetNF)}`,
          )}
        </span>
        <div className="proposal-badges">
          {if proposal.isLossless {
            <span className="badge badge-success"> {React.string("Lossless")} </span>
          } else {
            <span className="badge badge-warning"> {React.string("Lossy")} </span>
          }}
          {if proposal.preservesFDs {
            <span className="badge badge-success"> {React.string("FD-Preserving")} </span>
          } else {
            <span className="badge badge-warning"> {React.string("FDs may change")} </span>
          }}
        </div>
      </div>

      <div className="proposal-narrative">
        <h4> {React.string("What's wrong?")} </h4>
        <p> {React.string(proposal.narrative)} </p>
      </div>

      <div className="proposal-violating-fds">
        <h4> {React.string("Violating dependencies:")} </h4>
        <ul>
          {proposal.violatingFDs
          ->Array.mapWithIndex((fd, i) =>
            <li key={Int.toString(i)}>
              <code> {React.string(FunctionalDependency.toString(fd))} </code>
            </li>
          )
          ->React.array}
        </ul>
      </div>

      <div className="proposal-changes">
        <h4> {React.string("Proposed schema changes:")} </h4>
        {proposal.proposedTables
        ->Array.mapWithIndex((table, i) =>
          <div key={Int.toString(i)} className="proposed-table">
            <code className="table-name"> {React.string(table.name)} </code>
            <span className="table-fields">
              {React.string(`(${table.fields->Array.join(", ")})`)}
            </span>
            <p className="table-reason"> {React.string(table.reason)} </p>
          </div>
        )
        ->React.array}
      </div>

      <div className="proposal-actions">
        <button className="btn btn-secondary"> {React.string("View Proof")} </button>
        <button className="btn btn-primary" onClick={_ => onApply()}>
          {React.string("Apply Normalization")}
        </button>
      </div>
    </div>
  }
}

@react.component
let make = (~collections: array<Collection.t>) => {
  let (selectedCollection, setSelectedCollection) = React.useState(() => "")
  let (discoveryState, setDiscoveryState) = React.useState(() => NotStarted)
  let (confidenceThreshold, setConfidenceThreshold) = React.useState(() => 0.95)

  // Example data for demo
  let (currentNF, _setCurrentNF) = React.useState(() => NormalForm.Second)
  let (violations, _setViolations) = React.useState(() => [
    (NormalForm.Third, "author_name depends on author_id, not on the full key"),
  ])

  let (proposals, _setProposals) = React.useState(() => [
    {
      NormalizationProposal.id: "normalize-to-3nf",
      currentNF: NormalForm.Second,
      targetNF: NormalForm.Third,
      violatingFDs: [
        {
          FunctionalDependency.determinant: ["author_id"],
          dependent: ["author_name", "author_email"],
          confidence: 1.0,
          discovered: true,
        },
      ],
      proposedTables: [
        {
          NormalizationProposal.name: "evidence",
          fields: ["id", "claim", "prompt_score", "author_id"],
          reason: "Main evidence table with foreign key to authors",
        },
        {
          NormalizationProposal.name: "authors",
          fields: ["author_id", "author_name", "author_email"],
          reason: "Extracted author information to eliminate transitive dependency",
        },
      ],
      narrative: "The current schema has a transitive dependency: author_name and author_email depend on author_id, not on the evidence's primary key. This means author information is repeated for every piece of evidence by the same author, risking inconsistency.",
      isLossless: true,
      preservesFDs: true,
    },
  ])

  let handleDiscoverFDs = () => {
    setDiscoveryState(_ => Discovering)
    // TODO: Call backend command to discover FDs
    let _ = setTimeout(() => {
      setDiscoveryState(_ =>
        Discovered([
          {
            FunctionalDependency.determinant: ["id"],
            dependent: ["claim", "prompt_score", "author_id", "author_name"],
            confidence: 1.0,
            discovered: true,
          },
          {
            FunctionalDependency.determinant: ["author_id"],
            dependent: ["author_name", "author_email"],
            confidence: 0.98,
            discovered: true,
          },
          {
            FunctionalDependency.determinant: ["claim"],
            dependent: ["category"],
            confidence: 0.85,
            discovered: true,
          },
        ])
      )
    }, 1500)
  }

  let handleApplyProposal = () => {
    // TODO: Call backend command to apply normalization
    Console.log("Applying normalization proposal")
  }

  <section className="normalization-panel">
    <h2> {React.string("Schema Normalization")} </h2>
    <p className="section-hint">
      {React.string(
        "Discover functional dependencies in your data and normalize your schema with proof-carrying transformations.",
      )}
    </p>

    <div className="form-row">
      <div className="form-group">
        <label> {React.string("Collection")} </label>
        <select
          value={selectedCollection}
          onChange={evt => setSelectedCollection(_ => ReactEvent.Form.target(evt)["value"])}>
          <option value=""> {React.string("Select collection...")} </option>
          {collections
          ->Array.map(c =>
            <option key={c.name} value={c.name}> {React.string(c.name)} </option>
          )
          ->React.array}
        </select>
      </div>
      <div className="form-group">
        <label>
          {React.string(`Confidence threshold: ${Float.toFixed(confidenceThreshold *. 100.0, ~digits=0)}%`)}
        </label>
        <input
          type_="range"
          min="0.5"
          max="1.0"
          step={0.05}
          value={Float.toString(confidenceThreshold)}
          onChange={evt => {
            let v = Float.fromString(ReactEvent.Form.target(evt)["value"])->Option.getOr(0.95)
            setConfidenceThreshold(_ => v)
          }}
        />
      </div>
      <button
        className="btn btn-primary"
        onClick={_ => handleDiscoverFDs()}
        disabled={selectedCollection == ""}>
        {switch discoveryState {
        | Discovering => React.string("Discovering...")
        | _ => React.string("Discover Dependencies")
        }}
      </button>
    </div>

    {switch discoveryState {
    | NotStarted =>
      <div className="empty-state">
        <p> {React.string("Select a collection and click 'Discover Dependencies' to analyze your schema.")} </p>
      </div>
    | Discovering =>
      <div className="loading-state">
        <p> {React.string("Analyzing data patterns to discover functional dependencies...")} </p>
      </div>
    | Error(msg) =>
      <div className="error-state">
        <p> {React.string(msg)} </p>
      </div>
    | Discovered(fds) =>
      <>
        <div className="discovery-results">
          <h3> {React.string("Discovered Functional Dependencies")} </h3>
          <FDVisualization fds />
        </div>

        <NFStatus currentNF violations />

        {if Array.length(proposals) > 0 {
          <div className="normalization-proposals">
            <h3> {React.string("Normalization Proposals")} </h3>
            {proposals
            ->Array.map(p =>
              <ProposalCard key={p.id} proposal={p} onApply={handleApplyProposal} />
            )
            ->React.array}
          </div>
        } else {
          <div className="all-good">
            <span className="icon"> {React.string("\u2713")} </span>
            <p> {React.string("Your schema is already in the highest applicable normal form!")} </p>
          </div>
        }}
      </>
    }}
  </section>
}
