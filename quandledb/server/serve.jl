# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

"""
QuandleDB HTTP Server

Wraps Skein.jl as an HTTP API with static file serving.
Maintains a quandle-semantic sidecar index (separate from raw diagram storage).

Usage:
    julia --project=server server/serve.jl [dbpath] [--port PORT] [--static DIR] [--semantic-index PATH]
"""

using HTTP
using JSON3
using Skein
using KnotTheory
using Dates
using SQLite
using DBInterface
using SHA

include("quandle_semantic.jl")
using .QuandleSemantic

# -- Semantic sidecar ---------------------------------------------------------

const SEMANTIC_SCHEMA_VERSION = 1

const CREATE_SEMANTIC_TABLES = """
CREATE TABLE IF NOT EXISTS quandle_semantic_index (
    knot_name TEXT PRIMARY KEY,
    descriptor_version TEXT NOT NULL,
    descriptor_hash TEXT NOT NULL,
    quandle_key TEXT NOT NULL,
    diagram_format TEXT NOT NULL,
    canonical_representation TEXT NOT NULL,
    component_count INTEGER NOT NULL,
    crossing_number INTEGER NOT NULL,
    writhe INTEGER NOT NULL,
    genus INTEGER,
    determinant INTEGER,
    signature INTEGER,
    alexander_polynomial TEXT,
    jones_polynomial TEXT,
    quandle_generator_count INTEGER,
    quandle_relation_count INTEGER,
    quandle_degree_partition TEXT,
    colouring_count_3 INTEGER,
    colouring_count_5 INTEGER,
    indexed_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS semantic_schema_info (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
"""

const SEMANTIC_INDEX_STATEMENTS = [
    "CREATE INDEX IF NOT EXISTS idx_semantic_hash ON quandle_semantic_index(descriptor_hash)",
    "CREATE INDEX IF NOT EXISTS idx_semantic_key ON quandle_semantic_index(quandle_key)",
    "CREATE INDEX IF NOT EXISTS idx_semantic_crossing ON quandle_semantic_index(crossing_number)",
    "CREATE INDEX IF NOT EXISTS idx_semantic_determinant ON quandle_semantic_index(determinant)",
    "CREATE INDEX IF NOT EXISTS idx_semantic_signature ON quandle_semantic_index(signature)",
    "CREATE INDEX IF NOT EXISTS idx_semantic_col3 ON quandle_semantic_index(colouring_count_3)",
    "CREATE INDEX IF NOT EXISTS idx_semantic_col5 ON quandle_semantic_index(colouring_count_5)",
]

const REQUIRED_SEMANTIC_COLUMNS = [
    ("descriptor_version", "TEXT"),
    ("descriptor_hash", "TEXT"),
    ("quandle_key", "TEXT"),
    ("diagram_format", "TEXT"),
    ("canonical_representation", "TEXT"),
    ("component_count", "INTEGER"),
    ("crossing_number", "INTEGER"),
    ("writhe", "INTEGER"),
    ("genus", "INTEGER"),
    ("determinant", "INTEGER"),
    ("signature", "INTEGER"),
    ("alexander_polynomial", "TEXT"),
    ("jones_polynomial", "TEXT"),
    ("quandle_generator_count", "INTEGER"),
    ("quandle_relation_count", "INTEGER"),
    ("quandle_degree_partition", "TEXT"),
    ("colouring_count_3", "INTEGER"),
    ("colouring_count_5", "INTEGER"),
    ("indexed_at", "TEXT"),
]

mutable struct SemanticIndexDB
    conn::SQLite.DB
    path::String

    function SemanticIndexDB(path::String)
        conn = SQLite.DB(path)
        DBInterface.execute(conn, "PRAGMA journal_mode=WAL")

        for stmt in split(CREATE_SEMANTIC_TABLES, ";")
            stripped = strip(stmt)
            isempty(stripped) || DBInterface.execute(conn, stripped)
        end

        _ensure_semantic_columns!(conn)
        for stmt in SEMANTIC_INDEX_STATEMENTS
            DBInterface.execute(conn, stmt)
        end

        DBInterface.execute(conn,
            "INSERT OR REPLACE INTO semantic_schema_info (key, value) VALUES ('version', ?)",
            [string(SEMANTIC_SCHEMA_VERSION)])

        new(conn, path)
    end
end

function Base.close(sdb::SemanticIndexDB)
    close(sdb.conn)
end

function _ensure_semantic_columns!(conn::SQLite.DB)
    existing = Set{String}()
    for row in DBInterface.execute(conn, "PRAGMA table_info(quandle_semantic_index)")
        push!(existing, string(row[:name]))
    end

    # Preserve existing primary key if table already exists.
    if !("knot_name" in existing)
        DBInterface.execute(conn, "ALTER TABLE quandle_semantic_index ADD COLUMN knot_name TEXT")
    end

    for (name, typ) in REQUIRED_SEMANTIC_COLUMNS
        if !(name in existing)
            DBInterface.execute(conn, "ALTER TABLE quandle_semantic_index ADD COLUMN $name $typ")
        end
    end
end

_db_nullable(value) = value === nothing ? missing : value

function _str_or_nothing(value)
    (value === nothing || ismissing(value)) && return nothing
    string(value)
end

function _int_or_nothing(value)
    (value === nothing || ismissing(value)) && return nothing
    Int(value)
end

function component_count_from_pd_blob(blob::Union{Nothing, String})::Int
    isnothing(blob) && return 1
    parts = split(blob, "|")
    length(parts) >= 3 || return 1
    startswith(parts[3], "c=") || return 1
    payload = parts[3][3:end]
    isempty(payload) && return 1
    max(1, length(split(payload, ";")))
end

function _fallback_descriptor(record::KnotRecord, canonical::String, component_count::Int)
    approx_gens = max(1, record.crossing_number)
    approx_rels = record.crossing_number
    approx_key = string(approx_gens, ":", approx_rels, ":fallback")
    payload = string("fallback-v1|", record.diagram_format, "|", canonical, "|", approx_key)
    hash = bytes2hex(sha256(payload))

    (
        descriptor_version = "fallback-v1",
        descriptor_hash = hash,
        quandle_key = approx_key,
        canonical_representation = canonical,
        component_count = component_count,
        quandle_generator_count = approx_gens,
        quandle_relation_count = approx_rels,
        quandle_degree_partition = "",
        colouring_count_3 = nothing,
        colouring_count_5 = nothing,
    )
end

function semantic_descriptor(record::KnotRecord)
    canonical = if !isnothing(record.canonical_diagram)
        record.canonical_diagram
    else
        Skein.serialise_gauss(Skein.canonical_gauss(record.gauss_code))
    end
    component_count = component_count_from_pd_blob(record.pd_code)

    if !isnothing(record.pd_code)
        try
            pd = Skein.to_planardiagram(record)
            q = QuandleSemantic.quandle_descriptor(pd)
            return (
                descriptor_version = "qpres-v1",
                descriptor_hash = q.presentation_hash,
                quandle_key = q.quandle_key,
                canonical_representation = q.canonical_presentation,
                component_count = component_count,
                quandle_generator_count = q.generator_count,
                quandle_relation_count = q.relation_count,
                quandle_degree_partition = q.degree_partition,
                colouring_count_3 = q.colouring_count_3,
                colouring_count_5 = q.colouring_count_5,
            )
        catch
            # If PD decoding/extraction fails, fall back to structural cache.
        end
    end

    _fallback_descriptor(record, canonical, component_count)
end

function upsert_semantic_index!(sdb::SemanticIndexDB, record::KnotRecord)
    d = semantic_descriptor(record)
    now = string(Dates.now())

    DBInterface.execute(sdb.conn,
        """INSERT INTO quandle_semantic_index (
               knot_name, descriptor_version, descriptor_hash, quandle_key,
               diagram_format, canonical_representation, component_count,
               crossing_number, writhe, genus, determinant, signature,
               alexander_polynomial, jones_polynomial,
               quandle_generator_count, quandle_relation_count, quandle_degree_partition,
               colouring_count_3, colouring_count_5, indexed_at
           ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
           ON CONFLICT(knot_name) DO UPDATE SET
               descriptor_version = excluded.descriptor_version,
               descriptor_hash = excluded.descriptor_hash,
               quandle_key = excluded.quandle_key,
               diagram_format = excluded.diagram_format,
               canonical_representation = excluded.canonical_representation,
               component_count = excluded.component_count,
               crossing_number = excluded.crossing_number,
               writhe = excluded.writhe,
               genus = excluded.genus,
               determinant = excluded.determinant,
               signature = excluded.signature,
               alexander_polynomial = excluded.alexander_polynomial,
               jones_polynomial = excluded.jones_polynomial,
               quandle_generator_count = excluded.quandle_generator_count,
               quandle_relation_count = excluded.quandle_relation_count,
               quandle_degree_partition = excluded.quandle_degree_partition,
               colouring_count_3 = excluded.colouring_count_3,
               colouring_count_5 = excluded.colouring_count_5,
               indexed_at = excluded.indexed_at""",
        [record.name, d.descriptor_version, d.descriptor_hash, d.quandle_key,
         record.diagram_format, d.canonical_representation, d.component_count,
         record.crossing_number, record.writhe, _db_nullable(record.genus),
         _db_nullable(record.determinant), _db_nullable(record.signature),
         _db_nullable(record.alexander_polynomial), _db_nullable(record.jones_polynomial),
         _db_nullable(d.quandle_generator_count), _db_nullable(d.quandle_relation_count),
         _db_nullable(d.quandle_degree_partition), _db_nullable(d.colouring_count_3),
         _db_nullable(d.colouring_count_5), now])
end

function rebuild_semantic_index!(sdb::SemanticIndexDB, db::SkeinDB)::Int
    records = list_knots(db; limit = typemax(Int))
    for record in records
        upsert_semantic_index!(sdb, record)
    end
    length(records)
end

function semantic_row_by_name(sdb::SemanticIndexDB, name::String)
    result = DBInterface.execute(sdb.conn,
        "SELECT * FROM quandle_semantic_index WHERE knot_name = ?", [name])
    for row in result
        return row
    end
    nothing
end

function semantic_to_dict(row)
    Dict{String, Any}(
        "knot_name" => string(row[:knot_name]),
        "descriptor_version" => string(row[:descriptor_version]),
        "descriptor_hash" => string(row[:descriptor_hash]),
        "quandle_key" => string(row[:quandle_key]),
        "diagram_format" => string(row[:diagram_format]),
        "canonical_representation" => string(row[:canonical_representation]),
        "component_count" => Int(row[:component_count]),
        "crossing_number" => Int(row[:crossing_number]),
        "writhe" => Int(row[:writhe]),
        "genus" => _int_or_nothing(row[:genus]),
        "determinant" => _int_or_nothing(row[:determinant]),
        "signature" => _int_or_nothing(row[:signature]),
        "alexander_polynomial" => _str_or_nothing(row[:alexander_polynomial]),
        "jones_polynomial" => _str_or_nothing(row[:jones_polynomial]),
        "quandle_generator_count" => _int_or_nothing(row[:quandle_generator_count]),
        "quandle_relation_count" => _int_or_nothing(row[:quandle_relation_count]),
        "quandle_degree_partition" => _str_or_nothing(row[:quandle_degree_partition]),
        "colouring_count_3" => _int_or_nothing(row[:colouring_count_3]),
        "colouring_count_5" => _int_or_nothing(row[:colouring_count_5]),
        "indexed_at" => string(row[:indexed_at]),
    )
end

function semantic_summary_by_name(sdb::SemanticIndexDB, name::String)
    row = semantic_row_by_name(sdb, name)
    isnothing(row) && return nothing

    Dict{String, Any}(
        "descriptor_hash" => string(row[:descriptor_hash]),
        "quandle_key" => string(row[:quandle_key]),
        "quandle_generator_count" => _int_or_nothing(row[:quandle_generator_count]),
        "quandle_relation_count" => _int_or_nothing(row[:quandle_relation_count]),
        "colouring_count_3" => _int_or_nothing(row[:colouring_count_3]),
        "colouring_count_5" => _int_or_nothing(row[:colouring_count_5]),
    )
end

function ensure_semantic_entry!(db::SkeinDB, sdb::SemanticIndexDB, name::String)
    row = semantic_row_by_name(sdb, name)
    if !isnothing(row)
        return row
    end

    record = fetch_knot(db, name)
    isnothing(record) && return nothing
    upsert_semantic_index!(sdb, record)
    semantic_row_by_name(sdb, name)
end

function _rows_to_names(rows)
    unique(string(r[:knot_name]) for r in rows)
end

function semantic_equivalence_buckets(sdb::SemanticIndexDB, name::String)
    row = semantic_row_by_name(sdb, name)
    isnothing(row) && return nothing

    strong_rows = DBInterface.execute(sdb.conn,
        "SELECT knot_name FROM quandle_semantic_index WHERE descriptor_hash = ? ORDER BY knot_name",
        [string(row[:descriptor_hash])])
    weak_rows = DBInterface.execute(sdb.conn,
        "SELECT knot_name FROM quandle_semantic_index WHERE quandle_key = ? ORDER BY knot_name",
        [string(row[:quandle_key])])

    strong = _rows_to_names(strong_rows)
    weak = _rows_to_names(weak_rows)

    (
        descriptor_hash = string(row[:descriptor_hash]),
        quandle_key = string(row[:quandle_key]),
        strong = strong,
        weak = weak,
        combined = unique(vcat(strong, weak)),
    )
end

# -- CLI argument parsing -----------------------------------------------------

function parse_args(args)
    dbpath = "data/knots.db"
    port = 8080
    static_dir = "public/"
    semantic_index = nothing

    i = 1
    while i <= length(args)
        if args[i] == "--port" && i < length(args)
            port = parse(Int, args[i + 1])
            i += 2
        elseif args[i] == "--static" && i < length(args)
            static_dir = args[i + 1]
            i += 2
        elseif args[i] == "--semantic-index" && i < length(args)
            semantic_index = args[i + 1]
            i += 2
        elseif !startswith(args[i], "-")
            dbpath = args[i]
            i += 1
        else
            i += 1
        end
    end

    if isnothing(semantic_index)
        semantic_index = dbpath * ".semantic.db"
    end

    (; dbpath, port, static_dir, semantic_index)
end

# -- JSON helpers -------------------------------------------------------------

function format_jones(jp::Nothing)
    nothing
end

function format_jones(jp::String)
    s = replace(jp, "*" => "")
    replace(s, "q^" => "q^")
end

function knot_to_dict(record::KnotRecord; semantic=nothing)
    Dict{String, Any}(
        "id" => record.id,
        "name" => record.name,
        "gauss_code" => record.gauss_code.crossings,
        "diagram_format" => record.diagram_format,
        "crossing_number" => record.crossing_number,
        "writhe" => record.writhe,
        "genus" => record.genus,
        "seifert_circle_count" => record.seifert_circle_count,
        "determinant" => record.determinant,
        "signature" => record.signature,
        "alexander_polynomial" => record.alexander_polynomial,
        "jones_polynomial" => record.jones_polynomial,
        "jones_display" => format_jones(record.jones_polynomial),
        "metadata" => record.metadata,
        "semantic" => semantic,
        "created_at" => string(record.created_at),
        "updated_at" => string(record.updated_at),
    )
end

function json_response(data; status=200)
    body = JSON3.write(data)
    HTTP.Response(status, ["Content-Type" => "application/json", "Access-Control-Allow-Origin" => "*"], body)
end

function error_response(msg::String; status=400)
    json_response(Dict("error" => msg); status)
end

# -- Static content -----------------------------------------------------------

const MIME_TYPES = Dict(
    ".html" => "text/html; charset=utf-8",
    ".css" => "text/css; charset=utf-8",
    ".js" => "application/javascript; charset=utf-8",
    ".mjs" => "application/javascript; charset=utf-8",
    ".json" => "application/json",
    ".png" => "image/png",
    ".jpg" => "image/jpeg",
    ".jpeg" => "image/jpeg",
    ".svg" => "image/svg+xml",
    ".ico" => "image/x-icon",
    ".woff" => "font/woff",
    ".woff2" => "font/woff2",
    ".ttf" => "font/ttf",
)

function get_mime(path::String)
    ext = lowercase(splitext(path)[2])
    get(MIME_TYPES, ext, "application/octet-stream")
end

function parse_int_param(params::Dict{String, String}, key::String)
    val = get(params, key, nothing)
    isnothing(val) && return nothing
    tryparse(Int, val)
end

function extract_query_params(uri::String)
    idx = findfirst('?', uri)
    isnothing(idx) && return Dict{String, String}()

    query_string = uri[idx + 1:end]
    params = Dict{String, String}()
    for pair in split(query_string, '&')
        kv = split(pair, '='; limit = 2)
        if length(kv) == 2
            params[HTTP.URIs.unescapeuri(kv[1])] = HTTP.URIs.unescapeuri(kv[2])
        end
    end
    params
end

function extract_path(uri::String)
    idx = findfirst('?', uri)
    isnothing(idx) ? uri : uri[1:idx - 1]
end

function serve_static(static_dir::String, path::String)
    clean_path = replace(path, ".." => "")
    clean_path = lstrip(clean_path, '/')

    if isempty(clean_path) || clean_path == "/"
        clean_path = "index.html"
    end

    filepath = joinpath(static_dir, clean_path)
    if isfile(filepath)
        return HTTP.Response(200, ["Content-Type" => get_mime(filepath)], read(filepath))
    end

    index_path = joinpath(static_dir, "index.html")
    if isfile(index_path)
        return HTTP.Response(200, ["Content-Type" => "text/html; charset=utf-8"], read(index_path))
    end

    HTTP.Response(404, ["Content-Type" => "text/plain"], "Not Found")
end

# -- API handlers -------------------------------------------------------------

function handle_knots(db::SkeinDB, sdb::SemanticIndexDB, params::Dict{String, String})
    crossing_number = parse_int_param(params, "crossing_number")
    writhe_val = parse_int_param(params, "writhe")
    genus_val = parse_int_param(params, "genus")
    determinant_val = parse_int_param(params, "determinant")
    signature_val = parse_int_param(params, "signature")
    limit = something(parse_int_param(params, "limit"), 100)
    offset = something(parse_int_param(params, "offset"), 0)
    name_search = get(params, "name", nothing)

    results = query(db;
        crossing_number = crossing_number,
        writhe = writhe_val,
        genus = genus_val,
        determinant = determinant_val,
        signature = signature_val,
        name_like = isnothing(name_search) ? nothing : "%$(name_search)%",
        limit = limit,
        offset = offset,
    )

    knots_payload = Dict{String, Any}[]
    for r in results
        push!(knots_payload, knot_to_dict(r; semantic = semantic_summary_by_name(sdb, r.name)))
    end

    json_response(Dict("knots" => knots_payload, "count" => length(results), "limit" => limit, "offset" => offset))
end

function handle_knot_detail(db::SkeinDB, sdb::SemanticIndexDB, name::String)
    record = fetch_knot(db, name)
    isnothing(record) && return error_response("Knot '$name' not found"; status = 404)
    json_response(knot_to_dict(record; semantic = semantic_summary_by_name(sdb, record.name)))
end

function handle_semantic_detail(db::SkeinDB, sdb::SemanticIndexDB, name::String)
    row = ensure_semantic_entry!(db, sdb, name)
    isnothing(row) && return error_response("Semantic index for '$name' not found"; status = 404)
    json_response(semantic_to_dict(row))
end

function handle_semantic_equivalents(db::SkeinDB, sdb::SemanticIndexDB, name::String)
    ensure_semantic_entry!(db, sdb, name)
    buckets = semantic_equivalence_buckets(sdb, name)
    isnothing(buckets) && return error_response("Knot '$name' not found"; status = 404)

    json_response(Dict(
        "name" => name,
        "descriptor_hash" => buckets.descriptor_hash,
        "quandle_key" => buckets.quandle_key,
        "strong_candidates" => buckets.strong,
        "weak_candidates" => buckets.weak,
        "combined_candidates" => buckets.combined,
        "count" => length(buckets.combined),
    ))
end

function handle_semantic_index(sdb::SemanticIndexDB, params::Dict{String, String})
    crossing_number = parse_int_param(params, "crossing_number")
    determinant_val = parse_int_param(params, "determinant")
    signature_val = parse_int_param(params, "signature")
    quandle_generator_count = parse_int_param(params, "quandle_generator_count")
    colouring_count_3 = parse_int_param(params, "colouring_count_3")
    descriptor_hash = get(params, "descriptor_hash", nothing)
    quandle_key = get(params, "quandle_key", nothing)
    limit = something(parse_int_param(params, "limit"), 100)
    offset = something(parse_int_param(params, "offset"), 0)

    conditions = String[]
    args = Any[]

    if !isnothing(crossing_number)
        push!(conditions, "crossing_number = ?")
        push!(args, crossing_number)
    end
    if !isnothing(determinant_val)
        push!(conditions, "determinant = ?")
        push!(args, determinant_val)
    end
    if !isnothing(signature_val)
        push!(conditions, "signature = ?")
        push!(args, signature_val)
    end
    if !isnothing(quandle_generator_count)
        push!(conditions, "quandle_generator_count = ?")
        push!(args, quandle_generator_count)
    end
    if !isnothing(colouring_count_3)
        push!(conditions, "colouring_count_3 = ?")
        push!(args, colouring_count_3)
    end
    if !isnothing(descriptor_hash)
        push!(conditions, "descriptor_hash = ?")
        push!(args, descriptor_hash)
    end
    if !isnothing(quandle_key)
        push!(conditions, "quandle_key = ?")
        push!(args, quandle_key)
    end

    where_clause = isempty(conditions) ? "" : "WHERE " * join(conditions, " AND ")
    sql = """
        SELECT * FROM quandle_semantic_index
        $where_clause
        ORDER BY crossing_number, knot_name
        LIMIT ? OFFSET ?
    """
    push!(args, limit)
    push!(args, offset)

    rows = [semantic_to_dict(row) for row in DBInterface.execute(sdb.conn, sql, args)]
    json_response(Dict("semantic_index" => rows, "count" => length(rows), "limit" => limit, "offset" => offset))
end

function handle_statistics(db::SkeinDB, sdb::SemanticIndexDB)
    stats = statistics(db)

    genus_dist = Dict{Int, Int}()
    for knot in list_knots(db; limit = 10000)
        if !isnothing(knot.genus)
            genus_dist[knot.genus] = get(genus_dist, knot.genus, 0) + 1
        end
    end

    semantic_indexed = 0
    for row in DBInterface.execute(sdb.conn, "SELECT COUNT(*) AS n FROM quandle_semantic_index")
        semantic_indexed = Int(row[:n])
    end

    json_response(Dict(
        "total_knots" => stats.total_knots,
        "min_crossings" => stats.min_crossings,
        "max_crossings" => stats.max_crossings,
        "crossing_distribution" => stats.crossing_distribution,
        "genus_distribution" => genus_dist,
        "skein_schema_version" => 4,
        "semantic_schema_version" => SEMANTIC_SCHEMA_VERSION,
        "semantic_indexed_knots" => semantic_indexed,
    ))
end

# -- Router ------------------------------------------------------------------

function router(db::SkeinDB, sdb::SemanticIndexDB, static_dir::String, req::HTTP.Request)
    uri = req.target
    path = extract_path(uri)
    params = extract_query_params(uri)
    method = uppercase(String(req.method))

    if method == "OPTIONS"
        return HTTP.Response(204, [
            "Access-Control-Allow-Origin" => "*",
            "Access-Control-Allow-Methods" => "GET, OPTIONS",
            "Access-Control-Allow-Headers" => "Content-Type",
        ])
    end

    method != "GET" && return error_response("Method not allowed"; status = 405)

    if path == "/api/knots"
        return handle_knots(db, sdb, params)
    elseif path == "/api/semantic"
        return handle_semantic_index(sdb, params)
    elseif path == "/api/statistics"
        return handle_statistics(db, sdb)
    end

    m_equiv = match(r"^/api/semantic-equivalents/(.+)$", path)
    if !isnothing(m_equiv)
        return handle_semantic_equivalents(db, sdb, m_equiv.captures[1])
    end

    m_sem = match(r"^/api/semantic/(.+)$", path)
    if !isnothing(m_sem)
        return handle_semantic_detail(db, sdb, m_sem.captures[1])
    end

    m_knot = match(r"^/api/knots/(.+)$", path)
    if !isnothing(m_knot)
        return handle_knot_detail(db, sdb, m_knot.captures[1])
    end

    serve_static(static_dir, path)
end

# -- Main --------------------------------------------------------------------

function main()
    config = parse_args(ARGS)

    println("QuandleDB Server")
    println("  Database:       $(config.dbpath)")
    println("  Semantic index: $(config.semantic_index)")
    println("  Port:           $(config.port)")
    println("  Static:         $(config.static_dir)")
    println()

    if !isfile(config.dbpath)
        println("Warning: Database file '$(config.dbpath)' not found.")
        println("  Create it with Skein.jl first, or provide a valid path.")
        println()
    end

    db = SkeinDB(config.dbpath; readonly = true)
    total = count_knots(db)

    semantic_path = abspath(config.semantic_index)
    mkpath(dirname(semantic_path))
    sdb = SemanticIndexDB(semantic_path)
    indexed = rebuild_semantic_index!(sdb, db)

    println("Loaded $total knots from Skein database.")
    println("Indexed $indexed knots into semantic sidecar.")
    println()
    println("Starting server on http://localhost:$(config.port)")
    println("Press Ctrl+C to stop.")
    println()

    static_dir = abspath(config.static_dir)
    HTTP.serve(config.port) do req
        try
            router(db, sdb, static_dir, req)
        catch e
            @error "Request error" exception = (e, catch_backtrace())
            error_response("Internal server error"; status = 500)
        end
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
