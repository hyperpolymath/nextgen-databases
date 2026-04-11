# SPDX-License-Identifier: PMPL-1.0-or-later
#
# vcl/Query.jl — minimal VCL AST for the subset the experiment needs.
#
# Target grammar (research subset):
#
#   PROOF INTEGRITY FOR <octad_id>
#   PROOF CONSISTENCY FOR <octad_id> WITH DRIFT < <double>
#   PROOF CONSISTENCY FOR <octad_id> OVER {s1,s2,...} WITH DRIFT < <double>
#   PROOF FRESHNESS FOR <octad_id> WITHIN <duration_ns>
#
# Queries are constructed as Julia values; a tiny string parser is in
# Parser.jl. Evaluation lives in Prover.jl.

module VCLQuery

export ProofClause, ProofIntegrity, ProofConsistency, ProofFreshness,
       ProofConsonance,
       ProofVerdict, VerdictPass, VerdictFail

# -----------------------------------------------------------------------
# AST types
# -----------------------------------------------------------------------

abstract type ProofClause end

"""
PROOF INTEGRITY FOR <id>

Asks: is the octad's Core state internally consistent — Identity
Persistence holds, hash chain verifies, latest attestation is valid?
Core-only; no federation queries.
"""
struct ProofIntegrity <: ProofClause
    octad_id::Any  # OctadId (duck-typed to avoid load order)
end

"""
PROOF CONSISTENCY FOR <id> [OVER {shapes}] WITH DRIFT < <threshold>

Asks: does aggregate drift across the given shape-scope stay below the
threshold? Scope defaults to all registered shapes. Weights must be
supplied; renormalisation happens if scope is reduced.
"""
struct ProofConsistency <: ProofClause
    octad_id::Any
    scope::Vector{Symbol}       # empty = all shapes
    threshold::Float64
    weights::Any                # DriftWeights (duck-typed)
end

"""
PROOF FRESHNESS FOR <id> WITHIN <window_ns>

Asks: has the octad been written-to (enriched) within the window?
Core-only (reads Temporal leaves).
"""
struct ProofFreshness <: ProofClause
    octad_id::Any
    window_ns::Int64
end

"""
PROOF CONSONANCE FOR <id_a> AND <id_b> [WITHIN <bound>]

Asks: do two octads represent equivalent tangles / knots / links?

Uses tropical matrix power (Bellman-Ford) to search for a Reidemeister
move path connecting the two tangle configurations.  A finite minimum
path weight proves consonance; ∞ means no path was found within the
modelled move set.

Formal backing:
  `bellman_ford` theorem — Tropical_Matrices_Full.thy
  See docs/TROPICAL-BRIDGE.adoc for the Isabelle ↔ Julia correspondence.

Fields:
  octad_id_a  — first  TangleIR octad
  octad_id_b  — second TangleIR octad
  depth       — Reidemeister BFS horizon (default 2)
"""
struct ProofConsonance <: ProofClause
    octad_id_a::Any
    octad_id_b::Any
    depth::Int
end
ProofConsonance(a, b) = ProofConsonance(a, b, 2)

# -----------------------------------------------------------------------
# Results
# -----------------------------------------------------------------------

abstract type ProofVerdict end

struct VerdictPass <: ProofVerdict
    witness::String     # human-readable evidence
end

struct VerdictFail <: ProofVerdict
    reason::String
end

Base.show(io::IO, v::VerdictPass) = print(io, "PASS: ", v.witness)
Base.show(io::IO, v::VerdictFail) = print(io, "FAIL: ", v.reason)

end # module
