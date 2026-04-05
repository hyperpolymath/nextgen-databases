-- SPDX-License-Identifier: PMPL-1.0-or-later
||| Types.idr — Octad shape enumeration and Core/Federable partition.
|||
||| Derived from verisimdb/arcvix-octad-data-model.tex Definition 3
||| (Modality Set). The formal notation uses G, V, T, S, D, P, R, X
||| where P = Temporal and R = Provenance (not P = Provenance).
module Abi.Types

%default total

||| The eight octad modalities (per def:modset).
|||
||| Naming matches the formal model: `PTemporal` and `RProvenance`
||| preserve the TeX letter-assignments (P = Temporal, R = Provenance).
public export
data Shape : Type where
  G_Graph       : Shape
  V_Vector      : Shape
  T_Tensor      : Shape
  S_Semantic    : Shape
  D_Document    : Shape
  P_Temporal    : Shape
  R_Provenance  : Shape
  X_Spatial     : Shape

public export
Eq Shape where
  G_Graph       == G_Graph       = True
  V_Vector      == V_Vector      = True
  T_Tensor      == T_Tensor      = True
  S_Semantic    == S_Semantic    = True
  D_Document    == D_Document    = True
  P_Temporal    == P_Temporal    = True
  R_Provenance  == R_Provenance  = True
  X_Spatial     == X_Spatial     = True
  _             == _             = False

public export
Show Shape where
  show G_Graph      = "Graph"
  show V_Vector     = "Vector"
  show T_Tensor     = "Tensor"
  show S_Semantic   = "Semantic"
  show D_Document   = "Document"
  show P_Temporal   = "Temporal"
  show R_Provenance = "Provenance"
  show X_Spatial    = "Spatial"

||| Classification of each shape per the Path B stress-test
||| (docs/CORE-CANDIDATES.adoc, Resolved Classification).
public export
data Classification : Type where
  ||| Store-level required. Absence collapses VCL soundness.
  Core        : Classification
  ||| Can be omitted at store level; drift d(⊥,·)=0 convention holds.
  Federable   : Classification
  ||| Required iff cross-entity consonance claims are in scope.
  Conditional : Classification

public export
classify : Shape -> Classification
classify S_Semantic    = Core
classify P_Temporal    = Core
classify R_Provenance  = Core
classify G_Graph       = Conditional
classify V_Vector      = Federable
classify T_Tensor      = Federable
classify D_Document    = Federable
classify X_Spatial     = Federable

||| Proof that {Semantic, Temporal, Provenance} is exactly the Core set.
|||
||| This is a sanity lemma: the experiment's whole point is that |Core| = 3.
||| If this ever fails to compile, the classification has been edited and
||| Phase 1's result needs revisiting.
public export
coreIs3 : (classify S_Semantic = Core,
           classify P_Temporal = Core,
           classify R_Provenance = Core)
coreIs3 = (Refl, Refl, Refl)
