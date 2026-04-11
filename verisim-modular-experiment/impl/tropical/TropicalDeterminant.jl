# SPDX-License-Identifier: PMPL-1.0-or-later
#
# TropicalDeterminant.jl — Julia mirror of Tropical_Determinants.thy
#
# Computes the tropical (min-plus) determinant of an n×n cost matrix:
#
#   tropm_det(A) = min over all permutations π of (∑ᵢ A[i, π(i)])
#
# where the inner ∑ is ordinary nat-addition (tropical multiplication)
# and the outer min is tropical addition. This equals the minimum-cost
# perfect matching in the n×n assignment problem.
#
# Formal backing: Tropical_Determinants.thy (Isabelle 2025-1)
#   theorem optimal_assignment
#   theorem optimal_assignment_bound
#
# Performance: brute-force over all n! permutations — suitable for n ≤ 8.
# For larger n, use the Hungarian algorithm (not yet implemented).
#
# Mirror fidelity:
#   perm_weightm(n, A, π)  ↔  definition perm_weightm in .thy
#   tropm_det(n, A)         ↔  definition tropm_det in .thy
#   optimal_assignment(n,A) ↔  theorem optimal_assignment in .thy

module TropicalDeterminant

using ..TropicalMatrix: Tropical, TROP_ZERO, TROP_ONE, trop_add, trop_mul

export perm_weightm, tropm_det, optimal_assignment, OptimalAssignmentResult

# ---------------------------------------------------------------------------
# perm_weightm: weight of a single permutation π on cost matrix A
# ---------------------------------------------------------------------------

"""
    perm_weightm(n, A, π) -> Tropical

The tropical product (= nat sum) of A[i, π(i)] for i ∈ {0, …, n-1}.

Mirrors: `definition perm_weightm` in Tropical_Determinants.thy
"""
function perm_weightm(n::Int, A::Matrix{Tropical}, π::Vector{Int})::Tropical
    weight = TROP_ONE   # identity for *, i.e., Fin'(0)
    for i in 1:n
        weight = trop_mul(weight, A[i, π[i]])
    end
    return weight
end

# ---------------------------------------------------------------------------
# tropm_det: tropical determinant = minimum-cost perfect matching
# ---------------------------------------------------------------------------

"""
    tropm_det(n, A) -> Tropical

Tropical determinant: min over all permutations π of {1,…,n} of perm_weightm(n, A, π).

Brute-force enumeration of all n! permutations. Suitable for n ≤ 8.

Mirrors: `definition tropm_det` in Tropical_Determinants.thy
"""
function tropm_det(n::Int, A::Matrix{Tropical})::Tropical
    n == 0 && return TROP_ONE   # empty product = 1 (zero rows)
    det = TROP_ZERO             # identity for +, i.e., PosInf
    # Generate all permutations of {1,…,n} (1-indexed to match Julia arrays)
    for π in _permutations(n)
        w = perm_weightm(n, A, π)
        det = trop_add(det, w)  # min
    end
    return det
end

# ---------------------------------------------------------------------------
# optimal_assignment: find a minimising permutation
# ---------------------------------------------------------------------------

"""
    OptimalAssignmentResult

Result of `optimal_assignment/2`:
- `permutation`: 1-indexed permutation vector achieving the minimum cost
- `cost`: minimum assignment cost (= tropm_det)
- `is_finite`: false if the matrix has no finite-cost perfect matching

Mirrors: `theorem optimal_assignment` in Tropical_Determinants.thy
"""
struct OptimalAssignmentResult
    permutation::Vector{Int}
    cost::Tropical
    is_finite::Bool
end

"""
    optimal_assignment(n, A) -> OptimalAssignmentResult

Find a minimum-cost perfect matching.

Formal guarantee (Tropical_Determinants.thy, theorem `optimal_assignment`):
  ∃ π. π permutes {..<n} ∧ tropm_det n A = perm_weightm n A π
       ∧ ∀ π'. π' permutes {..<n} → tropm_det n A ≤ perm_weightm n A π'
"""
function optimal_assignment(n::Int, A::Matrix{Tropical})::OptimalAssignmentResult
    if n == 0
        return OptimalAssignmentResult(Int[], TROP_ONE, true)
    end
    best_π    = collect(1:n)
    best_cost = TROP_ZERO   # PosInf — will be replaced on first iteration
    for π in _permutations(n)
        w = perm_weightm(n, A, π)
        # trop_add is min; if w < best_cost, update
        new_min = trop_add(best_cost, w)
        if new_min != best_cost || best_cost == TROP_ZERO
            best_cost = w
            best_π    = copy(π)
        end
    end
    is_finite = isfinite(best_cost.val)
    return OptimalAssignmentResult(best_π, best_cost, is_finite)
end

"""
    is_within_bound(n, A, bound) -> Bool

Check whether the optimal assignment cost ≤ bound.

Mirrors: corollary `optimal_assignment_bound` in Tropical_Determinants.thy:
  (∃ π. π permutes {..<n} ∧ perm_weightm n A π ≤ B) ↔ tropm_det n A ≤ B
"""
function is_within_bound(n::Int, A::Matrix{Tropical}, bound::Tropical)::Bool
    cost = tropm_det(n, A)
    # In min-plus: a ≤ b iff trop_add(a, b) = a (min(a,b) = a)
    return trop_add(cost, bound) == cost || cost == bound
end

# ---------------------------------------------------------------------------
# Private: permutation generator (Heap's algorithm, 1-indexed)
# ---------------------------------------------------------------------------

function _permutations(n::Int)
    perms = Vector{Vector{Int}}()
    _heap_perms!(collect(1:n), n, perms)
    return perms
end

function _heap_perms!(a::Vector{Int}, k::Int, out::Vector{Vector{Int}})
    if k == 1
        push!(out, copy(a))
        return
    end
    _heap_perms!(a, k - 1, out)
    for i in 1:(k - 1)
        if k % 2 == 0
            a[i], a[k] = a[k], a[i]
        else
            a[1], a[k] = a[k], a[1]
        end
        _heap_perms!(a, k - 1, out)
    end
end

end # module TropicalDeterminant
