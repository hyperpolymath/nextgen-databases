---------------------------- MODULE Serializability ----------------------------
\* SPDX-License-Identifier: PMPL-1.0-or-later
\* Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
\*
\* V10: Conflict serializability for concurrent transactions on an octad.
\* Corresponds to rust-core/verisim-octad/src/transaction.rs (concurrent path).
\*
\* V5 proved atomicity for a single transaction under crashes. V10 extends
\* that to *multiple* concurrent transactions: the spec asserts that any
\* concurrent execution is conflict-equivalent to some serial execution of
\* the same transactions.
\*
\* Concurrency protocol modelled: atomic two-phase locking (2PL+atomic-acquire).
\*   - Each transaction has a fixed access-set (reads \cup writes) declared at
\*     design time (the TxnAccess constant).
\*   - Begin(t) atomically acquires the full access-set, or blocks.
\*   - Commit(t) releases locks and appends to the commit log.
\* This rules out deadlock by construction (atomic acquisition) and by the
\* same stroke makes the commit-log a valid serial schedule of the concurrent
\* execution. The spec's job is to verify both claims.

EXTENDS Naturals, FiniteSets, Sequences, TLC

\* Scenario is fixed at module level because TLC config files cannot express
\* record literals for TxnReads/TxnWrites, and this keeps a single-file spec
\* straightforwardly model-checkable. Alternative scenarios live as separate
\* .tla files.
\*
\* Scenario chosen: 3 transactions, 3 modalities, *partial* conflict graph.
\* This is deliberately richer than the all-pairs-conflict case, which would
\* trivially degenerate to a serial execution (at most 1 ACTIVE txn at any
\* time, so serializability is free). Here:
\*   - t1 reads {m1}, writes {m1}   -- disjoint from t2 (can run concurrently)
\*   - t2 reads {m2}, writes {m2}   -- disjoint from t1 (can run concurrently)
\*   - t3 reads {m1, m2}, writes {m3}  -- conflicts with BOTH t1 and t2
\*
\* Consequence: the reachable state graph contains states where t1 and t2
\* are simultaneously ACTIVE (real concurrency), but t3 must serialise
\* against each of them (real serialisation under 2PL). This scenario
\* genuinely exercises `NoConcurrentConflict` rather than trivially
\* satisfying it.

Txns == {"t1", "t2", "t3"}
Modalities == {"m1", "m2", "m3"}

TxnReads  == [t \in Txns |->
    CASE t = "t1" -> {"m1"}
      [] t = "t2" -> {"m2"}
      [] t = "t3" -> {"m1", "m2"}]

TxnWrites == [t \in Txns |->
    CASE t = "t1" -> {"m1"}
      [] t = "t2" -> {"m2"}
      [] t = "t3" -> {"m3"}]

ASSUME Cardinality(Txns) >= 2       \* serializability is trivial for 1 txn
ASSUME Cardinality(Modalities) >= 1
ASSUME TxnReads \in [Txns -> SUBSET Modalities]
ASSUME TxnWrites \in [Txns -> SUBSET Modalities]

\* A transaction's access-set is everything it reads or writes. 2PL acquires
\* the whole set atomically at Begin.
AccessSet(t) == TxnReads[t] \cup TxnWrites[t]

VARIABLES
    txnStatus,      \* [Txns -> {"IDLE", "ACTIVE", "COMMITTED"}]
    holdsLocks,     \* [Txns -> SUBSET Modalities] -- currently held
    commitLog       \* Seq(Txns) -- commit order (the serial schedule)

vars == <<txnStatus, holdsLocks, commitLog>>

Status == {"IDLE", "ACTIVE", "COMMITTED"}

TypeOK ==
    /\ txnStatus \in [Txns -> Status]
    /\ holdsLocks \in [Txns -> SUBSET Modalities]
    /\ commitLog \in Seq(Txns)

Init ==
    /\ txnStatus = [t \in Txns |-> "IDLE"]
    /\ holdsLocks = [t \in Txns |-> {}]
    /\ commitLog = << >>

--------------------------------------------------------------------------------
\* Begin: atomically acquire all locks in AccessSet(t). Fires only if no other
\* transaction currently holds any lock in AccessSet(t). Atomic acquisition
\* is what rules out deadlock -- no partial lock sets ever exist.
--------------------------------------------------------------------------------
Begin(t) ==
    /\ txnStatus[t] = "IDLE"
    /\ \A other \in Txns:
         (other /= t) => (holdsLocks[other] \cap AccessSet(t) = {})
    /\ txnStatus' = [txnStatus EXCEPT ![t] = "ACTIVE"]
    /\ holdsLocks' = [holdsLocks EXCEPT ![t] = AccessSet(t)]
    /\ UNCHANGED commitLog

--------------------------------------------------------------------------------
\* Commit: release all locks, mark COMMITTED, append to serial log. Only an
\* ACTIVE transaction (= one that has successfully acquired) can commit.
--------------------------------------------------------------------------------
Commit(t) ==
    /\ txnStatus[t] = "ACTIVE"
    /\ holdsLocks[t] = AccessSet(t)
    /\ txnStatus' = [txnStatus EXCEPT ![t] = "COMMITTED"]
    /\ holdsLocks' = [holdsLocks EXCEPT ![t] = {}]
    /\ commitLog' = Append(commitLog, t)

Next ==
    \/ \E t \in Txns: Begin(t)
    \/ \E t \in Txns: Commit(t)

\* Fairness: every ACTIVE txn eventually commits, every IDLE txn eventually
\* begins (or has no opportunity because all other txns hold its locks --
\* but atomic acquisition means some txn always makes progress, so an IDLE
\* txn cannot be permanently starved in this model).
Spec == Init /\ [][Next]_vars
        /\ \A t \in Txns: WF_vars(Begin(t) \/ Commit(t))

--------------------------------------------------------------------------------
\* Safety properties
--------------------------------------------------------------------------------

\* I1. Lock mutex: no two transactions hold overlapping locks simultaneously.
\* This is the 2PL invariant; its violation would be a direct serializability
\* failure.
NoSharedLocks ==
    \A t1, t2 \in Txns:
        (t1 /= t2) => (holdsLocks[t1] \cap holdsLocks[t2] = {})

\* I2. Locks are held only by ACTIVE transactions. IDLE and COMMITTED txns
\* own no locks.
LocksOnlyWhileActive ==
    \A t \in Txns:
        (txnStatus[t] \in {"IDLE", "COMMITTED"}) => (holdsLocks[t] = {})

\* I3. Lock-set matches the txn's AccessSet when ACTIVE. No partial acquisitions.
\* This is what atomic-Begin enforces structurally.
ActiveHoldsFullAccessSet ==
    \A t \in Txns:
        (txnStatus[t] = "ACTIVE") => (holdsLocks[t] = AccessSet(t))

\* I4. No duplicate commit log entries -- each txn commits at most once.
CommitLogInjective ==
    \A i, j \in 1..Len(commitLog):
        (commitLog[i] = commitLog[j]) => (i = j)

\* I5. Commit log only contains COMMITTED txns.
CommitLogSound ==
    \A i \in 1..Len(commitLog):
        txnStatus[commitLog[i]] = "COMMITTED"

\* I6. CENTRAL serializability claim: for any two committed conflicting txns
\* (sharing a written modality), the one that appears earlier in the commit
\* log is the one that accessed first. Because 2PL prevents overlap, this is
\* always true -- the commit log IS a conflict-equivalent serial order.
\*
\* Formal statement: if t1 and t2 both appear in commitLog and they conflict
\* (t1 writes some m that t2 reads or writes, or vice versa), then their
\* relative order in commitLog is consistent with the (trivially unique)
\* sequential order in which they held the shared lock. Since only one txn
\* can hold a given lock at a time and locks are released at Commit, the txn
\* committed earlier necessarily ran earlier. So the log IS the schedule.
\*
\* Operationally this reduces to: two conflicting txns both committed implies
\* they don't appear "simultaneously" in the log -- which is trivially true
\* of a sequence. What we really want to check is that ACTIVE sets of
\* conflicting txns never co-exist. That is exactly NoSharedLocks when
\* combined with ActiveHoldsFullAccessSet -- two ACTIVE txns have disjoint
\* access-sets, so no WW / WR / RW conflict can be concurrent.
NoConcurrentConflict ==
    \A t1, t2 \in Txns:
        (t1 /= t2
         /\ txnStatus[t1] = "ACTIVE" /\ txnStatus[t2] = "ACTIVE"
         /\ ((TxnWrites[t1] \cap (TxnReads[t2] \cup TxnWrites[t2])) /= {}
             \/ (TxnWrites[t2] \cap (TxnReads[t1] \cup TxnWrites[t1])) /= {}))
        => FALSE

SerializabilitySafe ==
    /\ TypeOK
    /\ NoSharedLocks
    /\ LocksOnlyWhileActive
    /\ ActiveHoldsFullAccessSet
    /\ CommitLogInjective
    /\ CommitLogSound
    /\ NoConcurrentConflict

--------------------------------------------------------------------------------
\* Liveness
--------------------------------------------------------------------------------

\* Every transaction eventually commits. Under atomic-acquire 2PL + WF, no
\* transaction can be starved forever: every state has at least one enabled
\* action (either some IDLE txn can Begin, since at most |Txns|-1 txns can
\* be ACTIVE at once -- and a fully ACTIVE state has at least one Commit
\* enabled; and after any Commit, freed locks re-enable some IDLE Begin).
EveryTxnCommits ==
    \A t \in Txns: <>(txnStatus[t] = "COMMITTED")

THEOREM SerializabilitySafety == Spec => []SerializabilitySafe
THEOREM AllCommit              == Spec => EveryTxnCommits

================================================================================
