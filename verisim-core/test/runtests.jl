# SPDX-License-Identifier: PMPL-1.0-or-later
#
# runtests.jl — VerisimCore package test suite.
#
# Consolidates the 145 assertions proved across 6 suites in the
# research sibling verisim-modular-experiment. These tests validate
# the same behaviours under the proper package module hierarchy.

using Test
using VerisimCore

# -----------------------------------------------------------------------
# Fixtures
# -----------------------------------------------------------------------

make_id(byte::UInt8) = OctadId(fill(byte, 16))
make_blob(tag::String) = SemanticBlob(
    ["http://verisim.test/#$tag"], collect(codeunits("payload-$tag")))
make_emb(tag::String, dim::Int = 384) = hash_embedding(
    collect(codeunits("embedding-$tag")), dim)
make_doc(tag::String) = collect(codeunits("document-content-$tag"))

# -----------------------------------------------------------------------
# Core lifecycle
# -----------------------------------------------------------------------

@testset "Core: lifecycle + enrichment atomicity" begin
    store = Store()
    id = make_id(0x01)

    @test get_core(store, id) === nothing

    enrich!(store, id, :semantic, make_blob("v1"), "alice")
    oc = get_core(store, id)
    @test oc !== nothing
    @test oc.semantic.type_uris[1] == "http://verisim.test/#v1"
    @test length(oc.temporal.leaves) == 1
    @test length(oc.provenance.entries) == 1

    # def:enrichment: Temporal + Provenance co-written on each call.
    enrich!(store, id, :semantic, make_blob("v2"), "bob")
    enrich!(store, id, :semantic, make_blob("v3"), "carol")
    oc2 = get_core(store, id)
    @test length(oc2.temporal.leaves) == 3
    @test length(oc2.provenance.entries) == 3

    # Hash-chain integrity.
    entries = oc2.provenance.entries
    @test isempty(entries[1].prev_hash)
    @test entries[2].prev_hash == entries[1].this_hash
    @test entries[3].prev_hash == entries[2].this_hash

    # Monotonic Temporal.
    ts = oc2.temporal.leaves
    @test ts[1] < ts[2] < ts[3]
end

# -----------------------------------------------------------------------
# Ed25519 round-trip
# -----------------------------------------------------------------------

@testset "Ed25519 via libsodium" begin
    kp = generate_keypair()
    @test length(kp.pk) == 32
    @test length(kp.sk) == 64

    msg = UInt8[0x01, 0x02, 0x03, 0x04]
    sig = sign_detached(kp, msg)
    @test length(sig) == 64
    @test verify_detached(kp.pk, sig, msg)

    # Tampered message fails.
    bad_msg = vcat(msg, UInt8[0xFF])
    @test !verify_detached(kp.pk, sig, bad_msg)

    # Tampered signature fails.
    bad_sig = copy(sig); bad_sig[1] ⊻= 0xFF
    @test !verify_detached(kp.pk, bad_sig, msg)
end

@testset "Attestation round-trip (real Ed25519)" begin
    store = Store()
    id = make_id(0x02)
    enrich!(store, id, :semantic, make_blob("att"), "alice")

    result = attest(store, id)
    @test result !== nothing
    oc, sig, t = result
    @test length(sig.key_id) == 32    # Ed25519 pubkey
    @test length(sig.sig_bytes) == 64 # Ed25519 sig
    @test verify_attest(store, oc, sig, t)

    # Tamper sig → verify_attest fails.
    tampered = Signature(sig.key_id, vcat(sig.sig_bytes[2:end], UInt8[0x00]))
    @test !verify_attest(store, oc, tampered, t)
end

# -----------------------------------------------------------------------
# Federation parity (Path B critical gate)
# -----------------------------------------------------------------------

function monolithic_agg(shape_values::Dict{Symbol, Any}, weights::DriftWeights)
    acc = 0.0
    for ((a, b), w) in weights.pair_weights
        va = get(shape_values, a, nothing)
        vb = get(shape_values, b, nothing)
        (va === nothing || vb === nothing) && continue
        acc += w * drift(a, va, b, vb)
    end
    acc
end

@testset "Federation parity: (S,V) single peer" begin
    id = make_id(0x10)
    blob = make_blob("p"); emb = make_emb("p")
    weights = DriftWeights((:semantic, :vector) => 1.0)

    mono = monolithic_agg(Dict{Symbol, Any}(:semantic => blob, :vector => emb), weights)

    store = Store(); enrich!(store, id, :semantic, blob, "a")
    peer = VectorPeer(); put_embedding!(peer, id, emb)
    mgr = Manager(); register_peer!(mgr, :vector, peer)

    core_values = Dict{Symbol, Any}(:semantic => get_core(store, id).semantic)
    fed = aggregate_drift(core_values, mgr, id, weights)
    @test mono ≈ fed
    @test mono > 0
end

@testset "Federation parity: (S,V,D) two peers" begin
    id = make_id(0x11)
    blob = make_blob("t"); emb = make_emb("t"); doc = make_doc("t")
    weights = DriftWeights(
        (:semantic, :vector)   => 0.4,
        (:semantic, :document) => 0.3,
        (:vector,   :document) => 0.3,
    )

    mono = monolithic_agg(Dict{Symbol, Any}(
        :semantic => blob, :vector => emb, :document => doc), weights)

    store = Store(); enrich!(store, id, :semantic, blob, "a")
    vp = VectorPeer(); put_embedding!(vp, id, emb)
    dp = DocumentPeer(); put_document!(dp, id, doc)
    mgr = Manager()
    register_peer!(mgr, :vector, vp)
    register_peer!(mgr, :document, dp)

    core_values = Dict{Symbol, Any}(:semantic => get_core(store, id).semantic)
    fed = aggregate_drift(core_values, mgr, id, weights)
    @test mono ≈ fed
end

# -----------------------------------------------------------------------
# Classification + IsFederable runtime validation
# -----------------------------------------------------------------------

@testset "register_peer! rejects Core shapes" begin
    mgr = Manager(); peer = VectorPeer()
    @test_throws ErrorException register_peer!(mgr, :semantic, peer)
    @test_throws ErrorException register_peer!(mgr, :temporal, peer)
    @test_throws ErrorException register_peer!(mgr, :provenance, peer)

    register_peer!(mgr, :vector, peer)
    @test :vector in registered_shapes(mgr)
end

@testset "Classification sets partition 8 shapes" begin
    @test CORE_SHAPES        == Set([:semantic, :temporal, :provenance])
    @test FEDERABLE_SHAPES   == Set([:vector, :tensor, :document, :spatial])
    @test CONDITIONAL_SHAPES == Set([:graph])
    @test length(union(CORE_SHAPES, FEDERABLE_SHAPES, CONDITIONAL_SHAPES)) == 8
end

# -----------------------------------------------------------------------
# Renormalisation
# -----------------------------------------------------------------------

@testset "Clause 1: renormalise preserves Σ=1 over present pairs" begin
    w = DriftWeights(
        (:semantic, :vector)   => 0.5,
        (:graph, :document)    => 0.3,
        (:vector, :document)   => 0.2,
    )
    r = renormalise([:semantic, :vector], w)
    @test sum(values(r.pair_weights)) ≈ 1.0
    @test length(r.pair_weights) == 1

    r2 = renormalise([:semantic, :vector, :document], w)
    @test sum(values(r2.pair_weights)) ≈ 1.0
    @test r2.pair_weights[(:semantic, :vector)] ≈ 5/7
    @test r2.pair_weights[(:document, :vector)] ≈ 2/7
end

# -----------------------------------------------------------------------
# VCL subset
# -----------------------------------------------------------------------

@testset "VCL: PROOF INTEGRITY + tampered chain" begin
    store = Store(); id = make_id(0x20)
    enrich!(store, id, :semantic, make_blob("i1"), "a")
    enrich!(store, id, :semantic, make_blob("i2"), "b")

    @test prove(ProofIntegrity(id), store, Manager()) isa VerdictPass

    # Tamper middle entry's this_hash.
    oc = get_core(store, id)
    oc.provenance.entries[1] = ProvenanceEntry(
        oc.provenance.entries[1].prev_hash,
        zeros(UInt8, 32),
        oc.provenance.entries[1].actor,
        oc.provenance.entries[1].timestamp,
        oc.provenance.entries[1].signature)
    @test prove(ProofIntegrity(id), store, Manager()) isa VerdictFail
end

@testset "VCL: PROOF CONSISTENCY with DRIFT threshold" begin
    store = Store(); id = make_id(0x21)
    enrich!(store, id, :semantic, make_blob("c"), "a")
    peer = VectorPeer(); put_embedding!(peer, id, make_emb("c"))
    mgr = Manager(); register_peer!(mgr, :vector, peer)

    weights = DriftWeights((:semantic, :vector) => 1.0)
    c_loose = ProofConsistency(id, [:semantic, :vector], 10.0, weights)
    @test prove(c_loose, store, mgr) isa VerdictPass
    c_tight = ProofConsistency(id, [:semantic, :vector], 0.01, weights)
    @test prove(c_tight, store, mgr) isa VerdictFail
end

@testset "VCL: parse_vcl string round-trip" begin
    q1 = parse_vcl("PROOF INTEGRITY FOR " * repeat("ab", 16))
    @test q1 isa ProofIntegrity
    q2 = parse_vcl("PROOF CONSISTENCY FOR " * repeat("cd", 16) *
                   " OVER {semantic, vector} WITH DRIFT < 0.5")
    @test q2 isa ProofConsistency
    @test q2.threshold == 0.5
    @test q2.scope == [:semantic, :vector]
    q3 = parse_vcl("PROOF FRESHNESS FOR " * repeat("ef", 16) * " WITHIN 1000000000ns")
    @test q3 isa ProofFreshness
    @test q3.window_ns == 1_000_000_000
end

@testset "VCL: parser errors on bad input" begin
    @test_throws ErrorException parse_vcl("SELECT * FROM octads")
    @test_throws ErrorException parse_vcl("PROOF INTEGRITY")
    @test_throws ErrorException parse_vcl("PROOF FOO FOR " * repeat("00", 16))
end

# -----------------------------------------------------------------------
# Non-interference (N=2 peers)
# -----------------------------------------------------------------------

@testset "Non-interference: 2 peers, independent keypairs" begin
    vp = VectorPeer(); dp = DocumentPeer()
    @test public_key(vp) != public_key_doc(dp)
    @test length(public_key(vp)) == 32
    @test length(public_key_doc(dp)) == 32
end

@testset "Non-interference: (S,V) drift invariant under adding Document" begin
    id = make_id(0x30)
    blob = make_blob("n"); emb = make_emb("n"); doc = make_doc("n")
    store = Store(); enrich!(store, id, :semantic, blob, "a")
    vp = VectorPeer(); put_embedding!(vp, id, emb)

    mgr_solo = Manager(); register_peer!(mgr_solo, :vector, vp)
    core_values = Dict{Symbol, Any}(:semantic => get_core(store, id).semantic)
    weights_sv = DriftWeights((:semantic, :vector) => 1.0)
    solo = aggregate_drift(core_values, mgr_solo, id, weights_sv)

    dp = DocumentPeer(); put_document!(dp, id, doc)
    mgr_both = Manager()
    register_peer!(mgr_both, :vector, vp)
    register_peer!(mgr_both, :document, dp)
    both = aggregate_drift(core_values, mgr_both, id, weights_sv)
    @test solo ≈ both
end
