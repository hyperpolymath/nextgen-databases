# SPDX-License-Identifier: PMPL-1.0-or-later
#
# vcl/Prover.jl — evaluator for VCL PROOF clauses.
#
# Routes each clause through VerisimCore + FederationManager primitives.
# Returns a ProofVerdict (VerdictPass/VerdictFail) with human-readable
# witness/reason strings.

module VCLProver

import ..Core
import ..Federation
import ..VCLQuery

using Printf

export prove

# -----------------------------------------------------------------------
# prove(clause, store, manager) — main dispatcher
# -----------------------------------------------------------------------

"""
    prove(clause, store, manager; now=current_time) -> ProofVerdict

Evaluate a VCL PROOF clause against the given Core store and federation
manager. Returns VerdictPass on success with a witness string, or
VerdictFail on failure with a reason.
"""
function prove(clause::VCLQuery.ProofIntegrity, store, manager)
    octad = Core.get_core(store, clause.octad_id)
    octad === nothing && return VCLQuery.VerdictFail(
        "octad not found in Core store")

    octad.temporal === nothing && return VCLQuery.VerdictFail(
        "Temporal absent — Identity Persistence cannot hold")
    octad.provenance === nothing && return VCLQuery.VerdictFail(
        "Provenance absent — enrichment invariant violated")

    entries = octad.provenance.entries
    leaves  = octad.temporal.leaves

    # Enrichment atomicity: |T.leaves| must equal |R.entries| for each
    # completed enrichment (1 leaf + 1 entry per call).
    length(leaves) == length(entries) || return VCLQuery.VerdictFail(
        "enrichment atomicity violated: $(length(leaves)) leaves vs " *
        "$(length(entries)) provenance entries")

    # Hash-chain integrity: each entry's prev_hash matches previous's this_hash.
    for i in 2:length(entries)
        entries[i].prev_hash == entries[i-1].this_hash || return VCLQuery.VerdictFail(
            "hash chain broken at entry $i")
    end

    # Signature verification on the latest entry.
    if !isempty(entries)
        latest = entries[end]
        Core.ed25519_verify(latest.signature, latest.this_hash) ||
            return VCLQuery.VerdictFail("latest signature failed Ed25519 verification")
    end

    n = length(entries)
    VCLQuery.VerdictPass(
        "$(n) enrichment(s), hash chain intact, latest signature valid")
end

function prove(clause::VCLQuery.ProofConsistency, store, manager)
    octad = Core.get_core(store, clause.octad_id)
    octad === nothing && return VCLQuery.VerdictFail(
        "octad not found in Core store")

    # Scope: explicit or all-present.
    present_shapes = Symbol[]
    octad.semantic   !== nothing && push!(present_shapes, :semantic)
    octad.temporal   !== nothing && push!(present_shapes, :temporal)
    octad.provenance !== nothing && push!(present_shapes, :provenance)
    for s in Federation.registered_shapes(manager)
        push!(present_shapes, s)
    end

    scope = isempty(clause.scope) ? present_shapes : clause.scope

    # Only keep pairs where both shapes are in scope.
    weights_scoped = Federation.renormalise(scope, clause.weights)

    # Build core_values for the scoped evaluation.
    core_values = Dict{Symbol, Any}()
    if :semantic in scope && octad.semantic !== nothing
        core_values[:semantic] = octad.semantic
    end

    agg = Federation.aggregate_drift(
        core_values, manager, clause.octad_id, weights_scoped)

    if agg < clause.threshold
        return VCLQuery.VerdictPass(@sprintf(
            "aggregate drift %.4f < threshold %.4f over scope %s",
            agg, clause.threshold, string(scope)))
    else
        return VCLQuery.VerdictFail(@sprintf(
            "aggregate drift %.4f ≥ threshold %.4f over scope %s",
            agg, clause.threshold, string(scope)))
    end
end

function prove(clause::VCLQuery.ProofFreshness, store, manager)
    octad = Core.get_core(store, clause.octad_id)
    octad === nothing && return VCLQuery.VerdictFail(
        "octad not found in Core store")
    octad.temporal === nothing && return VCLQuery.VerdictFail(
        "Temporal absent")
    isempty(octad.temporal.leaves) && return VCLQuery.VerdictFail(
        "no mutations recorded")

    latest = octad.temporal.leaves[end]
    now    = Core.now_ts()
    age    = now.epoch_nanos - latest.epoch_nanos

    if 0 <= age <= clause.window_ns
        return VCLQuery.VerdictPass(@sprintf(
            "latest mutation %d ns ago (window %d ns)", age, clause.window_ns))
    elseif age < 0
        return VCLQuery.VerdictFail(
            "latest mutation is in the future (clock skew?)")
    else
        return VCLQuery.VerdictFail(@sprintf(
            "latest mutation %d ns ago exceeds window %d ns", age, clause.window_ns))
    end
end

end # module
