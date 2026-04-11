# SPDX-License-Identifier: PMPL-1.0-or-later
#
# impl/tropical/TropicalMatrix.jl — min-plus tropical semiring and matrix power.
#
# Implements the min-plus tropical semiring (tropical_min in Isabelle) and the
# key matrix-power theorems proved in tropical-resource-typing/:
#
#   tropm_mat_pow_eq_sum_walks  — A^k[i,j] = ⊕_{w ∈ walks k i j} path_weight A w
#   bellman_ford               — (I ⊕ A)^{n-1}[i,j] = min simple-path weight
#
# This is the executable counterpart to those Isabelle proofs. The formal
# specification bridge is in docs/TROPICAL-BRIDGE.adoc.
#
# Notation guide (Isabelle ↔ Julia):
#   PosInf          ↔  TROP_ZERO  (additive identity:  a ⊕ ∞ = a)
#   Fin' 0          ↔  TROP_ONE   (multiplicative id:  a ⊗ 0 = a in ℕ)
#   a ⊕ b = min     ↔  trop_add(a, b)
#   a ⊗ b = a + b   ↔  trop_mul(a, b)
#   tropm_mat_mul   ↔  trop_mat_mul
#   tropm_mat_pow   ↔  trop_mat_pow
#   tropm_mat_close ↔  trop_mat_close

module TropicalMatrix

export Tropical, TROP_ZERO, TROP_ONE,
       trop_add, trop_mul,
       trop_mat_id, trop_mat_mul, trop_mat_close, trop_mat_pow,
       bellman_ford_matrix

# -----------------------------------------------------------------------
# The min-plus tropical semiring
# -----------------------------------------------------------------------

"""
    Tropical

Element of the min-plus tropical semiring (ℕ ∪ {+∞}).

`val = Inf`  →  PosInf (additive identity in Isabelle: `zero_tropical_min`)
`val = 0.0`  →  Fin' 0 (multiplicative identity: `one_tropical_min`)

Isabelle correspondence: `tropical_min` type in `Tropical_v2.thy`.
"""
struct Tropical
    val::Float64
end

"""Additive identity (∞ = PosInf). Isabelle: `zero_tropical_min_def`."""
const TROP_ZERO = Tropical(Inf)

"""Multiplicative identity (0 = Fin' 0). Isabelle: `one_tropical_min_def`."""
const TROP_ONE  = Tropical(0.0)

Base.isfinite(t::Tropical)           = isfinite(t.val)
Base.:(==)(a::Tropical, b::Tropical) = a.val == b.val
Base.isless(a::Tropical, b::Tropical) = a.val < b.val
Base.show(io::IO, t::Tropical) =
    isinf(t.val) ? print(io, "∞") : print(io, "Fin'(", Int(t.val), ")")

"""
    trop_add(a, b) → min(a, b)

Tropical addition = min.
Isabelle: instance of `add` on `tropical_min`; `tropm_add_idem: a ⊕ a = a`.
"""
trop_add(a::Tropical, b::Tropical) = Tropical(min(a.val, b.val))

"""
    trop_mul(a, b) → a + b  (or ∞ if either is ∞)

Tropical multiplication = arithmetic addition.
Isabelle: instance of `mul` on `tropical_min`;
absorbing element: `∞ ⊗ x = ∞`.
"""
function trop_mul(a::Tropical, b::Tropical)::Tropical
    (isinf(a.val) || isinf(b.val)) ? TROP_ZERO : Tropical(a.val + b.val)
end

# -----------------------------------------------------------------------
# Matrix operations
# -----------------------------------------------------------------------

"""
    trop_mat_id(n) → n×n identity matrix

Diagonal entries = TROP_ONE, off-diagonal = TROP_ZERO.
Isabelle: `tropm_mat_id`.
"""
function trop_mat_id(n::Int)::Matrix{Tropical}
    M = fill(TROP_ZERO, n, n)
    for i in 1:n
        M[i, i] = TROP_ONE
    end
    M
end

"""
    trop_mat_mul(A, B) → C

Min-plus matrix multiplication.
  C[i,j] = ⊕_k (A[i,k] ⊗ B[k,j]) = min_k (A[i,k] + B[k,j])

Isabelle: `tropm_mat_mul n A B i j ≡ ∑ k ∈ {..<n}. A i k * B k j`.
"""
function trop_mat_mul(A::Matrix{Tropical}, B::Matrix{Tropical})::Matrix{Tropical}
    n = size(A, 1)
    @assert size(A) == size(B) == (n, n) "square matrices required"
    C = fill(TROP_ZERO, n, n)
    for i in 1:n, j in 1:n, k in 1:n
        C[i, j] = trop_add(C[i, j], trop_mul(A[i, k], B[k, j]))
    end
    C
end

"""
    trop_mat_close(A) → I ⊕ A

Entry-wise minimum with the identity matrix.
Isabelle: `tropm_mat_close n A i j ≡ A i j + tropm_mat_id n i j`.
"""
function trop_mat_close(A::Matrix{Tropical})::Matrix{Tropical}
    n = size(A, 1)
    I = trop_mat_id(n)
    [trop_add(I[i, j], A[i, j]) for i in 1:n, j in 1:n]
end

"""
    trop_mat_pow(A, k) → A^k

k-fold min-plus matrix product.  A^0 = I.
Isabelle: `tropm_mat_pow n A k` (right-iterated).
"""
function trop_mat_pow(A::Matrix{Tropical}, k::Int)::Matrix{Tropical}
    k == 0 && return trop_mat_id(size(A, 1))
    k == 1 && return A
    result = A
    for _ in 2:k
        result = trop_mat_mul(result, A)
    end
    result
end

"""
    bellman_ford_matrix(A) → (I ⊕ A)^{n-1}

All-pairs shortest-path matrix for an n-vertex graph, bounded by
walks of length ≤ n-1.

Formal guarantee (pending `bellman_ford` sorry closure in
Tropical_Matrices_Full.thy, under `no_neg_cycle n A`):

  bellman_ford_matrix(A)[i,j]  =  min weight over all simple walks i→j

A finite entry means i and j are connected; PosInf (TROP_ZERO) means
no path exists within the graph.

Isabelle:
  `bellman_ford: tropm_mat_pow n (tropm_mat_close n A) (n-1) i j
               = tropm_walks_sum A (simple_walksm n i j)`
"""
function bellman_ford_matrix(A::Matrix{Tropical})::Matrix{Tropical}
    n = size(A, 1)
    n == 0 && return trop_mat_id(0)
    trop_mat_pow(trop_mat_close(A), n - 1)
end

end # module TropicalMatrix
