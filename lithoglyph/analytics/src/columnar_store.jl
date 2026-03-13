# SPDX-License-Identifier: PMPL-1.0-or-later
"""
Columnar storage using Arrow/Parquet for analytical queries
"""

"""
Columnar store for analytical data
"""
mutable struct ColumnarStore
    data_dir::String
    collections::Dict{String,DataFrame}
    last_sync::Dict{String,DateTime}

    function ColumnarStore(data_dir::String)
        mkpath(data_dir)
        new(data_dir, Dict{String,DataFrame}(), Dict{String,DateTime}())
    end
end

"""
    sync!(store::ColumnarStore, client::LithClient, collection::String; mode::Symbol=:full)

Sync data from Lith to columnar store.
Modes: :full (replace all), :incremental (append new)
"""
function sync!(store::ColumnarStore, client::LithClient, collection::String; mode::Symbol=:full)
    start_time = now()

    @info "Starting sync" collection mode

    documents = fetch_collection(client, collection)

    # Transform to columnar format
    rows = []
    for doc in documents
        row = Dict{String,Any}(
            "id" => doc.id,
            "synced_at" => now()
        )

        # Flatten document data (first level only)
        for (key, value) in doc.data
            if value isa Number || value isa String || value isa Bool
                row["data_$key"] = value
            elseif value isa Dict
                # Handle nested objects like PROMPT scores
                for (k2, v2) in value
                    if v2 isa Number || v2 isa String || v2 isa Bool
                        row["data_$(key)_$k2"] = v2
                    end
                end
            end
        end

        # Extract PROMPT scores
        prompt = extract_prompt_scores(doc)
        if !isnothing(prompt)
            row["prompt_provenance"] = coalesce(prompt.provenance, missing)
            row["prompt_replicability"] = coalesce(prompt.replicability, missing)
            row["prompt_objective"] = coalesce(prompt.objective, missing)
            row["prompt_methodology"] = coalesce(prompt.methodology, missing)
            row["prompt_publication"] = coalesce(prompt.publication, missing)
            row["prompt_transparency"] = coalesce(prompt.transparency, missing)
        end

        # Extract timestamp
        ts = extract_timestamp(doc)
        row["timestamp"] = isnothing(ts) ? missing : ts

        # Provenance
        if !isnothing(doc.provenance)
            row["created_by"] = get(doc.provenance, "created_by", missing)
        end

        push!(rows, row)
    end

    # Create DataFrame
    if !isempty(rows)
        df = DataFrame(rows)

        if mode == :full
            store.collections[collection] = df
        else
            # Incremental: append new rows
            existing = get(store.collections, collection, DataFrame())
            if isempty(existing)
                store.collections[collection] = df
            else
                store.collections[collection] = vcat(existing, df)
            end
        end

        # Persist to Parquet
        parquet_path = joinpath(store.data_dir, "$(collection).parquet")
        Parquet2.writefile(parquet_path, store.collections[collection])

        store.last_sync[collection] = now()

        duration = now() - start_time
        @info "Sync complete" collection rows=nrow(store.collections[collection]) duration
    end

    return nrow(get(store.collections, collection, DataFrame()))
end

"""
    load!(store::ColumnarStore, collection::String)

Load a collection from Parquet file if it exists.
"""
function load!(store::ColumnarStore, collection::String)
    parquet_path = joinpath(store.data_dir, "$(collection).parquet")

    if isfile(parquet_path)
        @info "Loading from Parquet" collection path=parquet_path
        store.collections[collection] = DataFrame(Parquet2.readfile(parquet_path))
        @info "Loaded" collection rows=nrow(store.collections[collection])
    end
end

"""
    query(store::ColumnarStore, collection::String) -> DataFrame

Get the DataFrame for a collection.
"""
function query(store::ColumnarStore, collection::String)::DataFrame
    return get(store.collections, collection, DataFrame())
end

"""
    stats(store::ColumnarStore) -> Dict

Get statistics about the store.
"""
function stats(store::ColumnarStore)
    result = Dict{String,Any}()

    for (collection, df) in store.collections
        result[collection] = Dict(
            "rows" => nrow(df),
            "columns" => ncol(df),
            "last_sync" => get(store.last_sync, collection, nothing)
        )
    end

    return result
end
