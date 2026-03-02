# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# VeriSimDB Julia Client — VQL (VeriSimDB Query Language) operations.
#
# VQL is VeriSimDB's native query language for multi-modal queries that span
# graph traversals, vector similarity, spatial filters, and temporal constraints
# in a single statement. This file provides execution and explain functions.

"""
    execute_vql(client, query; params=Dict()) -> VqlResult

Execute a VQL query and return the result set.

VQL queries can combine modalities — for example:
```
FIND hexads WHERE vector_similar(\$embedding, 0.8)
  AND spatial_within(51.5, -0.1, 10km)
  AND graph_connected("category:science", depth: 2)
```

# Arguments
- `client::Client` — The authenticated client.
- `query::String` — The VQL query string.

# Keyword Arguments
- `params::Dict{String,String}` — Named parameters for parameterised queries.

# Returns
A `VqlResult` containing columns, rows, count, and execution time.
"""
function execute_vql(
    client::Client,
    query::String;
    params::Dict{String,String}=Dict{String,String}()
)::VqlResult
    body = Dict("query" => query, "params" => params)
    resp = do_post(client, "/api/v1/vql/execute", body)
    return parse_response(VqlResult, resp)
end

"""
    explain_vql(client, query; params=Dict()) -> VqlExplanation

Return the query execution plan for a VQL statement without running it.
Useful for debugging and optimising queries.

# Arguments
- `client::Client` — The authenticated client.
- `query::String` — The VQL query string.

# Keyword Arguments
- `params::Dict{String,String}` — Named parameters.

# Returns
A `VqlExplanation` containing the plan, estimated cost, and warnings.
"""
function explain_vql(
    client::Client,
    query::String;
    params::Dict{String,String}=Dict{String,String}()
)::VqlExplanation
    body = Dict("query" => query, "params" => params)
    resp = do_post(client, "/api/v1/vql/explain", body)
    return parse_response(VqlExplanation, resp)
end
