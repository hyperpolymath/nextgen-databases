# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
"""
    Verisim

Julia package wrapper for the VeriSim identity-core research prototype.

Exports the full VCL proof API (prove, parse_vcl), the VerisimCore store
(enrich!, get_core, Store, Manager), and the tropical geometry types
(Tropical, TropicalMatrix, TangleGraph).

# Design note — flat-include scaffold preserved
The implementation lives in `impl/` as a set of independent modules that
cross-reference each other via `Main.X` (the "flat-include scaffold" pattern).
On package load, `__init__` injects each module into `Main` in dependency
order, preserving all `Main.X` references without modifying any impl file.

This is intentional for the research prototype phase.  A future
`Verisim v0.2` refactor will move each impl module into `src/` with proper
relative imports (`using ..Sibling`), removing the `Main` injection.
See `PLAN.adoc §Phase-6-Package-Refactor`.

# Usage
```julia
using Verisim

store   = Verisim.Store()
manager = Verisim.Manager()
id      = Verisim.OctadId(fill(0x01, 16))
blob    = Verisim.SemanticBlob(["http://example.org/Doc"], b"hello")

Verisim.enrich!(store, id, :semantic, blob, "alice")

v = Verisim.prove(Verisim.ProofIntegrity(id), store, manager)
println(v)  # VerdictPass(...)
```
"""
module Verisim

# -----------------------------------------------------------------------
# Impl load order — must match the manual include order in test files and
# examples.  Each file defines its own module which __init__ injects into
# Main so that all existing Main.X cross-references continue to work.
# -----------------------------------------------------------------------

const _IMPL = joinpath(@__DIR__, "..", "impl")

const _IMPL_FILES = [
    joinpath(_IMPL, "Crypto.jl"),
    joinpath(_IMPL, "drift", "Metrics.jl"),
    joinpath(_IMPL, "VerisimCore.jl"),
    joinpath(_IMPL, "peers", "VectorPeer.jl"),
    joinpath(_IMPL, "FederationManager.jl"),
    joinpath(_IMPL, "tropical", "TropicalMatrix.jl"),
    joinpath(_IMPL, "tropical", "TangleGraph.jl"),
    joinpath(_IMPL, "tropical", "TropicalDeterminant.jl"),
    joinpath(_IMPL, "vcl", "Query.jl"),
    joinpath(_IMPL, "vcl", "Prover.jl"),
    joinpath(_IMPL, "vcl", "Parser.jl"),
]

"""
    __init__()

Load all impl modules into `Main` in dependency order.  Called automatically
by Julia when `using Verisim` is evaluated.
"""
function __init__()
    for f in _IMPL_FILES
        # Base.include(Main, f) loads the file in the Main module context,
        # making each defined module accessible as Main.<ModuleName>.
        Base.include(Main, f)
    end
end

# -----------------------------------------------------------------------
# Public API — thin delegators to the Main-level modules loaded by __init__
# -----------------------------------------------------------------------
#
# Struct types cannot be forwarded by reference at precompile time, so we
# expose factory functions and let users call the Main-level types directly
# when they need the actual types (e.g. for dispatch / isa checks).
# All functions are dispatched at call time via Main.<Module> to avoid
# precompile-time binding issues.

export prove, parse_vcl
export Store, Manager, OctadId, SemanticBlob
export enrich!, get_core
export ProofIntegrity, ProofConsistency, ProofFreshness, ProofConsonance,
       ProofOptimalAssignment
export VerdictPass, VerdictFail
export Tropical, TROP_ZERO, TROP_ONE, trop_add, trop_mul, bellman_ford_matrix

# VCL proof evaluation
prove(args...; kw...)       = Main.VCLProver.prove(args...; kw...)
parse_vcl(s::AbstractString) = Main.VCLParser.parse_vcl(s)

# Store lifecycle
Store()                     = Main.VerisimCore.Store()
Manager()                   = Main.FederationManager.Manager()
OctadId(b)                  = Main.VerisimCore.OctadId(b)
SemanticBlob(types, bytes)  = Main.VerisimCore.SemanticBlob(types, bytes)
enrich!(args...)            = Main.VerisimCore.enrich!(args...)
get_core(args...)           = Main.VerisimCore.get_core(args...)

# VCL clause constructors
ProofIntegrity(id)                  = Main.VCLQuery.ProofIntegrity(id)
ProofConsistency(args...)           = Main.VCLQuery.ProofConsistency(args...)
ProofFreshness(id, window)          = Main.VCLQuery.ProofFreshness(id, window)
ProofConsonance(args...)            = Main.VCLQuery.ProofConsonance(args...)
ProofOptimalAssignment(id, n, b)    = Main.VCLQuery.ProofOptimalAssignment(id, n, b)

# Tropical types
Tropical(x)                 = Main.TropicalMatrix.Tropical(x)
TROP_ZERO()                 = Main.TropicalMatrix.TROP_ZERO
TROP_ONE()                  = Main.TropicalMatrix.TROP_ONE
trop_add(a, b)              = Main.TropicalMatrix.trop_add(a, b)
trop_mul(a, b)              = Main.TropicalMatrix.trop_mul(a, b)
bellman_ford_matrix(A)      = Main.TropicalMatrix.bellman_ford_matrix(A)

end # module Verisim
