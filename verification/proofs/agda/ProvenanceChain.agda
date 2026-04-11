-- SPDX-License-Identifier: PMPL-1.0-or-later
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
-- ProvenanceChain.agda — Formal proof of provenance chain immutability (V7).
--
-- REQUIREMENTS-MASTER.md: V7 | Provenance chain immutability (hash chain, monotonic timestamps) | SEC | Ag | P1
--
-- Models rust-core/verisim-provenance/src/lib.rs:
--   - ProvenanceRecord has: content, timestamp, parentHash, actorId, contentHash
--   - Hash chain: parentHash[i+1] = contentHash[i]  (each record links to its predecessor)
--   - First record has parentHash = genesisHash (the "0"*64 sentinel)
--
-- List representation: PREPEND order — the HEAD of the list is the NEWEST record.
-- This makes chain extension (hc-cons) structurally natural.
--
-- Properties proved:
--   1. HashChain predicate — well-formedness of a provenance chain
--   2. chain-tail-valid — tail of valid chain is valid
--   3. chain-head-consistent — head is self-consistent
--   4. chain-link — parentHash of head links to contentHash of predecessor
--   5. tamper-detected — changing content changes contentHash (by hash injectivity)
--   6. chain-tamper-breaks-link — a tampered record breaks the link from its successor
--   7. timestamps-non-decreasing — timestamps grow along the chain (oldest last)
--   8. genesis-unique — only the tail (oldest) record has genesisHash as parent
--   9. chain-extend — prepending a new record with a valid link extends the chain

module ProvenanceChain where

open import Data.Nat using (ℕ; zero; suc; _≤_; _<_; z≤n; s≤s)
open import Data.Nat.Properties using (≤-refl; ≤-trans; n<1+n; <⇒≤)
open import Data.List using (List; []; _∷_; length)
open import Data.Product using (_×_; _,_; proj₁; proj₂)
open import Data.Empty using (⊥; ⊥-elim)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; sym; trans; cong; _≢_)
open import Relation.Nullary using (¬_)

------------------------------------------------------------------------
-- Section 1: Abstract hash model
------------------------------------------------------------------------

-- Hashes are abstracted as ℕ.
Hash : Set
Hash = ℕ

-- Abstract hash function for a provenance record's fields.
-- content × timestamp × parentHash × actorId → contentHash
postulate
  hashRecord : Hash → ℕ → Hash → Hash → Hash
  -- Collision resistance: equal outputs imply equal inputs.
  hash-injective : ∀ {c₁ t₁ p₁ a₁ c₂ t₂ p₂ a₂}
    → hashRecord c₁ t₁ p₁ a₁ ≡ hashRecord c₂ t₂ p₂ a₂
    → c₁ ≡ c₂ × t₁ ≡ t₂ × p₁ ≡ p₂ × a₁ ≡ a₂
  -- hashRecord never returns the genesis sentinel.
  -- Holds in Rust because SHA-256 of non-empty input ≠ "0"*64.
  hashRecord-not-genesis : ∀ (c t p a : Hash) → hashRecord c t p a ≢ 0

-- Genesis parent hash: sentinel for the oldest record's parentHash.
genesisHash : Hash
genesisHash = 0

------------------------------------------------------------------------
-- Section 2: Provenance record model
------------------------------------------------------------------------

record ProvenanceRecord : Set where
  constructor mkRecord
  field
    content     : Hash
    timestamp   : ℕ
    parentHash  : Hash
    actorId     : Hash
    contentHash : Hash   -- = hashRecord content timestamp parentHash actorId

-- A record is self-consistent if its contentHash is correctly computed.
SelfConsistent : ProvenanceRecord → Set
SelfConsistent r =
  ProvenanceRecord.contentHash r ≡
    hashRecord
      (ProvenanceRecord.content r)
      (ProvenanceRecord.timestamp r)
      (ProvenanceRecord.parentHash r)
      (ProvenanceRecord.actorId r)

------------------------------------------------------------------------
-- Section 3: Hash chain predicate
--
-- The list is stored NEWEST-FIRST (prepend order).
-- HashChain (r_new ∷ r_old ∷ rs) means:
--   - r_new is the most recently appended record
--   - r_old is the record before r_new
--   - r_new.parentHash = r_old.contentHash  (link)
--   - r_old.timestamp ≤ r_new.timestamp     (monotone)
------------------------------------------------------------------------

data HashChain : List ProvenanceRecord → Set where

  hc-nil   : HashChain []

  hc-first : ∀ {r}
           → SelfConsistent r
           → ProvenanceRecord.parentHash r ≡ genesisHash
           → HashChain (r ∷ [])

  -- Prepend r_new to an existing chain headed by r_old.
  hc-cons  : ∀ {r_new r_old rs}
           → HashChain (r_old ∷ rs)          -- existing chain
           → SelfConsistent r_new
           → ProvenanceRecord.parentHash r_new ≡ ProvenanceRecord.contentHash r_old
           → ProvenanceRecord.timestamp r_old ≤ ProvenanceRecord.timestamp r_new
           → HashChain (r_new ∷ r_old ∷ rs)  -- extended chain

------------------------------------------------------------------------
-- Section 4: Structural lemmas
------------------------------------------------------------------------

-- V7 — LEMMA 1: The tail of a valid chain is valid.
-- (Easy: hc-cons's first argument is exactly the tail chain.)
chain-tail-valid : ∀ {r rs}
                  → HashChain (r ∷ rs)
                  → HashChain rs
chain-tail-valid (hc-first _ _)           = hc-nil
chain-tail-valid (hc-cons hc_tail _ _ _) = hc_tail

-- V7 — LEMMA 2: The head of a valid chain is self-consistent.
chain-head-consistent : ∀ {r rs}
                       → HashChain (r ∷ rs)
                       → SelfConsistent r
chain-head-consistent (hc-first sc _)     = sc
chain-head-consistent (hc-cons _ sc _ _) = sc

-- V7 — LEMMA 3: The head's parentHash equals its predecessor's contentHash.
chain-link : ∀ {r_new r_old rs}
            → HashChain (r_new ∷ r_old ∷ rs)
            → ProvenanceRecord.parentHash r_new ≡ ProvenanceRecord.contentHash r_old
chain-link (hc-cons _ _ link _) = link

-- V7 — LEMMA 4: Timestamps are non-decreasing head-to-predecessor.
-- Since the list is newest-first, the head timestamp is ≥ the second element's.
chain-ts-head-ge : ∀ {r_new r_old rs}
                  → HashChain (r_new ∷ r_old ∷ rs)
                  → ProvenanceRecord.timestamp r_old ≤ ProvenanceRecord.timestamp r_new
chain-ts-head-ge (hc-cons _ _ _ ts) = ts

------------------------------------------------------------------------
-- Section 5: Immutability theorems
------------------------------------------------------------------------

-- V7 — THEOREM 1: Two self-consistent records with the same contentHash
-- have identical field values (injectivity of hashRecord).
same-hash-same-fields :
  ∀ {r₁ r₂ : ProvenanceRecord}
  → SelfConsistent r₁
  → SelfConsistent r₂
  → ProvenanceRecord.contentHash r₁ ≡ ProvenanceRecord.contentHash r₂
  → ProvenanceRecord.content r₁ ≡ ProvenanceRecord.content r₂
    × ProvenanceRecord.timestamp r₁ ≡ ProvenanceRecord.timestamp r₂
    × ProvenanceRecord.parentHash r₁ ≡ ProvenanceRecord.parentHash r₂
    × ProvenanceRecord.actorId r₁ ≡ ProvenanceRecord.actorId r₂
same-hash-same-fields sc₁ sc₂ heq =
  hash-injective (trans (sym sc₁) (trans heq sc₂))

-- V7 — THEOREM 2: Changing the content field changes the contentHash.
tamper-detected :
  ∀ {r r' : ProvenanceRecord}
  → SelfConsistent r
  → SelfConsistent r'
  → ProvenanceRecord.content r ≢ ProvenanceRecord.content r'
  → ProvenanceRecord.contentHash r ≢ ProvenanceRecord.contentHash r'
tamper-detected sc sc' hne heq =
  hne (proj₁ (same-hash-same-fields sc sc' heq))

-- V7 — THEOREM 3: Replacing the predecessor r_old with a tampered r_old'
-- (different content) causes the head r_new's parentHash to no longer match.
chain-tamper-breaks-link :
  ∀ {r_new r_old : ProvenanceRecord} {rs : List ProvenanceRecord}
  → HashChain (r_new ∷ r_old ∷ rs)
  → (r_old' : ProvenanceRecord)
  → SelfConsistent r_old'
  → ProvenanceRecord.content r_old ≢ ProvenanceRecord.content r_old'
  → ProvenanceRecord.parentHash r_new ≢ ProvenanceRecord.contentHash r_old'
chain-tamper-breaks-link hc r_old' sc' hContentNe =
  let hc-old : SelfConsistent _
      hc-old = chain-head-consistent (chain-tail-valid hc)
      hLink  = chain-link hc
      hHashNe = tamper-detected hc-old sc' hContentNe
  in λ link' → hHashNe (trans (sym hLink) link')

------------------------------------------------------------------------
-- Section 6: Timestamp monotonicity
------------------------------------------------------------------------

-- Extract timestamps in newest-first order.
chainTimestamps : List ProvenanceRecord → List ℕ
chainTimestamps []       = []
chainTimestamps (r ∷ rs) = ProvenanceRecord.timestamp r ∷ chainTimestamps rs

-- V7 — THEOREM 4: Timestamps in a valid chain are non-decreasing from
-- oldest (tail) to newest (head). Equivalently, chainTimestamps is a
-- non-increasing sequence (newest first → values are ≥ previous).
--
-- We prove the pointwise version: for any adjacent pair in the chain,
-- the older record's timestamp ≤ the newer record's timestamp.
timestamps-non-decreasing :
  ∀ {r_new r_old rs}
  → HashChain (r_new ∷ r_old ∷ rs)
  → ProvenanceRecord.timestamp r_old ≤ ProvenanceRecord.timestamp r_new
timestamps-non-decreasing = chain-ts-head-ge

------------------------------------------------------------------------
-- Section 7: Genesis uniqueness
------------------------------------------------------------------------

-- V7 — THEOREM 5: Only the tail (oldest) record has genesisHash as parentHash.
-- Any non-first record's parentHash equals the contentHash of its predecessor,
-- and contentHash is produced by hashRecord, which never returns genesisHash.
genesis-unique :
  ∀ {r_new r_old rs}
  → HashChain (r_new ∷ r_old ∷ rs)
  → ProvenanceRecord.parentHash r_new ≢ genesisHash
genesis-unique {r_new} {r_old} hc hEq =
  let hLink = chain-link hc
      sc_old = chain-head-consistent (chain-tail-valid hc)
  in hashRecord-not-genesis
       (ProvenanceRecord.content r_old)
       (ProvenanceRecord.timestamp r_old)
       (ProvenanceRecord.parentHash r_old)
       (ProvenanceRecord.actorId r_old)
       (trans (sym sc_old) (trans (sym hLink) hEq))

------------------------------------------------------------------------
-- Section 8: Chain extension
------------------------------------------------------------------------

-- V7 — THEOREM 6: Prepending a new well-formed record extends the chain.
-- The caller supplies the link proof and the timestamp proof.
chain-extend :
  ∀ {r_old rs}
  → HashChain (r_old ∷ rs)
  → (r_new : ProvenanceRecord)
  → SelfConsistent r_new
  → ProvenanceRecord.parentHash r_new ≡ ProvenanceRecord.contentHash r_old
  → ProvenanceRecord.timestamp r_old ≤ ProvenanceRecord.timestamp r_new
  → HashChain (r_new ∷ r_old ∷ rs)
chain-extend hc r_new sc link ts = hc-cons hc sc link ts
