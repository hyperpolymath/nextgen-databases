-- SPDX-License-Identifier: PMPL-1.0-or-later
||| VerisimCore.idr — the identity-core ABI.
|||
||| VerisimCore is the minimal substrate required to state and verify
||| VCL consonance claims. A Core instance can stand alone (no federated
||| shapes) and still provide sound — though limited — VCL operation.
|||
||| Grounded in verisimdb/arcvix-octad-data-model.tex:
|||   - def:octad         (octad identity, φ function, ⊥ per modality)
|||   - inv:persist       (Identity Persistence — Temporal required)
|||   - def:enrichment    (write primitive writes to both P and R)
|||   - thm:attestation   (attestation freshness + signature)
module Abi.VerisimCore

import Abi.Types

%default total

||| 128-bit octad identifier (def:octad, id ∈ UUID).
||| Abstracted here; concrete representation lives in the FFI layer.
public export
data OctadId : Type where
  MkOctadId : (bytes : List Bits8) -> OctadId

||| A monotonic logical timestamp, Temporal-modality-provided.
||| Per thm:attestation, attestations bear a timestamp t that must lie
||| within the freshness window. Per §7, LWW uses Temporal as total order.
public export
record Timestamp where
  constructor MkTimestamp
  epochNanos : Integer

||| An Ed25519 signature and the key-id of the signer. Per §7 (federation
||| trust), every cross-store query response is signed. Provenance maintains
||| the hash-chain of signed attestations over time.
public export
record Signature where
  constructor MkSignature
  keyId     : List Bits8
  sigBytes  : List Bits8

||| A provenance hash-chain entry (def:modset, Σ_R = SHA-256 hash chains).
||| Each entry records a creation / transformation / access event.
public export
record ProvenanceEntry where
  constructor MkProvenanceEntry
  prevHash  : List Bits8
  thisHash  : List Bits8
  actor     : String
  timestamp : Timestamp
  signature : Signature

||| The Temporal modality for one octad (def:modset, Σ_P = Merkle-tree
||| version histories over octad snapshots).
public export
record TemporalHistory where
  constructor MkTemporalHistory
  ||| Ordered leaves of the Merkle tree. First entry is creation.
  leaves : List Timestamp

||| The Provenance modality for one octad (def:modset, Σ_R = hash chain).
public export
record ProvenanceChain where
  constructor MkProvenanceChain
  entries : List ProvenanceEntry

||| The Semantic modality for one octad (def:modset, Σ_S = CBOR-encoded
||| type URIs + proof blobs). Abstracted as an opaque byte slice here;
||| the concrete CBOR decoder lives in the FFI layer.
public export
record SemanticBlob where
  constructor MkSemanticBlob
  typeUris   : List String
  proofBytes : List Bits8

||| A Core octad holds exactly the three store-level-required modalities.
||| Any of them may be ⊥ per-entity (def:octad allows this), but the
||| store must implement all three for Identity Persistence (inv:persist)
||| and the enrichment primitive (def:enrichment) to hold.
public export
record CoreOctad where
  constructor MkCoreOctad
  id         : OctadId
  semantic   : Maybe SemanticBlob       -- φ(S), ⊥ allowed per-entity
  temporal   : Maybe TemporalHistory    -- φ(P), ⊥ allowed per-entity
  provenance : Maybe ProvenanceChain    -- φ(R), ⊥ allowed per-entity

||| Interface a VerisimCore implementation must satisfy. This is the
||| minimal surface — Federable shapes bind via FederationContract.idr.
public export
interface VerisimCore (m : Type -> Type) where
  ||| Read: fetch the core projection of an octad by id.
  getCore    : OctadId -> m (Maybe CoreOctad)

  ||| Write: the enrichment primitive (def:enrichment). Appends to both
  ||| Temporal (φ(P)) and Provenance (φ(R)) atomically. This is the ONLY
  ||| permitted write path — enforcing Identity Persistence by
  ||| construction.
  enrich     : OctadId -> (shape : Shape) -> (payload : List Bits8) ->
               (actor : String) -> m (Either String ())

  ||| Produce a signed attestation of the current core state
  ||| (thm:attestation). Used both locally and when responding to
  ||| federation peers.
  attest     : OctadId -> m (Maybe (CoreOctad, Signature, Timestamp))

  ||| Verify an attestation from a federated peer. Checks signature
  ||| validity AND that the timestamp lies within the freshness window
  ||| (freshness window is implementation-configured).
  verifyAttest : (octad : CoreOctad) -> (sig : Signature) ->
                 (t : Timestamp) -> m Bool
