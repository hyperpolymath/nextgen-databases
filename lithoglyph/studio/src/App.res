// SPDX-License-Identifier: PMPL-1.0-or-later
// Lith Studio - Main Application

// Re-export types for backward compatibility
module FieldType = Types.FieldType
module Field = Types.Field
module Collection = Types.Collection
module Backend = Types.Backend
module ServiceStatus = Types.ServiceStatus
module AppInfo = Types.AppInfo

// Validation result from backend
type validationResult = {
  valid: bool,
  errors: array<string>,
  proofs_generated: array<string>,
}

// Check service status from backend
let checkServiceStatus = async (): option<ServiceStatus.t> => {
  try {
    let result = await Backend.invoke("check_service_status", ())
    Some(result)
  } catch {
  | _ => None
  }
}

// Generate GQLdt from collection definition
let generateGqldt = async (collection: Collection.t): result<string, string> => {
  try {
    let payload = {
      "name": collection.name,
      "fields": collection.fields->Array.map(f => {
        let (min, max, required) = switch f.fieldType {
        | FieldType.Number({min, max}) => (min, max, false)
        | FieldType.Text({required}) => (None, None, required)
        | _ => (None, None, false)
        }
        {
          "name": f.name,
          "field_type": f.fieldType->FieldType.toString,
          "min": min,
          "max": max,
          "required": required,
        }
      }),
    }
    let result = await Backend.invoke("generate_gqldt", {"collection": payload})
    Ok(result)
  } catch {
  | JsExn(e) => Error(JsExn.message(e)->Option.getOr("Unknown error"))
  }
}

// Validate GQLdt code
let validateGqldt = async (code: string): result<validationResult, string> => {
  try {
    let result = await Backend.invoke("validate_gqldt", {"code": code})
    Ok(result)
  } catch {
  | JsExn(e) => Error(JsExn.message(e)->Option.getOr("Unknown error"))
  }
}

// Navigation tabs
type tab =
  | Schema
  | Query
  | DataEntry
  | ProofAssistant
  | Normalization

let tabToString = (tab: tab): string =>
  switch tab {
  | Schema => "Schema"
  | Query => "Query"
  | DataEntry => "Data"
  | ProofAssistant => "Proofs"
  | Normalization => "Normalize"
  }

let tabToDescription = (tab: tab): string =>
  switch tab {
  | Schema => "Create Collections"
  | Query => "Query Builder"
  | DataEntry => "Enter Data"
  | ProofAssistant => "Proof Assistant"
  | Normalization => "Schema Normalization"
  }

// Navigation component
module Navigation = {
  @react.component
  let make = (~activeTab: tab, ~onTabChange: tab => unit) => {
    let tabs = [Schema, Query, DataEntry, ProofAssistant, Normalization]

    <nav className="main-nav">
      {tabs
      ->Array.map(t => {
        let isActive = t == activeTab
        <button
          key={tabToString(t)}
          className={`nav-tab ${isActive ? "active" : ""}`}
          onClick={_ => onTabChange(t)}>
          <span className="nav-tab-label"> {React.string(tabToString(t))} </span>
          <span className="nav-tab-desc"> {React.string(tabToDescription(t))} </span>
        </button>
      })
      ->React.array}
    </nav>
  }
}

// LocalStorage helpers for persistence
module Storage = {
  let collectionsKey = "lith_studio_collections"

  let saveCollections = (collections: array<Collection.t>): unit => {
    let json = collections->Array.map(c => {
      {
        "name": c.name,
        "fields": c.fields->Array.map(f => {
          {
            "name": f.name,
            "fieldType": f.fieldType->FieldType.toString,
          }
        }),
      }
    })
    let _ = json  // Ensure json is captured for the raw JS block
    let _: unit = %raw(`localStorage.setItem(collectionsKey, JSON.stringify(json))`)
  }

  let loadCollections = (): array<Collection.t> => {
    let result: option<array<Collection.t>> = %raw(`(function() {
      try {
        var raw = localStorage.getItem(collectionsKey);
        if (!raw) return null;
        var data = JSON.parse(raw);
        return data.map(function(c) {
          return {
            name: c.name,
            fields: c.fields.map(function(f) {
              return {
                name: f.name,
                fieldType: f.fieldType === "Number" ? { TAG: "Number", _0: { min: null, max: null } }
                         : f.fieldType === "Text" ? { TAG: "Text", _0: { required: false } }
                         : f.fieldType === "Confidence" ? "Confidence"
                         : "PromptScores"
              };
            })
          };
        });
      } catch (e) {
        return null;
      }
    })()`)
    result->Option.getOr([])
  }
}

// Main App component
@react.component
let make = () => {
  let (activeTab, setActiveTab) = React.useState(() => Schema)
  let (collections, setCollections) = React.useState(() => Storage.loadCollections())
  let (currentCollection, setCurrentCollection) = React.useState(() => Collection.empty())
  let (validationState, setValidationState) = React.useState(() => Types.NotValidated)
  let (serviceStatus, setServiceStatus) = React.useState(() => None)

  // Check service status on mount
  React.useEffect0(() => {
    let _ = checkServiceStatus()->Promise.then(status => {
      setServiceStatus(_ => status)
      Promise.resolve()
    })->ignore
    None
  })

  // Keyboard navigation (Ctrl+1-5 for tabs)
  React.useEffect1(() => {
    let setTab = setActiveTab
    let _ = setTab  // Ensure setTab is captured for the raw JS block
    let cleanup: unit => unit = %raw(`function() {
      var handler = function(evt) {
        if (evt.ctrlKey || evt.metaKey) {
          var tab = null;
          switch (evt.key) {
            case "1": tab = "Schema"; break;
            case "2": tab = "Query"; break;
            case "3": tab = "DataEntry"; break;
            case "4": tab = "ProofAssistant"; break;
            case "5": tab = "Normalization"; break;
          }
          if (tab) {
            evt.preventDefault();
            setTab(function(_) { return tab; });
          }
        }
      };
      document.addEventListener("keydown", handler);
      return function() { document.removeEventListener("keydown", handler); };
    }()`)
    Some(cleanup)
  }, [setActiveTab])

  // Save collections to localStorage when they change
  React.useEffect1(() => {
    Storage.saveCollections(collections)
    None
  }, [collections])

  // Schema builder handlers
  let handleUpdateName = name => {
    setCurrentCollection(prev => {...prev, name})
  }

  let handleAddField = (field: Field.t) => {
    setCurrentCollection(prev => {
      ...prev,
      fields: prev.fields->Array.concat([field]),
    })
  }

  let handleRemoveField = index => {
    setCurrentCollection(prev => {
      ...prev,
      fields: prev.fields->Array.filterWithIndex((_, i) => i != index),
    })
  }

  let handleCreateCollection = () => {
    if currentCollection.name != "" && Array.length(currentCollection.fields) > 0 {
      setCollections(prev => prev->Array.concat([currentCollection]))
      setCurrentCollection(_ => Collection.empty())
      setValidationState(_ => Types.NotValidated)
    }
  }

  // Auto-validate when collection changes
  React.useEffect1(() => {
    if currentCollection.name != "" && Array.length(currentCollection.fields) > 0 {
      setValidationState(_ => Types.Validating)

      let _ = generateGqldt(currentCollection)->Promise.then(result => {
        switch result {
        | Ok(code) =>
          validateGqldt(code)->Promise.then(validResult => {
            switch validResult {
            | Ok(r) =>
              if r.valid {
                setValidationState(_ => Types.Valid(r.proofs_generated))
              } else {
                setValidationState(_ => Types.Invalid(r.errors))
              }
            | Error(e) => setValidationState(_ => Types.Invalid([e]))
            }
            Promise.resolve()
          })
        | Error(e) =>
          setValidationState(_ => Types.Invalid([e]))
          Promise.resolve()
        }
      })->ignore
    } else {
      setValidationState(_ => Types.NotValidated)
    }
    None
  }, [currentCollection])

  <div className="lith-studio">
    <header>
      <div className="header-content">
        <h1> {React.string("Lith Studio")} </h1>
        <p> {React.string("Zero-friction interface for dependently-typed databases")} </p>
      </div>
      {if Array.length(collections) > 0 {
        <div className="collections-badge">
          <span className="badge">
            {React.string(`${Int.toString(Array.length(collections))} collections`)}
          </span>
        </div>
      } else {
        React.null
      }}
    </header>

    <Navigation activeTab onTabChange={tab => setActiveTab(_ => tab)} />

    <main>
      {switch activeTab {
      | Schema =>
        <div className="schema-view">
          <SchemaBuilder
            collection={currentCollection}
            onUpdateName={handleUpdateName}
            onAddField={handleAddField}
            onRemoveField={handleRemoveField}
          />
          <GqldtPreview
            collection={currentCollection}
            validationState
            onCreateCollection={handleCreateCollection}
          />
        </div>
      | Query => <QueryBuilder collections />
      | DataEntry => <DataEntryPanel collections />
      | ProofAssistant => <ProofAssistant />
      | Normalization => <NormalizationPanel collections />
      }}
    </main>

    <StatusBar status={serviceStatus} />
  </div>
}
