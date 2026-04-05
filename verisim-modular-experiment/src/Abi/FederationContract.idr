-- SPDX-License-Identifier: PMPL-1.0-or-later
||| FederationContract.idr — what a Federable shape must expose
||| to bind to VerisimCore soundly.
|||
||| The 5 clauses implemented here (per docs/CORE-CANDIDATES.adoc):
|||   1. Aggregate-drift weight renormalisation
|||   2. Drift-signal projection surface
|||   3. Attestation-signature surface
|||   4. Coherence-constraint surface
|||   5. Conflict-resolution contract (Temporal LWW)
module Abi.FederationContract

import Abi.Types
import Abi.VerisimCore

%default total

-- -----------------------------------------------------------------------
-- Clause 1: Aggregate-drift weight renormalisation
-- -----------------------------------------------------------------------

||| A weight assignment over modality pairs (def:agg-drift).
||| The formal invariant is Σ w_{m1,m2} = 1 over all 28 pairs.
||| If a shape is absent at store level, the weights over *present* pairs
||| must renormalise to 1, or aggregate-drift claims silently change
||| semantics.
public export
record DriftWeights where
  constructor MkDriftWeights
  ||| Pairs (m1, m2) with m1 /= m2, weight in [0,1]. Caller-supplied.
  pairWeights : List ((Shape, Shape), Double)

||| Given a set of present shapes and a weight assignment over all pairs,
||| produce a renormalised assignment over only the pairs where both
||| shapes are present. Resulting weights sum to 1 (assuming input sum
||| was > 0 over present pairs).
public export
renormalise : (present : List Shape) -> DriftWeights -> DriftWeights
renormalise present (MkDriftWeights ws) =
  let keep   = filter (\((a, b), _) => elem a present && elem b present) ws in
  let wSum   = sum (map snd keep) in
  if wSum == 0
     then MkDriftWeights keep
     else MkDriftWeights (map (\(p, w) => (p, w / wSum)) keep)

-- -----------------------------------------------------------------------
-- Clause 2: Drift-signal projection surface
-- -----------------------------------------------------------------------

||| A federated peer must be able to expose drift-signal projections,
||| not just query results. This allows VerisimCore to compute drift
||| scores that involve this peer's shape without transferring the full
||| shape value.
|||
||| Example: Vector peer exposes a cosine-projection against a Core-held
||| document embedding, returning just the scalar drift contribution.
|||
||| **Transport abstraction.** This ABI commits to the semantic contract
||| only — the peer computes d_{sh, other} for an octad — and abstracts
||| over *how* the peer obtains the other shape's value. Valid transport
||| implementations include:
|||   * Peer pulls from Core via a separate endpoint.
|||   * Core pushes `otherValue` in-band (an inline-value variant; this
|||     is the pattern used by the Julia reference impl).
|||   * Both sides precompute drift snapshots at attestation time.
||| The transport is implementation-selected; the contract is identical.
public export
interface DriftProjector (m : Type -> Type) (sh : Shape) where
  ||| Compute d_{sh, other}(octad.sh, octad.other) where 'other' is a
  ||| shape the Core holds. Returns a scalar drift contribution in [0, 1]
  ||| or fails if the projection is undefined for that pair.
  driftAgainst : OctadId -> (other : Shape) -> m (Either String Double)

-- -----------------------------------------------------------------------
-- Clause 3: Attestation-signature surface
-- -----------------------------------------------------------------------

||| Every Federable peer must sign its responses, per thm:attestation.
||| The peer provides: (a) its public key id, (b) a signing function
||| over byte payloads, and (c) a freshness policy.
public export
record PeerAttestation where
  constructor MkPeerAttestation
  publicKeyId     : List Bits8
  latestAttest    : Signature
  attestTimestamp : Timestamp
  ||| Maximum age in nanoseconds before attestation is stale.
  freshnessWindow : Integer

||| Check that a peer's attestation falls within its declared freshness
||| window relative to Core's current time.
public export
isFresh : (now : Timestamp) -> PeerAttestation -> Bool
isFresh now p =
  let age = now.epochNanos - p.attestTimestamp.epochNanos
  in age >= 0 && age <= p.freshnessWindow

-- -----------------------------------------------------------------------
-- Clause 4: Coherence-constraint surface
-- -----------------------------------------------------------------------

||| A peer may participate in coherence constraints that cross the
||| Core/Federable boundary (def:coherence). For constraint c(m1, m2)
||| where m1 is Core and m2 is this peer's shape, the peer must expose
||| enough to evaluate c.
|||
||| Example: G↔S coherence constraint ("Graph edges match Semantic type
||| assertions"). If Graph is Federable, Graph peer must expose the
||| set of typed edges so Core's Semantic can compute the Jaccard
||| distance (def:drift-metrics, Graph-Semantic drift).
public export
interface CoherenceProjector (m : Type -> Type) (sh : Shape) where
  ||| Expose enough of this shape's data to evaluate a coherence
  ||| constraint with 'coreShape'. Returns an opaque byte projection
  ||| for Core to interpret.
  coherenceProj : OctadId -> (coreShape : Shape) -> m (Either String (List Bits8))

-- -----------------------------------------------------------------------
-- Clause 5: Conflict-resolution contract (Temporal LWW)
-- -----------------------------------------------------------------------

||| In federation, Temporal is Core-provided and serves as the total
||| order on writes (§7, Conflict Resolution). Federable peers must
||| accept Core's Temporal ordering as authoritative for resolving
||| conflicts on their shape's data.
public export
interface LWWAcceptor (m : Type -> Type) (sh : Shape) where
  ||| Apply a write to this peer's shape under Core-provided LWW
  ||| ordering. Peer compares 'coreTimestamp' against its local
  ||| last-write timestamp for this octad and accepts/rejects.
  applyLWW : OctadId -> (coreTimestamp : Timestamp) ->
             (payload : List Bits8) -> m (Either String ())

-- -----------------------------------------------------------------------
-- Full FederableShape interface: combines clauses 2, 4, 5 per-shape.
-- Clauses 1 (renormalisation) and 3 (attestation) are orthogonal —
-- they belong to Core's federation manager, not per-shape.
-- -----------------------------------------------------------------------

public export
interface (DriftProjector m sh,
           CoherenceProjector m sh,
           LWWAcceptor m sh) =>
          FederableShape (m : Type -> Type) (sh : Shape) where
  ||| Identify the Federable shape this peer implements.
  peerShape : Shape
  ||| Peer's attestation metadata.
  peerAttestation : m PeerAttestation

-- -----------------------------------------------------------------------
-- Soundness obligation: only Federable (not Core) shapes may be
-- federated. Attempting to federate a Core shape is a category error.
-- -----------------------------------------------------------------------

||| A type-level predicate that a shape is permitted to be federated.
||| Core shapes fail to satisfy this; Federable and Conditional shapes
||| succeed (the latter subject to runtime cross-entity-claim gating).
public export
data IsFederable : Shape -> Type where
  FederableVector   : IsFederable V_Vector
  FederableTensor   : IsFederable T_Tensor
  FederableDocument : IsFederable D_Document
  FederableSpatial  : IsFederable X_Spatial
  ConditionalGraph  : IsFederable G_Graph
  -- Deliberately NO constructors for S_Semantic, P_Temporal, R_Provenance:
  -- the type system refuses to let Core shapes be federated.
