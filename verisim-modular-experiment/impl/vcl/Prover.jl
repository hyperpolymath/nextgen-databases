# SPDX-License-Identifier: PMPL-1.0-or-later
#
# vcl/Prover.jl — evaluator for VCL PROOF clauses.
#
# Routes each clause through VerisimCore + FederationManager primitives.
# Returns a ProofVerdict (VerdictPass/VerdictFail) with human-readable
# witness/reason strings.

module VCLProver

using Printf

export prove

# TropicalMatrix and TangleGraph are loaded by the including script
# before this module, so they are reachable via Main.TropicalMatrix
# and Main.TangleGraph.

# -----------------------------------------------------------------------
# prove(clause, store, manager) — main dispatcher
# -----------------------------------------------------------------------

"""
    prove(clause, store, manager; now=current_time) -> ProofVerdict

Evaluate a VCL PROOF clause against the given Core store and federation
manager. Returns VerdictPass on success with a witness string, or
VerdictFail on failure with a reason.
"""
function prove(clause::Main.VCLQuery.ProofIntegrity, store, manager)
    octad = Main.VerisimCore.get_core(store, clause.octad_id)
    octad === nothing && return Main.VCLQuery.VerdictFail(
        "octad not found in Core store")

    octad.temporal === nothing && return Main.VCLQuery.VerdictFail(
        "Temporal absent — Identity Persistence cannot hold")
    octad.provenance === nothing && return Main.VCLQuery.VerdictFail(
        "Provenance absent — enrichment invariant violated")

    entries = octad.provenance.entries
    leaves  = octad.temporal.leaves

    # Enrichment atomicity: |T.leaves| must equal |R.entries| for each
    # completed enrichment (1 leaf + 1 entry per call).
    length(leaves) == length(entries) || return Main.VCLQuery.VerdictFail(
        "enrichment atomicity violated: $(length(leaves)) leaves vs " *
        "$(length(entries)) provenance entries")

    # Hash-chain integrity: each entry's prev_hash matches previous's this_hash.
    for i in 2:length(entries)
        entries[i].prev_hash == entries[i-1].this_hash || return Main.VCLQuery.VerdictFail(
            "hash chain broken at entry $i")
    end

    # Signature verification on the latest entry.
    if !isempty(entries)
        latest = entries[end]
        Main.VerisimCore.ed25519_verify(latest.signature, latest.this_hash) ||
            return Main.VCLQuery.VerdictFail("latest signature failed Ed25519 verification")
    end

    n = length(entries)
    Main.VCLQuery.VerdictPass(
        "$(n) enrichment(s), hash chain intact, latest signature valid")
end

function prove(clause::Main.VCLQuery.ProofConsistency, store, manager)
    octad = Main.VerisimCore.get_core(store, clause.octad_id)
    octad === nothing && return Main.VCLQuery.VerdictFail(
        "octad not found in Core store")

    # Scope: explicit or all-present.
    present_shapes = Symbol[]
    octad.semantic   !== nothing && push!(present_shapes, :semantic)
    octad.temporal   !== nothing && push!(present_shapes, :temporal)
    octad.provenance !== nothing && push!(present_shapes, :provenance)
    for s in Main.FederationManager.registered_shapes(manager)
        push!(present_shapes, s)
    end

    scope = isempty(clause.scope) ? present_shapes : clause.scope

    # Only keep pairs where both shapes are in scope.
    weights_scoped = Main.FederationManager.renormalise(scope, clause.weights)

    # Build core_values for the scoped evaluation.
    core_values = Dict{Symbol, Any}()
    if :semantic in scope && octad.semantic !== nothing
        core_values[:semantic] = octad.semantic
    end

    agg = Main.FederationManager.aggregate_drift(
        core_values, manager, clause.octad_id, weights_scoped)

    if agg < clause.threshold
        return Main.VCLQuery.VerdictPass(@sprintf(
            "aggregate drift %.4f < threshold %.4f over scope %s",
            agg, clause.threshold, string(scope)))
    else
        return Main.VCLQuery.VerdictFail(@sprintf(
            "aggregate drift %.4f ≥ threshold %.4f over scope %s",
            agg, clause.threshold, string(scope)))
    end
end

function prove(clause::Main.VCLQuery.ProofFreshness, store, manager)
    octad = Main.VerisimCore.get_core(store, clause.octad_id)
    octad === nothing && return Main.VCLQuery.VerdictFail(
        "octad not found in Core store")
    octad.temporal === nothing && return Main.VCLQuery.VerdictFail(
        "Temporal absent")
    isempty(octad.temporal.leaves) && return Main.VCLQuery.VerdictFail(
        "no mutations recorded")

    latest = octad.temporal.leaves[end]
    now    = Main.VerisimCore.now_ts()
    age    = now.epoch_nanos - latest.epoch_nanos

    if 0 <= age <= clause.window_ns
        return Main.VCLQuery.VerdictPass(@sprintf(
            "latest mutation %d ns ago (window %d ns)", age, clause.window_ns))
    elseif age < 0
        return Main.VCLQuery.VerdictFail(
            "latest mutation is in the future (clock skew?)")
    else
        return Main.VCLQuery.VerdictFail(@sprintf(
            "latest mutation %d ns ago exceeds window %d ns", age, clause.window_ns))
    end
end


# -----------------------------------------------------------------------
# PROOF CONSONANCE — tropical Bellman-Ford tangle equivalence check
# -----------------------------------------------------------------------

function prove(clause::Main.VCLQuery.ProofConsonance, store, manager)
    # Trivial case: same octad
    clause.octad_id_a == clause.octad_id_b &&
        return Main.VCLQuery.VerdictPass(
            "same octad id — trivially consonant")

    # Fetch both octads
    oct_a = Main.VerisimCore.get_core(store, clause.octad_id_a)
    oct_a === nothing && return Main.VCLQuery.VerdictFail(
        "octad A not found in Core store")
    oct_b = Main.VerisimCore.get_core(store, clause.octad_id_b)
    oct_b === nothing && return Main.VCLQuery.VerdictFail(
        "octad B not found in Core store")

    # Require Semantic shapes (DT code is in proof_bytes)
    oct_a.semantic === nothing && return Main.VCLQuery.VerdictFail(
        "octad A has no Semantic shape — cannot extract tangle structure")
    oct_b.semantic === nothing && return Main.VCLQuery.VerdictFail(
        "octad B has no Semantic shape — cannot extract tangle structure")

    # Decode DT codes
    dt_a = Main.TangleGraph.dt_codes_from_blob(oct_a.semantic.proof_bytes)
    dt_b = Main.TangleGraph.dt_codes_from_blob(oct_b.semantic.proof_bytes)

    isempty(dt_a) && return Main.VCLQuery.VerdictFail(
        "could not decode DT code from octad A semantic blob")
    isempty(dt_b) && return Main.VCLQuery.VerdictFail(
        "could not decode DT code from octad B semantic blob")

    # Fast path: identical DT codes → same knot type
    dt_a == dt_b &&
        return Main.VCLQuery.VerdictPass(
            "DT codes identical — consonant: $(dt_a)")

    # Tropical path search: build bounded Reidemeister graph and run
    # Bellman-Ford (min-plus matrix power) on it.
    #
    # Formal backing: `bellman_ford` in Tropical_Matrices_Full.thy proves
    # that (I ⊕ A)^{n-1}[i,j] equals the minimum walk weight over all
    # simple walks from i to j (under no-negative-cycle assumption).
    # Here: weight 1 per Reidemeister move, ∞ = unreachable.
    graph = Main.TangleGraph.build_consonance_graph(dt_a, dt_b;
                                                    depth = clause.depth)
    bfm   = Main.TropicalMatrix.bellman_ford_matrix(graph.matrix)

    # Reidemeister equivalence is symmetric: check both directions and take
    # the minimum.  bfm[1,2] = A→B, bfm[2,1] = B→A; either suffices.
    TM   = Main.TropicalMatrix
    cost = TM.trop_add(bfm[1, 2], bfm[2, 1])
    if isfinite(cost)
        n_moves = Int(cost.val)
        return Main.VCLQuery.VerdictPass(
            "Reidemeister path: $(n_moves) move(s) [tropical Bellman-Ford, " *
            "backed by Tropical_Matrices_Full.thy::bellman_ford]")
    else
        return Main.VCLQuery.VerdictFail(
            "no path found within depth=$(clause.depth) " *
            "[RI only; RII/RIII require KnotTheory.jl integration]")
    end
end

end # module
