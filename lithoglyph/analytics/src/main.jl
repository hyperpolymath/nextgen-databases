#!/usr/bin/env julia
# SPDX-License-Identifier: PMPL-1.0-or-later
"""
Lith-Analytics entry point
"""

using Pkg
Pkg.activate(@__DIR__ |> dirname)

using LithAnalytics

function main()
    # Parse arguments
    config_path = "config.toml"

    for (i, arg) in enumerate(ARGS)
        if arg == "--config" && i < length(ARGS)
            config_path = ARGS[i + 1]
        elseif arg == "--help"
            println("""
Lith-Analytics - OLAP analytics layer for Lith

Usage:
    julia src/main.jl [options]

Options:
    --config PATH    Path to config file (default: config.toml)
    --help           Show this help message
            """)
            return
        end
    end

    # Load configuration
    config = load_config(config_path)

    # Start server
    serve(config)
end

main()
