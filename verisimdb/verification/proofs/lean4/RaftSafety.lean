-- SPDX-License-Identifier: PMPL-1.0-or-later
/-!
# Raft Consensus Safety — Commit Invariants

**Proof obligation V4** — companion to
`nextgen-databases/verisimdb/src/registry/MetadataLog.res` and
`KRaftCluster.res`

Lean 4 only — no Mathlib.

## Scope

Single-node commit safety invariants of the KRaft-style Raft implementation
used in VeriSimDB's federation registry:

1. **V4-A  Commit monotonicity** — `commitIndex` never decreases
2. **V4-B  Append isolation** — appending never changes entries at `< commitIndex`
3. **V4-C  WF preservation** — well-formedness is maintained by valid appends
4. **V4-D  Log Matching (single node)** — sequential index uniquely locates entries

The distributed Log Matching invariant (no divergence across replicas) is proven
in the companion TLA+ model (`verification/tla+/RaftConsensus.tla`).
-/

-- ============================================================================
-- § 1. Data types
-- ============================================================================

/-- A single Raft log entry. -/
structure RaftEntry where
  term  : Nat    -- Raft term (epoch)
  idx   : Nat    -- 1-based sequential log index
  cmdId : Nat    -- abstract command identifier
  deriving DecidableEq, Repr

/-- Raft node log state (`commitIndex = 0` means nothing committed). -/
structure RaftLog where
  entries     : List RaftEntry
  commitIndex : Nat
  deriving Repr

-- ============================================================================
-- § 2. Well-formedness
-- ============================================================================

/-- A log is well-formed: sequential indices, bounded commit pointer, and
    monotone terms. -/
structure RaftLog.WF (rl : RaftLog) : Prop where
  idxSeq    : ∀ i (e : RaftEntry), rl.entries[i]? = some e → e.idx = i + 1
  commitBnd : rl.commitIndex ≤ rl.entries.length
  termMono  : ∀ i j (ei ej : RaftEntry),
                i ≤ j → j < rl.entries.length →
                rl.entries[i]? = some ei →
                rl.entries[j]? = some ej →
                ei.term ≤ ej.term

-- ============================================================================
-- § 3. Transitions
-- ============================================================================

/-- Append one entry to the log. -/
def RaftLog.appendEntry (rl : RaftLog) (e : RaftEntry) : RaftLog :=
  { rl with entries := rl.entries ++ [e] }

/-- Advance `commitIndex` monotonically. -/
def RaftLog.advanceCommit (rl : RaftLog) (n : Nat) : RaftLog :=
  { rl with commitIndex := Nat.max rl.commitIndex n }

-- ============================================================================
-- § 4. V4-A  Commit monotonicity
-- ============================================================================

theorem commitIndex_monotone (rl : RaftLog) (n : Nat) :
    rl.commitIndex ≤ (rl.advanceCommit n).commitIndex :=
  Nat.le_max_left ..

-- ============================================================================
-- § 5. V4-B  Append isolation
-- ============================================================================

/-- Appending a new entry does not change entries at positions below
    `commitIndex`. -/
theorem append_preserves_committed (rl : RaftLog) (e : RaftEntry) (i : Nat)
    (hwf : rl.WF) (hi : i < rl.commitIndex) :
    (rl.appendEntry e).entries[i]? = rl.entries[i]? :=
  List.getElem?_append_left (Nat.lt_of_lt_of_le hi hwf.commitBnd)

/-- Committed entry is still present after any valid append. -/
theorem committed_entry_stable (rl : RaftLog) (e_new : RaftEntry)
    (hwf : rl.WF) (i : Nat) (hi : i < rl.commitIndex)
    (x : RaftEntry) (hx : rl.entries[i]? = some x) :
    (rl.appendEntry e_new).entries[i]? = some x := by
  rw [append_preserves_committed rl e_new i hwf hi]; exact hx

-- ============================================================================
-- § 6. V4-C  WF preservation under valid append
-- ============================================================================

/-!
A **valid** append carries:
- `e.idx = rl.entries.length + 1`  (next sequential index)
- `∀ last, getLast? = some last → last.term ≤ e.term`  (term monotonicity)
-/

/-- `getElem?` of the last element in a singleton-appended list. -/
private theorem getElem?_snoc_last {α} (l : List α) (x : α) :
    (l ++ [x])[l.length]? = some x := by
  exact List.getElem?_concat_length l x

/-- In bounds `getElem?` of appended list equals original. -/
private theorem getElem?_snoc_left {α} (l : List α) (x : α) (i : Nat)
    (h : i < l.length) : (l ++ [x])[i]? = l[i]? :=
  List.getElem?_append_left h

/-- The only in-bounds position past `l.length` in `l ++ [x]` is `l.length`. -/
private theorem snoc_out_implies_eq {α} (l : List α) (x : α) (i : Nat)
    (hge : ¬ i < l.length)
    (hlt : i < (l ++ [x]).length) : i = l.length := by
  simp [List.length_append] at hlt; omega

theorem appendEntry_WF (rl : RaftLog) (e : RaftEntry)
    (hwf   : rl.WF)
    (hidx  : e.idx = rl.entries.length + 1)
    (hterm : ∀ last, rl.entries.getLast? = some last → last.term ≤ e.term) :
    (rl.appendEntry e).WF := by
  unfold RaftLog.appendEntry
  constructor
  · -- idxSeq
    intro i x hget
    by_cases hi : i < rl.entries.length
    · rw [getElem?_snoc_left _ _ _ hi] at hget
      exact hwf.idxSeq i x hget
    · -- new element
      have hlt : i < (rl.entries ++ [e]).length := by
        cases Nat.lt_or_ge i (rl.entries ++ [e]).length with
        | inl h => exact h
        | inr h =>
          exfalso
          have : (rl.entries ++ [e])[i]? = none :=
            List.getElem?_eq_none_iff.mpr h
          simp [this] at hget
      have heq : i = rl.entries.length := snoc_out_implies_eq _ _ _ hi hlt
      subst heq
      rw [getElem?_snoc_last] at hget
      exact Option.some.inj hget ▸ hidx
  · -- commitBnd
    simp only [List.length_append, List.length_singleton]
    exact Nat.le_add_right_of_le hwf.commitBnd
  · -- termMono
    intro i j ei ej hij hjlt hgi hgj
    simp only [List.length_append, List.length_singleton] at hjlt
    by_cases hj : j < rl.entries.length
    · -- j in old log → i also in old log
      have hi_lt : i < rl.entries.length := Nat.lt_of_le_of_lt hij hj
      rw [getElem?_snoc_left _ _ _ hi_lt] at hgi
      rw [getElem?_snoc_left _ _ _ hj] at hgj
      exact hwf.termMono i j ei ej hij hj hgi hgj
    · -- j = length (the new element)
      have hjeq : j = rl.entries.length := by omega
      subst hjeq
      rw [getElem?_snoc_last] at hgj
      -- hgj : some e = some ej
      obtain rfl : ej = e := (Option.some.inj hgj).symm
      -- goal: ei.term ≤ e.term
      by_cases hi_lt : i < rl.entries.length
      · -- i in old log: chain ei.term ≤ last.term ≤ e.term
        rw [getElem?_snoc_left _ _ _ hi_lt] at hgi
        have hlen_pos : 0 < rl.entries.length :=
          Nat.lt_of_le_of_lt (Nat.zero_le i) hi_lt
        have hne : rl.entries ≠ [] := (List.length_pos.mp hlen_pos)
        have hbound : rl.entries.length - 1 < rl.entries.length := by omega
        have hlast_get : rl.entries.getLast? = some (rl.entries.getLast hne) :=
          List.getLast?_eq_getLast rl.entries hne
        have hlast_idx : rl.entries[rl.entries.length - 1]? = some (rl.entries.getLast hne) := by
          rw [List.getElem?_eq_getElem hbound]
          exact (congrArg some (List.getLast_eq_getElem rl.entries hne)).symm
        have hterm_e := hterm (rl.entries.getLast hne) hlast_get
        have hei_last : ei.term ≤ (rl.entries.getLast hne).term :=
          hwf.termMono i (rl.entries.length - 1) ei (rl.entries.getLast hne)
            (by omega) hbound hgi hlast_idx
        exact Nat.le_trans hei_last hterm_e
      · -- i = rl.entries.length: ei occupies same slot as ej (= e)
        have heq : i = rl.entries.length := by omega
        subst heq
        rw [getElem?_snoc_last] at hgi
        -- hgi : some e = some ei  →  e = ei
        exact Nat.le_of_eq (congrArg RaftEntry.term (Option.some.inj hgi).symm)

-- ============================================================================
-- § 7. V4-D  Log Matching (single-node)
-- ============================================================================

/-!
In a well-formed log, the `idx` field uniquely determines the list position:
two entries with the same `idx` are at the same list position.
-/
theorem log_matching_single (rl : RaftLog) (hwf : rl.WF)
    (i j : Nat) (ei ej : RaftEntry)
    (hgi     : rl.entries[i]? = some ei)
    (hgj     : rl.entries[j]? = some ej)
    (hidx_eq : ei.idx = ej.idx) :
    i = j := by
  have hi := hwf.idxSeq i ei hgi   -- ei.idx = i + 1
  have hj := hwf.idxSeq j ej hgj   -- ej.idx = j + 1
  -- ei.idx = ej.idx implies i + 1 = j + 1
  rw [hi, hj] at hidx_eq
  omega

-- ============================================================================
-- § 8. Summary
-- ============================================================================

/-!
## Proof summary (V4)

| Label  | Property                          | Theorem                     |
|--------|-----------------------------------|-----------------------------|
| V4-A   | Commit monotonicity               | `commitIndex_monotone`      |
| V4-B   | Append isolation                  | `append_preserves_committed` |
| V4-B′  | Committed entry stability         | `committed_entry_stable`    |
| V4-C   | WF preservation under append      | `appendEntry_WF`            |
| V4-D   | Log Matching (single-node)        | `log_matching_single`       |

The distributed Log Matching invariant (no divergence across replicas after
commit) is established in the companion TLA+ model.
-/
