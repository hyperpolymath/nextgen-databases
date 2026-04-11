# SPDX-License-Identifier: PMPL-1.0-or-later
#
# impl/tropical/TangleGraph.jl — TangleIR → tropical adjacency matrix.
#
# Models a bounded Reidemeister reachability graph:
#
#   vertices : tangle configurations, identified by DT code
#   edges    : single Reidemeister moves, each costing 1
#   A[i,j]   : Tropical(1.0) if tangle j is one RI/RII/RIII move from i
#              TROP_ZERO (∞) otherwise
#
# `bellman_ford_matrix(A)[1,2]` then gives the minimum number of
# Reidemeister moves needed to reach tangle B from tangle A, or ∞ if
# no path exists within the modelled move set.
#
# Coverage v0.1 — only Reidemeister I (isolated crossing add/remove).
# RII (crossing pair cancellation) and RIII (triangle move) require
# full Gauss/PD code manipulation; that integration point is
# `KnotTheory.jl` (READ-ONLY community library) via KRLAdapter.jl.
# Stubs are provided; replace `_rii_neighbors` / `_riii_neighbors`
# with live calls once the KnotTheory.jl adapter is wired.

module TangleGraph

export dt_codes_from_blob, build_consonance_graph, ConsonanceGraph

# Module TropicalMatrix is included by the same script before this file.
# Reach it via Main.TropicalMatrix.

# -----------------------------------------------------------------------
# DT-code extraction from a VerisimCore SemanticBlob's proof_bytes
# -----------------------------------------------------------------------

"""
    dt_codes_from_blob(bytes) → Vector{Int}

Decode the Dowker-Thistlethwaite (DT) code from a TangleIR SemanticBlob
as produced by `tangle_to_semantic` in krladapter_integration.jl.

Encoding format (little-endian Int64):
  name (UTF-8) ‖ 0x00 ‖ Int64(len) ‖ Int64(c₁)…Int64(cₙ) ‖ 0x00 ‖ source

Returns empty vector on decode failure (caller should treat as
inconclusive, not as a hard error).
"""
function dt_codes_from_blob(bytes::Vector{UInt8})::Vector{Int}
    isempty(bytes) && return Int[]

    # Skip past the name (find first null byte)
    nul1 = findfirst(==(0x00), bytes)
    nul1 === nothing && return Int[]
    pos = nul1 + 1

    # Read Int64 count
    pos + 7 > length(bytes) && return Int[]
    n_crossings = Int(reinterpret(Int64, bytes[pos:pos+7])[1])
    pos += 8

    # Sanity check: DT code must have ≥ 0 and ≤ 100 crossings
    (n_crossings < 0 || n_crossings > 100) && return Int[]

    # Read n_crossings Int64 values
    dt = Vector{Int}(undef, n_crossings)
    for i in 1:n_crossings
        pos + 7 > length(bytes) && return Int[]
        dt[i] = Int(reinterpret(Int64, bytes[pos:pos+7])[1])
        pos += 8
    end
    dt
end

# -----------------------------------------------------------------------
# Reidemeister-move neighbourhood (v0.1: RI only)
# -----------------------------------------------------------------------

"""
    ri_neighbors(dt) → Vector{Vector{Int}}

Produce all DT codes reachable from `dt` by a single Reidemeister I move:
  - RI⁻ (removal): remove one isolated self-crossing (adjacent equal-magnitude pair)
  - RI⁺ (addition): add one isolated self-crossing at each boundary point

v0.1: RI⁻ only (removal is deterministic; addition produces infinitely
many candidates without a bound — deferred to Phase 2).
"""
function ri_neighbors(dt::Vector{Int})::Vector{Vector{Int}}
    neighbors = Vector{Vector{Int}}()

    # RI⁻: remove a consecutive ±2k / ∓2k pair (isolated crossing)
    # In DT notation an isolated crossing appears as two adjacent entries
    # a, b with |a| + 1 = |b| or |b| + 1 = |a| and opposite signs.
    # Conservative check: adjacent entries that are additive inverses.
    i = 1
    while i < length(dt)
        if dt[i] == -dt[i+1] || dt[i] == dt[i+1]
            # Remove this pair and renumber
            candidate = vcat(dt[1:i-1], dt[i+2:end])
            push!(neighbors, candidate)
        end
        i += 1
    end
    neighbors
end

"""
    _rii_neighbors(dt) → Vector{Vector{Int}}   [STUB]

Reidemeister II moves (pair creation/cancellation).
Requires Gauss/PD code manipulation from KnotTheory.jl.
"""
function _rii_neighbors(dt::Vector{Int})::Vector{Vector{Int}}
    # TODO: wire to KnotTheory.jl Reidemeister II move generator
    Vector{Vector{Int}}()
end

"""
    _riii_neighbors(dt) → Vector{Vector{Int}}   [STUB]

Reidemeister III moves (triangle).
Requires PD code manipulation from KnotTheory.jl.
"""
function _riii_neighbors(dt::Vector{Int})::Vector{Vector{Int}}
    # TODO: wire to KnotTheory.jl Reidemeister III move generator
    Vector{Vector{Int}}()
end

"""
    all_neighbors(dt) → Vector{Vector{Int}}

Union of all RI/RII/RIII neighbors.  v0.1: RI only.
"""
function all_neighbors(dt::Vector{Int})::Vector{Vector{Int}}
    vcat(ri_neighbors(dt), _rii_neighbors(dt), _riii_neighbors(dt))
end

# -----------------------------------------------------------------------
# Consonance graph
# -----------------------------------------------------------------------

"""
    ConsonanceGraph

Finite tangle reachability graph for two starting configurations.

Fields:
  `nodes`  — ordered list of DT codes (index 1 = tangle A, index 2 = tangle B)
  `matrix` — min-plus adjacency matrix over those nodes
"""
struct ConsonanceGraph
    nodes::Vector{Vector{Int}}
    matrix::Matrix{Main.TropicalMatrix.Tropical}
end

"""
    build_consonance_graph(dt_a, dt_b; depth=2) → ConsonanceGraph

Build a bounded neighbourhood graph containing dt_a, dt_b, and all
tangles reachable from either within `depth` Reidemeister moves.

The graph is used by `bellman_ford_matrix` to check reachability:
  - finite entry [1,2] → consonant (minimum-move path exists)
  - TROP_ZERO (∞) at [1,2] → no path found in this graph

Note: soundness only; completeness requires full RI/RII/RIII coverage.
"""
function build_consonance_graph(
        dt_a::Vector{Int},
        dt_b::Vector{Int};
        depth::Int = 2
    )::ConsonanceGraph

    TM = Main.TropicalMatrix

    # BFS to collect all nodes reachable within `depth` moves from either start
    seen  = Dict{Vector{Int}, Int}()   # dt_code → node index
    queue = Tuple{Vector{Int}, Int}[]  # (dt_code, hops_from_start)

    function add_node!(dt)
        if !haskey(seen, dt)
            seen[dt] = length(seen) + 1
            push!(queue, (dt, 0))
        end
    end

    add_node!(dt_a)
    add_node!(dt_b)

    while !isempty(queue)
        dt, hops = popfirst!(queue)
        hops >= depth && continue
        for nbr in all_neighbors(dt)
            add_node!(nbr)
            # Don't re-enqueue already-processed nodes
            if seen[nbr] == length(seen)  # freshly added
                push!(queue, (nbr, hops + 1))
            end
        end
    end

    n     = length(seen)
    nodes = Vector{Vector{Int}}(undef, n)
    for (dt, idx) in seen
        nodes[idx] = dt
    end

    # Build adjacency matrix: self-loops at cost 0, edges at cost 1
    A = fill(TM.TROP_ZERO, n, n)
    for i in 1:n
        A[i, i] = TM.TROP_ONE  # reflexivity
    end
    for (dt, i) in seen
        for nbr in all_neighbors(dt)
            haskey(seen, nbr) || continue
            j = seen[nbr]
            A[i, j] = TM.trop_add(A[i, j], TM.Tropical(1.0))
        end
    end

    ConsonanceGraph(nodes, A)
end

end # module TangleGraph
