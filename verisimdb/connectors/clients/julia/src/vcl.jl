# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# VeriSimDB Julia Client — VCL (VeriSimDB Query Language) operations.
#
# VCL is VeriSimDB's native query language for multi-modal queries that span
# graph traversals, vector similarity, spatial filters, and temporal constraints
# in a single statement. This file provides execution and explain functions.

"""
    execute_vcl(client, query; params=Dict()) -> VclResult

Execute a VCL query and return the result set.

VCL queries can combine modalities — for example:
```
FIND octads WHERE vector_similar(\$embedding, 0.8)
  AND spatial_within(51.5, -0.1, 10km)
  AND graph_connected("category:science", depth: 2)
```

# Arguments
- `client::Client` — The authenticated client.
- `query::String` — The VCL query string.

# Keyword Arguments
- `params::Dict{String,String}` — Named parameters for parameterised queries.

# Returns
A `VclResult` containing columns, rows, count, and execution time.
"""
function execute_vcl(
    client::Client,
    query::String;
    params::Dict{String,String}=Dict{String,String}()
)::VclResult
    body = Dict("query" => query, "params" => params)
    resp = do_post(client, "/api/v1/vcl/execute", body)
    return parse_response(VclResult, resp)
end

"""
    explain_vcl(client, query; params=Dict()) -> VclExplanation

Return the query execution plan for a VCL statement without running it.
Useful for debugging and optimising queries.

# Arguments
- `client::Client` — The authenticated client.
- `query::String` — The VCL query string.

# Keyword Arguments
- `params::Dict{String,String}` — Named parameters.

# Returns
A `VclExplanation` containing the plan, estimated cost, and warnings.
"""
function explain_vcl(
    client::Client,
    query::String;
    params::Dict{String,String}=Dict{String,String}()
)::VclExplanation
    body = Dict("query" => query, "params" => params)
    resp = do_post(client, "/api/v1/vcl/explain", body)
    return parse_response(VclExplanation, resp)
end
