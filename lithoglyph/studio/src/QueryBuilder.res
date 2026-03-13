// SPDX-License-Identifier: PMPL-1.0-or-later
// Lith Studio - Query Builder Component (Phase 2)

open Types

// Query filter types
module Filter = {
  type operator =
    | Equals
    | NotEquals
    | GreaterThan
    | LessThan
    | GreaterOrEqual
    | LessOrEqual
    | Contains
    | StartsWith
    | EndsWith

  type t = {
    field: string,
    operator: operator,
    value: string,
  }

  let operatorToString = op =>
    switch op {
    | Equals => "="
    | NotEquals => "!="
    | GreaterThan => ">"
    | LessThan => "<"
    | GreaterOrEqual => ">="
    | LessOrEqual => "<="
    | Contains => "CONTAINS"
    | StartsWith => "STARTS WITH"
    | EndsWith => "ENDS WITH"
    }

  let operatorToGql = op =>
    switch op {
    | Equals => "="
    | NotEquals => "<>"
    | GreaterThan => ">"
    | LessThan => "<"
    | GreaterOrEqual => ">="
    | LessOrEqual => "<="
    | Contains => "LIKE"
    | StartsWith => "LIKE"
    | EndsWith => "LIKE"
    }
}

// Query definition
module Query = {
  type selectField =
    | All
    | Fields(array<string>)

  type orderDirection = Asc | Desc

  type order = {
    field: string,
    direction: orderDirection,
  }

  type t = {
    collection: string,
    select: selectField,
    filters: array<Filter.t>,
    orderBy: option<order>,
    limit: option<int>,
    includeProvenance: bool,
  }

  let empty = () => {
    collection: "",
    select: All,
    filters: [],
    orderBy: None,
    limit: Some(100),
    includeProvenance: false,
  }
}

// Generate GQL from query
let generateGql = (query: Query.t): string => {
  if query.collection == "" {
    "-- Select a collection to build query"
  } else {
    let selectClause = switch query.select {
    | Query.All => "*"
    | Query.Fields(fields) => fields->Array.join(", ")
    }

    let provenanceClause = if query.includeProvenance {
      ", _provenance"
    } else {
      ""
    }

    let whereClause = if Array.length(query.filters) > 0 {
      let conditions =
        query.filters
        ->Array.map(f => {
          let op = Filter.operatorToGql(f.operator)
          let value = switch f.operator {
          | Filter.Contains => `'%${f.value}%'`
          | Filter.StartsWith => `'${f.value}%'`
          | Filter.EndsWith => `'%${f.value}'`
          | _ => `'${f.value}'`
          }
          `${f.field} ${op} ${value}`
        })
        ->Array.join("\n  AND ")
      `\nWHERE ${conditions}`
    } else {
      ""
    }

    let orderClause = switch query.orderBy {
    | Some({field, direction}) =>
      let dir = switch direction {
      | Query.Asc => "ASC"
      | Query.Desc => "DESC"
      }
      `\nORDER BY ${field} ${dir}`
    | None => ""
    }

    let limitClause = switch query.limit {
    | Some(n) => `\nLIMIT ${Int.toString(n)}`
    | None => ""
    }

    `SELECT ${selectClause}${provenanceClause}
FROM ${query.collection}${whereClause}${orderClause}${limitClause};`
  }
}

// Filter editor sub-component
module FilterEditor = {
  @react.component
  let make = (
    ~availableFields: array<string>,
    ~onAdd: Filter.t => unit,
  ) => {
    let (field, setField) = React.useState(() => "")
    let (operator, setOperator) = React.useState(() => Filter.Equals)
    let (value, setValue) = React.useState(() => "")

    let handleSubmit = evt => {
      ReactEvent.Form.preventDefault(evt)
      if field != "" && value != "" {
        onAdd({Filter.field, operator, value})
        setField(_ => "")
        setValue(_ => "")
      }
    }

    <form className="filter-editor" onSubmit={handleSubmit}>
      <select
        value={field}
        onChange={evt => setField(_ => ReactEvent.Form.target(evt)["value"])}>
        <option value=""> {React.string("Select field...")} </option>
        {availableFields
        ->Array.map(f =>
          <option key={f} value={f}> {React.string(f)} </option>
        )
        ->React.array}
      </select>
      <select
        value={switch operator {
        | Filter.Equals => "eq"
        | Filter.NotEquals => "neq"
        | Filter.GreaterThan => "gt"
        | Filter.LessThan => "lt"
        | Filter.GreaterOrEqual => "gte"
        | Filter.LessOrEqual => "lte"
        | Filter.Contains => "contains"
        | Filter.StartsWith => "starts"
        | Filter.EndsWith => "ends"
        }}
        onChange={evt => {
          let v = ReactEvent.Form.target(evt)["value"]
          setOperator(_ =>
            switch v {
            | "eq" => Filter.Equals
            | "neq" => Filter.NotEquals
            | "gt" => Filter.GreaterThan
            | "lt" => Filter.LessThan
            | "gte" => Filter.GreaterOrEqual
            | "lte" => Filter.LessOrEqual
            | "contains" => Filter.Contains
            | "starts" => Filter.StartsWith
            | "ends" => Filter.EndsWith
            | _ => Filter.Equals
            }
          )
        }}>
        <option value="eq"> {React.string("equals")} </option>
        <option value="neq"> {React.string("not equals")} </option>
        <option value="gt"> {React.string("greater than")} </option>
        <option value="lt"> {React.string("less than")} </option>
        <option value="gte"> {React.string("greater or equal")} </option>
        <option value="lte"> {React.string("less or equal")} </option>
        <option value="contains"> {React.string("contains")} </option>
        <option value="starts"> {React.string("starts with")} </option>
        <option value="ends"> {React.string("ends with")} </option>
      </select>
      <input
        type_="text"
        placeholder="Value"
        value={value}
        onChange={evt => setValue(_ => ReactEvent.Form.target(evt)["value"])}
      />
      <button type_="submit" className="btn btn-primary btn-small">
        {React.string("Add Filter")}
      </button>
    </form>
  }
}

// Query results display
module QueryResults = {
  type resultState =
    | NoResults
    | Loading
    | Success(array<dict<string>>)
    | Error(string)

  @react.component
  let make = (~results: resultState) => {
    <div className="query-results">
      <h3> {React.string("Results")} </h3>
      {switch results {
      | NoResults =>
        <div className="empty-state">
          <p> {React.string("Run a query to see results")} </p>
        </div>
      | Loading =>
        <div className="loading-state">
          <p> {React.string("Executing query...")} </p>
        </div>
      | Error(msg) =>
        <div className="error-state">
          <p> {React.string(msg)} </p>
        </div>
      | Success(rows) =>
        if Array.length(rows) == 0 {
          <div className="empty-state">
            <p> {React.string("No matching documents")} </p>
          </div>
        } else {
          let headers = rows[0]->Option.mapOr([], Dict.keysToArray)
          <div className="results-table-wrapper">
            <table className="results-table">
              <thead>
                <tr>
                  {headers
                  ->Array.map(h => <th key={h}> {React.string(h)} </th>)
                  ->React.array}
                </tr>
              </thead>
              <tbody>
                {rows
                ->Array.mapWithIndex((row, i) =>
                  <tr key={Int.toString(i)}>
                    {headers
                    ->Array.map(h => {
                      let value = row->Dict.get(h)->Option.getOr("")
                      <td key={h}> {React.string(value)} </td>
                    })
                    ->React.array}
                  </tr>
                )
                ->React.array}
              </tbody>
            </table>
          </div>
        }
      }}
    </div>
  }
}

@react.component
let make = (~collections: array<Collection.t>) => {
  let (query, setQuery) = React.useState(() => Query.empty())
  let (results, setResults) = React.useState(() => QueryResults.NoResults)

  let availableFields = switch collections->Array.find(c => c.name == query.collection) {
  | Some(coll) => coll.fields->Array.map(f => f.name)
  | None => []
  }

  let handleCollectionChange = evt => {
    let value = ReactEvent.Form.target(evt)["value"]
    setQuery(prev => {...prev, collection: value, filters: []})
  }

  let handleAddFilter = (filter: Filter.t) => {
    setQuery(prev => {
      ...prev,
      filters: prev.filters->Array.concat([filter]),
    })
  }

  let handleRemoveFilter = index => {
    setQuery(prev => {
      ...prev,
      filters: prev.filters->Array.filterWithIndex((_, i) => i != index),
    })
  }

  let handleProvenanceToggle = evt => {
    let checked = ReactEvent.Form.target(evt)["checked"]
    setQuery(prev => {...prev, includeProvenance: checked})
  }

  let handleLimitChange = evt => {
    let value = ReactEvent.Form.target(evt)["value"]
    let limit = Int.fromString(value)
    setQuery(prev => {...prev, limit})
  }

  let handleRunQuery = _ => {
    setResults(_ => QueryResults.Loading)
    // TODO: Call Tauri command to execute query
    // For now, simulate with placeholder
    let _ = setTimeout(() => {
      setResults(_ => QueryResults.Success([]))
    }, 500)
  }

  let gql = generateGql(query)

  <section className="query-builder">
    <h2> {React.string("Query Builder")} </h2>
    <div className="query-form">
      <div className="form-row">
        <div className="form-group">
          <label> {React.string("Collection")} </label>
          <select value={query.collection} onChange={handleCollectionChange}>
            <option value=""> {React.string("Select collection...")} </option>
            {collections
            ->Array.map(c =>
              <option key={c.name} value={c.name}> {React.string(c.name)} </option>
            )
            ->React.array}
          </select>
        </div>
        <div className="form-group">
          <label> {React.string("Limit")} </label>
          <input
            type_="number"
            value={query.limit->Option.mapOr("", n => Int.toString(n))}
            onChange={handleLimitChange}
            min="1"
            max="10000"
          />
        </div>
        <div className="form-group checkbox-group">
          <input
            type_="checkbox"
            id="provenance"
            checked={query.includeProvenance}
            onChange={handleProvenanceToggle}
          />
          <label htmlFor="provenance"> {React.string("Include provenance")} </label>
        </div>
      </div>

      <div className="filters-section">
        <h3> {React.string("Filters")} </h3>
        {if Array.length(query.filters) > 0 {
          <div className="filters-list">
            {query.filters
            ->Array.mapWithIndex((filter, index) =>
              <div key={Int.toString(index)} className="filter-item">
                <span className="filter-field"> {React.string(filter.field)} </span>
                <span className="filter-op">
                  {React.string(Filter.operatorToString(filter.operator))}
                </span>
                <span className="filter-value"> {React.string(`"${filter.value}"`)} </span>
                <button
                  type_="button"
                  className="remove-btn"
                  onClick={_ => handleRemoveFilter(index)}>
                  {React.string("\u00D7")}
                </button>
              </div>
            )
            ->React.array}
          </div>
        } else {
          React.null
        }}
        <FilterEditor availableFields onAdd={handleAddFilter} />
      </div>

      <div className="query-preview">
        <h3> {React.string("Generated GQL")} </h3>
        <pre className="code-block"> {React.string(gql)} </pre>
      </div>

      <div className="actions-bar">
        <button className="btn btn-secondary"> {React.string("Explain Query")} </button>
        <button className="btn btn-primary" onClick={handleRunQuery}>
          {React.string("Run Query")}
        </button>
      </div>
    </div>

    <QueryResults results />
  </section>
}
