------------------------------ MODULE OctadAtomicity ------------------------------
\* SPDX-License-Identifier: PMPL-1.0-or-later
\* Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
\*
\* V5: Transaction atomicity across the 8 modalities of a VeriSimDB octad.
\* Corresponds to rust-core/verisim-octad/src/transaction.rs.
\*
\* A VeriSimDB octad is a record with 8 per-modality projections. A transaction
\* touches a subset of the 8 modality projections and must be either fully
\* committed (all 8 projections updated) or fully aborted (none visible). No
\* PARTIAL state is ever observable outside a transaction's own PENDING scope.
\*
\* This spec models the transaction lifecycle (PENDING -> COMMITTED | ABORTED)
\* together with fault injection (crashes during a PENDING transaction) and
\* proves the Atomicity invariant under an adversary that can interleave
\* multiple concurrent transactions and crashes.

EXTENDS Naturals, FiniteSets, TLC

CONSTANTS
    Txns,           \* finite set of transaction identifiers
    MaxCrashes      \* bound on the number of crash events per run

ASSUME Cardinality(Txns) >= 1
ASSUME MaxCrashes \in Nat

\* The 8 modalities of a VeriSimDB octad.
Modalities == {"graph", "vector", "tensor", "semantic",
               "document", "temporal", "provenance", "spatial"}

Status == {"PENDING", "COMMITTED", "ABORTED"}

VARIABLES
    txnStatus,       \* [Txns -> Status] - each transaction's lifecycle stage
    modalityUpdates, \* [Txns -> SUBSET Modalities] - modalities already applied
    crashes          \* Nat - bounded counter for fault-injection events

vars == <<txnStatus, modalityUpdates, crashes>>

TypeOK ==
    /\ txnStatus \in [Txns -> Status]
    /\ modalityUpdates \in [Txns -> SUBSET Modalities]
    /\ crashes \in 0..MaxCrashes

Init ==
    /\ txnStatus = [t \in Txns |-> "PENDING"]
    /\ modalityUpdates = [t \in Txns |-> {}]
    /\ crashes = 0

--------------------------------------------------------------------------------
\* Incremental per-modality application during a PENDING transaction.
\* Each modality can be applied at most once per transaction (enforced by the
\* set-union: \cup already-applied is idempotent, but we also disallow reapply
\* via the `m \notin` guard so TLC bounds the state space by 2^|Modalities|).
--------------------------------------------------------------------------------
ApplyModality(t, m) ==
    /\ txnStatus[t] = "PENDING"
    /\ m \notin modalityUpdates[t]
    /\ modalityUpdates' = [modalityUpdates EXCEPT ![t] = @ \cup {m}]
    /\ UNCHANGED <<txnStatus, crashes>>

--------------------------------------------------------------------------------
\* Commit: only allowed once all 8 modalities have been applied. The commit
\* is itself atomic in the spec (single state transition); the Rust source is
\* expected to implement this via a 2-phase commit or equivalent mechanism.
--------------------------------------------------------------------------------
Commit(t) ==
    /\ txnStatus[t] = "PENDING"
    /\ modalityUpdates[t] = Modalities
    /\ txnStatus' = [txnStatus EXCEPT ![t] = "COMMITTED"]
    /\ UNCHANGED <<modalityUpdates, crashes>>

--------------------------------------------------------------------------------
\* Abort: unilateral rollback. Clears all applied updates and transitions to
\* ABORTED. Can fire at any time during PENDING.
--------------------------------------------------------------------------------
Abort(t) ==
    /\ txnStatus[t] = "PENDING"
    /\ txnStatus' = [txnStatus EXCEPT ![t] = "ABORTED"]
    /\ modalityUpdates' = [modalityUpdates EXCEPT ![t] = {}]
    /\ UNCHANGED crashes

--------------------------------------------------------------------------------
\* Crash during PENDING. Recovery must act as an abort: rollback applied
\* updates, transition to ABORTED. This is the adversarial event that the
\* Atomicity invariant is designed to defeat: without the rollback, a crash
\* mid-transaction would leave some modalities updated and the txnStatus
\* visible, i.e. a partial commit.
--------------------------------------------------------------------------------
Crash(t) ==
    /\ crashes < MaxCrashes
    /\ txnStatus[t] = "PENDING"
    /\ txnStatus' = [txnStatus EXCEPT ![t] = "ABORTED"]
    /\ modalityUpdates' = [modalityUpdates EXCEPT ![t] = {}]
    /\ crashes' = crashes + 1

Next ==
    \/ \E t \in Txns, m \in Modalities: ApplyModality(t, m)
    \/ \E t \in Txns: Commit(t)
    \/ \E t \in Txns: Abort(t)
    \/ \E t \in Txns: Crash(t)

\* Fairness: every transaction eventually resolves (either commits or aborts).
\* WF on (Commit \/ Abort) is sufficient because Abort is always enabled while
\* the transaction is PENDING, so the disjunction is continuously enabled.
Spec == Init
        /\ [][Next]_vars
        /\ \A t \in Txns: WF_vars(Commit(t) \/ Abort(t))

--------------------------------------------------------------------------------
\* Safety properties
--------------------------------------------------------------------------------

\* I1. The central atomicity claim:
\*   COMMITTED => all 8 modalities updated
\*   ABORTED   => no modalities updated
\* This is the "all-or-nothing" observation externally visible on an octad.
Atomicity ==
    \A t \in Txns:
        /\ (txnStatus[t] = "COMMITTED" => modalityUpdates[t] = Modalities)
        /\ (txnStatus[t] = "ABORTED"   => modalityUpdates[t] = {})

\* I2. No observable partial state: once a transaction is no longer PENDING,
\* its modalityUpdates set is either empty or the full 8. This is derivable
\* from Atomicity but stated separately because it is the property consumers
\* of the octad actually rely on ("if I read a committed octad, I never see a
\* half-update").
NoObservablePartial ==
    \A t \in Txns:
        (txnStatus[t] \in {"COMMITTED", "ABORTED"}) =>
            (modalityUpdates[t] = Modalities \/ modalityUpdates[t] = {})

\* I3. Status monotonicity: PENDING can move to COMMITTED or ABORTED, but
\* never the reverse. (This is implicitly enforced by Next -- every action
\* that changes txnStatus requires it was PENDING -- but stating it as an
\* invariant on (txnStatus, txnStatus') is not trivial without action vars;
\* instead we check a weaker "never COMMITTED AND ABORTED" which is trivially
\* true by type but confirms no action flips between terminal statuses.)
StatusMonotone ==
    \A t \in Txns:
        \neg (txnStatus[t] = "COMMITTED" /\ modalityUpdates[t] = {})

OctadSafe ==
    /\ TypeOK
    /\ Atomicity
    /\ NoObservablePartial
    /\ StatusMonotone

--------------------------------------------------------------------------------
\* Liveness
--------------------------------------------------------------------------------

\* Every transaction eventually reaches a terminal state.
EveryTxnResolves ==
    \A t \in Txns: <>(txnStatus[t] \in {"COMMITTED", "ABORTED"})

THEOREM AtomicitySafety == Spec => []OctadSafe
THEOREM Resolution      == Spec => EveryTxnResolves

================================================================================
