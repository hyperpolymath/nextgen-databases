# SPDX-License-Identifier: PMPL-1.0-or-later
#
# examples/krladapter_integration.jl — Phase 4 dogfood demonstration.
#
# Shows that KRLAdapter.jl's TangleIR (a tangle/knot intermediate
# representation) can be stored and verified through VerisimCore+FederationManager
# WITHOUT requiring any Federable shapes. The Core = {Semantic, Temporal,
# Provenance} alone suffices for this client, because TangleIR's own
# provenance metadata naturally maps to the Core's Provenance modality.
#
# This is the positive Phase 4 result: KRLAdapter.jl is satisfied by
# VerisimCore alone — it needs identity + audit trail, not similarity
# search or full-text index or geospatial.
#
# This example constructs a minimal synthetic TangleIR surrogate rather
# than depending on the KRLAdapter.jl module itself, to keep the
# experiment's test surface self-contained.

include(joinpath(@__DIR__, "..", "impl", "Crypto.jl"))
include(joinpath(@__DIR__, "..", "impl", "drift", "Metrics.jl"))
include(joinpath(@__DIR__, "..", "impl", "VerisimCore.jl"))
include(joinpath(@__DIR__, "..", "impl", "FederationManager.jl"))
# Tropical modules must be loaded before VCLProver (Prover dispatches to them)
include(joinpath(@__DIR__, "..", "impl", "tropical", "TropicalMatrix.jl"))
include(joinpath(@__DIR__, "..", "impl", "tropical", "TangleGraph.jl"))
include(joinpath(@__DIR__, "..", "impl", "vcl", "Query.jl"))
include(joinpath(@__DIR__, "..", "impl", "vcl", "Prover.jl"))

using .Crypto
using .VerisimCore
using .Metrics
using .FederationManager
using .TropicalMatrix
using .TangleGraph
using .VCLQuery
using .VCLProver

# -----------------------------------------------------------------------
# Minimal TangleIR surrogate (mirrors KRLAdapter.jl/src/ir.jl shape)
# -----------------------------------------------------------------------

struct TangleIRSurrogate
    name::String
    dt_code::Vector{Int}          # Dowker-Thistlethwaite code
    provenance::Symbol             # :user | :derived | :imported | :rewritten
    source_text::String
end

# -----------------------------------------------------------------------
# Adapter: TangleIR → VerisimCore SemanticBlob
# -----------------------------------------------------------------------

"""
Serialise a TangleIR into a SemanticBlob that VerisimCore can enrich.
Type URI identifies the IR class; proof_bytes carries a deterministic
binary encoding of the tangle's content.
"""
function tangle_to_semantic(tangle::TangleIRSurrogate)::SemanticBlob
    type_uris = ["http://krl.hyperpolymath.org/#TangleIR",
                 "http://krl.hyperpolymath.org/#provenance/$(tangle.provenance)"]
    # Simple deterministic encoding: name || len(dt_code) || dt_code... || source_text
    bytes = UInt8[]
    append!(bytes, collect(codeunits(tangle.name)))
    push!(bytes, 0x00)
    append!(bytes, reinterpret(UInt8, [Int64(length(tangle.dt_code))]))
    for c in tangle.dt_code
        append!(bytes, reinterpret(UInt8, [Int64(c)]))
    end
    push!(bytes, 0x00)
    append!(bytes, collect(codeunits(tangle.source_text)))
    SemanticBlob(type_uris, bytes)
end

function tangle_octad_id(tangle::TangleIRSurrogate)::OctadId
    # Deterministic 16-byte id from tangle name + dt_code digest.
    input = collect(codeunits("krl:$(tangle.name)"))
    for c in tangle.dt_code
        append!(input, reinterpret(UInt8, [Int64(c)]))
    end
    digest = SHA.sha256(input)
    OctadId(digest[1:16])
end

import SHA

# -----------------------------------------------------------------------
# Demonstration
# -----------------------------------------------------------------------

function demo()
    println("=== KRLAdapter.jl → VerisimCore dogfood demo ===\n")

    # Construct a TangleIR (here: the trefoil knot, DT code [4, 6, 2]).
    trefoil = TangleIRSurrogate(
        "trefoil",
        [4, 6, 2],
        :user,
        "B_1^3 (braid word for trefoil)",
    )

    # Stand up a fresh Core store. No federation manager needed — this
    # client doesn't need any Federable shapes.
    store = Store()
    manager = Manager()

    # Adapt → enrich.
    id = tangle_octad_id(trefoil)
    blob = tangle_to_semantic(trefoil)
    println("TangleIR octad id: ", id)
    println("SemanticBlob type URIs: ", blob.type_uris)
    println()

    enrich!(store, id, :semantic, blob, "krl-user")

    # Record a derivation event: simplified trefoil → same underlying knot.
    simplified = TangleIRSurrogate(
        "trefoil", [4, 6, 2], :rewritten, "Reidemeister III applied",
    )
    blob2 = tangle_to_semantic(simplified)
    enrich!(store, id, :semantic, blob2, "krl-rewriter")

    # Verify via PROOF INTEGRITY — no federation required.
    v_int = prove(ProofIntegrity(id), store, manager)
    println("PROOF INTEGRITY: ", v_int)

    # Freshness check.
    v_fresh = prove(ProofFreshness(id, Int64(60_000_000_000)), store, manager)
    println("PROOF FRESHNESS (60s): ", v_fresh)

    # Show the audit trail.
    octad = get_core(store, id)
    println("\nAudit trail:")
    for (i, entry) in enumerate(octad.provenance.entries)
        println("  [$i] actor=$(entry.actor) @ $(entry.timestamp.epoch_nanos)ns")
    end

    println("\n=== Client satisfied by Core alone. No Federable shapes needed. ===")
end

# -----------------------------------------------------------------------
# Phase 5: Tropical consonance demo
# -----------------------------------------------------------------------

"""
demo_consonance()

Demonstrates PROOF CONSONANCE using tropical Bellman-Ford:

1. Trivial case: same octad id → immediate PASS.
2. Same DT code (same tangle, different provenance) → fast-path PASS.
3. RI-equivalent tangles (differ by one isolated crossing) → tropical PASS.
4. Unrelated tangles (trefoil vs figure-eight) → tropical FAIL (RI only).

Formal backing: `bellman_ford` in Tropical_Matrices_Full.thy.
See impl/tropical/TropicalMatrix.jl for the Julia mirror of the Isabelle proof.
"""
function demo_consonance()
    println("\n=== PROOF CONSONANCE — tropical Bellman-Ford demo ===\n")

    store   = Store()
    manager = Manager()

    # Helper: store a tangle and return its octad id
    function store_tangle(t::TangleIRSurrogate)
        id   = tangle_octad_id(t)
        blob = tangle_to_semantic(t)
        enrich!(store, id, :semantic, blob, "krl-demo")
        id
    end

    # Case 1: same octad — trivially consonant
    println("--- Case 1: same octad id ---")
    trefoil = TangleIRSurrogate("trefoil", [4, 6, 2], :user, "B_1^3")
    id_t    = store_tangle(trefoil)
    r1 = prove(ProofConsonance(id_t, id_t), store, manager)
    println("  Result: ", r1)

    # Case 2: same DT code, different provenance — fast-path match
    println("\n--- Case 2: same DT code, different provenance ---")
    trefoil2 = TangleIRSurrogate("trefoil-rewritten", [4, 6, 2], :rewritten,
                                  "Reidemeister III applied")
    id_t2    = store_tangle(trefoil2)
    r2 = prove(ProofConsonance(id_t, id_t2), store, manager)
    println("  Result: ", r2)

    # Case 3: RI-equivalent — trefoil with one RI⁺ crossing added then removed
    # Simulated: DT code [4, 6, 2] vs [4, 6, 2] with an extra RI pair ±8
    # In practice RI⁺ on trefoil gives a 4-crossing diagram with an ear
    println("\n--- Case 3: RI-equivalent tangles ---")
    # Synthetic RI⁺ of trefoil: prepend an isolated ±2 pair
    trefoil_ri = TangleIRSurrogate("trefoil-ri", [2, -2, 4, 6, 2], :derived,
                                    "trefoil + RI ear")
    id_ri = store_tangle(trefoil_ri)
    r3 = prove(ProofConsonance(id_t, id_ri, 3), store, manager)
    println("  Result: ", r3)

    # Case 4: different knots — trefoil [4,6,2] vs figure-eight [4,8,12,2,10,6]
    println("\n--- Case 4: trefoil vs figure-eight (expected FAIL at RI depth) ---")
    fig8 = TangleIRSurrogate("figure-eight", [4, 8, 12, 2, 10, 6], :user,
                               "figure-eight knot")
    id_f8 = store_tangle(fig8)
    r4 = prove(ProofConsonance(id_t, id_f8), store, manager)
    println("  Result: ", r4)

    println("\n=== Consonance demo complete ===")
end

# Run the demo when executed as a script.
if abspath(PROGRAM_FILE) == @__FILE__
    demo()
    demo_consonance()
end
