# SPDX-License-Identifier: PMPL-1.0-or-later
"""
Lith-Analytics: OLAP analytics layer for Lith

Provides columnar storage and analytical queries over Lith documents.
"""
module LithAnalytics

using Arrow
using CSV
using Dates
using DataFrames
using HTTP
using JSON3
using Oxygen
using Parquet2
using Tables
using TOML
using UUIDs

export Config, load_config
export LithClient, Document, fetch_collection, fetch_document, extract_prompt_scores, extract_timestamp, health_check
export ColumnarStore, sync!, load!, query, stats, prompt_stats, prompt_distribution, time_series, contributors
export serve

include("config.jl")
include("lith_client.jl")
include("columnar_store.jl")
include("analytics.jl")
include("api.jl")

end # module
