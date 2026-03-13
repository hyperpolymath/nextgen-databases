# SPDX-License-Identifier: PMPL-1.0-or-later
"""
Analytics functions for PROMPT scores and time-series analysis
"""

"""
    prompt_stats(store::ColumnarStore, collection::String; groupby::Union{Symbol,Nothing}=nothing)

Calculate PROMPT score statistics.
"""
function prompt_stats(store::ColumnarStore, collection::String; groupby::Union{Symbol,Nothing}=nothing)
    df = query(store, collection)

    if isempty(df)
        return Dict("error" => "Collection not found or empty")
    end

    prompt_cols = filter(n -> startswith(string(n), "prompt_"), names(df))

    if isempty(prompt_cols)
        return Dict("error" => "No PROMPT scores found in collection")
    end

    if isnothing(groupby)
        # Overall statistics
        result = Dict{String,Any}()

        for col in prompt_cols
            dimension = replace(string(col), "prompt_" => "")
            values = skipmissing(df[!, col])

            if !isempty(collect(values))
                result[dimension] = Dict(
                    "mean" => mean(values),
                    "median" => median(collect(values)),
                    "min" => minimum(values),
                    "max" => maximum(values),
                    "count" => length(collect(values))
                )
            end
        end

        return result
    else
        # Grouped statistics
        group_col = Symbol("data_$groupby")

        if group_col ∉ Symbol.(names(df))
            return Dict("error" => "Group column not found: $groupby")
        end

        grouped = groupby(df, group_col)

        result = Dict{String,Any}()

        for group in grouped
            key = string(first(group[!, group_col]))
            result[key] = Dict{String,Any}()

            for col in prompt_cols
                dimension = replace(string(col), "prompt_" => "")
                values = skipmissing(group[!, col])

                if !isempty(collect(values))
                    result[key][dimension] = Dict(
                        "mean" => mean(values),
                        "count" => length(collect(values))
                    )
                end
            end
        end

        return result
    end
end

"""
    prompt_distribution(store::ColumnarStore, collection::String, dimension::Symbol; bins::Int=10)

Get distribution of a PROMPT dimension.
"""
function prompt_distribution(store::ColumnarStore, collection::String, dimension::Symbol; bins::Int=10)
    df = query(store, collection)

    if isempty(df)
        return Dict("error" => "Collection not found or empty")
    end

    col = Symbol("prompt_$dimension")

    if col ∉ Symbol.(names(df))
        return Dict("error" => "PROMPT dimension not found: $dimension")
    end

    values = collect(skipmissing(df[!, col]))

    if isempty(values)
        return Dict("error" => "No values for dimension: $dimension")
    end

    # Calculate histogram
    min_val = minimum(values)
    max_val = maximum(values)
    bin_width = (max_val - min_val) / bins

    histogram = zeros(Int, bins)
    for v in values
        bin_idx = min(bins, max(1, ceil(Int, (v - min_val) / bin_width)))
        histogram[bin_idx] += 1
    end

    return Dict(
        "dimension" => string(dimension),
        "min" => min_val,
        "max" => max_val,
        "bin_width" => bin_width,
        "histogram" => histogram,
        "total" => length(values)
    )
end

"""
    time_series(store::ColumnarStore, collection::String; interval::Symbol=:day, field::Union{Symbol,Nothing}=nothing)

Generate time-series data for document counts or field values.
"""
function time_series(store::ColumnarStore, collection::String; interval::Symbol=:day, field::Union{Symbol,Nothing}=nothing)
    df = query(store, collection)

    if isempty(df)
        return Dict("error" => "Collection not found or empty")
    end

    if :timestamp ∉ Symbol.(names(df))
        return Dict("error" => "No timestamp column in collection")
    end

    # Filter rows with valid timestamps
    df_with_ts = filter(row -> !ismissing(row.timestamp), df)

    if isempty(df_with_ts)
        return Dict("error" => "No rows with valid timestamps")
    end

    # Truncate timestamps to interval
    truncate_fn = if interval == :hour
        t -> DateTime(year(t), month(t), day(t), hour(t))
    elseif interval == :day
        t -> DateTime(year(t), month(t), day(t))
    elseif interval == :week
        t -> DateTime(year(t), month(t), day(t) - dayofweek(t) + 1)
    elseif interval == :month
        t -> DateTime(year(t), month(t))
    else
        error("Invalid interval: $interval")
    end

    df_with_ts[!, :period] = truncate_fn.(df_with_ts.timestamp)

    if isnothing(field)
        # Count documents per period
        grouped = DataFrames.groupby(df_with_ts, :period)
        result_df = combine(grouped, nrow => :count)
        sort!(result_df, :period)

        return Dict(
            "interval" => string(interval),
            "data" => [Dict("period" => string(row.period), "count" => row.count) for row in eachrow(result_df)]
        )
    else
        # Aggregate field per period
        field_col = Symbol("data_$field")

        if field_col ∉ Symbol.(names(df_with_ts))
            return Dict("error" => "Field not found: $field")
        end

        grouped = DataFrames.groupby(df_with_ts, :period)
        result_df = combine(grouped, field_col => mean => :mean_value, nrow => :count)
        sort!(result_df, :period)

        return Dict(
            "interval" => string(interval),
            "field" => string(field),
            "data" => [Dict("period" => string(row.period), "mean" => row.mean_value, "count" => row.count) for row in eachrow(result_df)]
        )
    end
end

"""
    contributors(store::ColumnarStore, collection::String)

Analyze contributors/provenance data.
"""
function contributors(store::ColumnarStore, collection::String)
    df = query(store, collection)

    if isempty(df)
        return Dict("error" => "Collection not found or empty")
    end

    if :created_by ∉ Symbol.(names(df))
        return Dict("error" => "No provenance data in collection")
    end

    # Filter rows with created_by
    df_with_prov = filter(row -> !ismissing(row.created_by), df)

    if isempty(df_with_prov)
        return Dict("error" => "No provenance data found")
    end

    grouped = DataFrames.groupby(df_with_prov, :created_by)
    result_df = combine(grouped, nrow => :document_count)
    sort!(result_df, :document_count, rev=true)

    return Dict(
        "total_contributors" => nrow(result_df),
        "contributors" => [Dict("name" => row.created_by, "documents" => row.document_count) for row in eachrow(result_df)]
    )
end
