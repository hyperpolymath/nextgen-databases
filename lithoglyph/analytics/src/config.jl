# SPDX-License-Identifier: PMPL-1.0-or-later
"""
Configuration management for Lith-Analytics
"""

"""
Lith connection configuration
"""
Base.@kwdef struct LithConfig
    api_url::String = "http://localhost:8080"
    collections::Vector{String} = ["evidence"]
end

"""
HTTP server configuration
"""
Base.@kwdef struct ServerConfig
    host::String = "127.0.0.1"
    port::Int = 8082
end

"""
Storage configuration
"""
Base.@kwdef struct StorageConfig
    data_dir::String = "./data"
    retention_days::Int = 0
end

"""
Sync configuration
"""
Base.@kwdef struct SyncConfig
    auto_sync_minutes::Int = 0
end

"""
Main configuration structure
"""
Base.@kwdef struct Config
    lith::LithConfig = LithConfig()
    server::ServerConfig = ServerConfig()
    storage::StorageConfig = StorageConfig()
    sync::SyncConfig = SyncConfig()
end

"""
    load_config(path::String) -> Config

Load configuration from a TOML file. Returns default config if file doesn't exist.
"""
function load_config(path::String)::Config
    if !isfile(path)
        @warn "Config file not found, using defaults" path
        return Config()
    end

    data = TOML.parsefile(path)

    lith = if haskey(data, "lith")
        f = data["lith"]
        LithConfig(
            api_url = get(f, "api_url", "http://localhost:8080"),
            collections = get(f, "collections", ["evidence"])
        )
    else
        LithConfig()
    end

    server = if haskey(data, "server")
        s = data["server"]
        ServerConfig(
            host = get(s, "host", "127.0.0.1"),
            port = get(s, "port", 8082)
        )
    else
        ServerConfig()
    end

    storage = if haskey(data, "storage")
        st = data["storage"]
        StorageConfig(
            data_dir = get(st, "data_dir", "./data"),
            retention_days = get(st, "retention_days", 0)
        )
    else
        StorageConfig()
    end

    sync = if haskey(data, "sync")
        sy = data["sync"]
        SyncConfig(
            auto_sync_minutes = get(sy, "auto_sync_minutes", 0)
        )
    else
        SyncConfig()
    end

    return Config(lith=lith, server=server, storage=storage, sync=sync)
end
