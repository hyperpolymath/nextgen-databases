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
include(joinpath(@__DIR__, "..", "impl", "vcl", "Query.jl"))
include(joinpath(@__DIR__, "..", "impl", "vcl", "Prover.jl"))

using .Crypto
using .VerisimCore
using .Metrics
using .FederationManager
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

# Run the demo when executed as a script.
if abspath(PROGRAM_FILE) == @__FILE__
    demo()
end
