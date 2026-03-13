# SPDX-License-Identifier: PMPL-1.0-or-later
"""
HTTP API for Lith-Analytics using Oxygen.jl
"""

"""
Application state shared across handlers
"""
mutable struct AppState
    client::LithClient
    store::ColumnarStore
    config::Config
end

# Global state (Oxygen uses global handlers)
const APP_STATE = Ref{Union{AppState,Nothing}}(nothing)

"""
    serve(config::Config)

Start the HTTP server.
"""
function serve(config::Config)
    # Initialize state
    client = LithClient(config.lith.api_url)
    store = ColumnarStore(config.storage.data_dir)

    # Load existing data
    for collection in config.lith.collections
        load!(store, collection)
    end

    APP_STATE[] = AppState(client, store, config)

    @info "Lith-Analytics starting" host=config.server.host port=config.server.port

    # Define routes
    @get "/analytics/health" function()
        state = APP_STATE[]
        lith_reachable = health_check(state.client)

        return Dict(
            "status" => "ok",
            "lith_reachable" => lith_reachable,
            "collections" => length(state.store.collections)
        )
    end

    @get "/analytics/stats" function()
        state = APP_STATE[]
        return stats(state.store)
    end

    @get "/analytics/collections" function()
        state = APP_STATE[]
        result = Dict{String,Any}()

        for (collection, df) in state.store.collections
            result[collection] = Dict(
                "rows" => nrow(df),
                "columns" => names(df),
                "last_sync" => get(state.store.last_sync, collection, nothing)
            )
        end

        return result
    end

    @post "/analytics/sync" function(req)
        state = APP_STATE[]
        body = JSON3.read(String(req.body))

        collection = get(body, :collection, nothing)
        mode = Symbol(get(body, :mode, "full"))

        if isnothing(collection)
            return Dict("error" => "Collection required")
        end

        start_time = now()

        try
            rows = sync!(state.store, state.client, string(collection); mode=mode)
            duration = now() - start_time

            return Dict(
                "status" => "ok",
                "collection" => collection,
                "rows_synced" => rows,
                "duration_ms" => Dates.value(duration)
            )
        catch e
            return Dict("error" => string(e))
        end
    end

    @get "/analytics/prompt-scores" function(req)
        state = APP_STATE[]
        params = Oxygen.queryparams(req)

        collection = get(params, "collection", "evidence")
        groupby = get(params, "groupBy", nothing)

        return prompt_stats(state.store, collection; groupby=isnothing(groupby) ? nothing : Symbol(groupby))
    end

    @get "/analytics/prompt-distribution" function(req)
        state = APP_STATE[]
        params = Oxygen.queryparams(req)

        collection = get(params, "collection", "evidence")
        dimension = get(params, "dimension", "provenance")
        bins = parse(Int, get(params, "bins", "10"))

        return prompt_distribution(state.store, collection, Symbol(dimension); bins=bins)
    end

    @get "/analytics/time-series" function(req)
        state = APP_STATE[]
        params = Oxygen.queryparams(req)

        collection = get(params, "collection", "evidence")
        interval = Symbol(get(params, "interval", "day"))
        field = get(params, "field", nothing)

        return time_series(state.store, collection; interval=interval, field=isnothing(field) ? nothing : Symbol(field))
    end

    @get "/analytics/contributors" function(req)
        state = APP_STATE[]
        params = Oxygen.queryparams(req)

        collection = get(params, "collection", "evidence")

        return contributors(state.store, collection)
    end

    # Start server
    Oxygen.serve(; host=config.server.host, port=config.server.port)
end
