------------------------------- MODULE Normalizer -------------------------------
\* SPDX-License-Identifier: PMPL-1.0-or-later
\* Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
\*
\* V9: Normalizer determinism + convergence.
\* Corresponds to rust-core/verisim-normalizer/src/lib.rs (StorageRegenerator).
\*
\* The verisim-normalizer resolves drift between the 8 modalities of an octad
\* by picking an authoritative source modality and regenerating the others
\* from it. The real system has a (source, target) strategy table -- Document
\* is the usual authoritative source for Vector/Semantic/Graph regeneration,
\* with cosine-similarity drift measured against Vector and Jaccard against
\* Semantic. This spec abstracts that machinery into its essential claim:
\*
\*   - Determinism: normalisation is a *function* of state. Given the same
\*     input octad, normalisation always produces the same output octad;
\*     there is no schedule-dependent or source-rank-tie non-determinism.
\*   - Convergence: starting from any drift-ed state, repeated normalisation
\*     reaches a drift-free fixed point in bounded time.
\*
\* The spec also checks that the fixed point is *stable* (Normalize is
\* identity on a drift-free state).

EXTENDS Naturals, FiniteSets, TLC

CONSTANTS
    Values,         \* abstract set of possible modality payload hashes
    MaxSteps        \* bound on normalisation rounds for model-checking

\* Modalities and their deterministic priority ordering are module-level (TLC
\* config files cannot represent record literals, and the real system has a
\* fixed strategy table anyway). Priority is strictly injective by
\* construction here -- that injectivity is exactly what makes the CHOOSE in
\* SourceOf deterministic, and it is the spec's central structural claim.
Modalities == {"graph", "vector", "semantic", "document"}

Priority == [graph |-> 1, vector |-> 2, semantic |-> 3, document |-> 4]

ASSUME Cardinality(Values) >= 1
ASSUME MaxSteps \in Nat
ASSUME \A m1, m2 \in Modalities: (m1 /= m2) => (Priority[m1] /= Priority[m2])

VARIABLES
    state,          \* [Modalities -> Values] -- current octad snapshot
    steps           \* Nat -- normalisation rounds elapsed

vars == <<state, steps>>

TypeOK ==
    /\ state \in [Modalities -> Values]
    /\ steps \in 0..MaxSteps

\* Drift holds when any two modalities disagree on the payload.
HasDrift(s) ==
    \E m1, m2 \in Modalities: s[m1] /= s[m2]

\* The deterministic authoritative-source function. Under the injectivity
\* ASSUME above, CHOOSE returns the unique highest-priority modality. This
\* is the single piece of the spec that, if wrong, would make the whole
\* normaliser non-deterministic -- so it is the thing determinism hinges on.
SourceOf(s) ==
    CHOOSE m \in Modalities:
        \A other \in Modalities: Priority[m] >= Priority[other]

\* The normaliser: rewrite every modality to the source's value.
Normalize(s) ==
    [m \in Modalities |-> s[SourceOf(s)]]

\* Non-deterministic initial state; all octads are possible starting points
\* for the model-check.
Init ==
    /\ state \in [Modalities -> Values]
    /\ steps = 0

\* One round of normalisation. Guard by HasDrift so converged states are
\* stuttering; guard by MaxSteps for finite model-check.
Step ==
    /\ steps < MaxSteps
    /\ HasDrift(state)
    /\ state' = Normalize(state)
    /\ steps' = steps + 1

Next == Step

\* Weak fairness forces Step to fire while drift remains, which is what makes
\* Convergence true. Without it, the system could stutter forever in a drifted
\* state (that would be a real bug in the implementation, not the spec).
Spec == Init /\ [][Next]_vars /\ WF_vars(Step)

--------------------------------------------------------------------------------
\* Safety
--------------------------------------------------------------------------------

\* I1. SourceOf is well-defined: the CHOOSE always returns an element of
\* Modalities, and that element is the unique priority-maximum. Trivial from
\* the ASSUME, but stated explicitly so TLC exercises it on every state.
SourceIsMaximal ==
    \A other \in Modalities:
        Priority[SourceOf(state)] >= Priority[other]

\* I2. Idempotence of Normalize: normalising a normalised state is a no-op.
\* This is a property of the *definition* of Normalize; TLC checks it across
\* all reachable states including the non-deterministic Init.
NormalizeIdempotent ==
    Normalize(Normalize(state)) = Normalize(state)

\* I3. Post-Step drift-free: immediately after Step, no drift remains.
\* Implementation: Step replaces state with Normalize(state), which makes
\* every modality equal to state[SourceOf(state)] -- so any two modalities
\* agree, i.e. ~HasDrift. TLC verifies by exploring.
PostStepNoDrift ==
    (steps > 0) => ~HasDrift(state)

\* I4. Stability of fixed point: in any drift-free state, Normalize is the
\* identity. This is the "once converged, stay converged" guarantee.
FixedPointStable ==
    ~HasDrift(state) => (Normalize(state) = state)

NormalizerSafe ==
    /\ TypeOK
    /\ SourceIsMaximal
    /\ NormalizeIdempotent
    /\ PostStepNoDrift
    /\ FixedPointStable

--------------------------------------------------------------------------------
\* Liveness / convergence
--------------------------------------------------------------------------------

\* Eventually, drift is gone and stays gone. Stronger than "eventually no
\* drift" because the system could in principle re-drift if Step non-
\* deterministically reintroduced disagreement -- the <>[] form forbids that.
Convergence ==
    <>[]~HasDrift(state)

THEOREM NormalizerSafety == Spec => []NormalizerSafe
THEOREM NormalizerConverges == Spec => Convergence

================================================================================
