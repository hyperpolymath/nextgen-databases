-- SPDX-License-Identifier: PMPL-1.0-or-later
/-!
# VCL Type Inference Soundness (V2)

Formal model for the query-core fragment implemented by `src/vcl/VCLBidir.res`.

The model focuses on the pieces that drive result typing in production:

- query synthesis (`select`, `selectP`, projections)
- checking against expected type via a small subtyping layer
- progress and preservation for the core reduction rules (`fst`, `snd`)

This is intentionally query-core, not lambda-calculus. The source checker in
`VCLBidir.res` walks a query AST and returns `Result<vclType, typeError>`; it
does not evaluate lambda/application terms.
-/

namespace VCLTypeSoundness

-- ============================================================================
-- 1. Types
-- ============================================================================

inductive Modality : Type where
  | graph | vector | tensor | semantic | document | temporal | provenance | spatial
  deriving DecidableEq, Repr

inductive PrimTy : Type where
  | int | float | string | bool | uuid | timestamp
  deriving DecidableEq, Repr

inductive ProofKind : Type where
  | existence | integrity | consistency | provenanceProof | freshness | access | citation | custom
  deriving DecidableEq, Repr

inductive Ty : Type where
  | prim      : PrimTy → Ty
  | array     : Ty → Ty
  | modality  : Modality → Ty
  | unit      : Ty
  | never     : Ty
  | queryRes  : List Modality → Ty
  | proof     : ProofKind → String → Ty
  | sigma     : Ty → Ty → Ty
  | piType    : String → Ty → Ty → Ty
  deriving DecidableEq, Repr

-- ============================================================================
-- 2. Expressions and values
-- ============================================================================

structure FieldRef where
  mod   : Modality
  field : String
  deriving DecidableEq, Repr

inductive AggFunc : Type where
  | count | sum | avg | min | max
  deriving DecidableEq, Repr

inductive Lit : Type where
  | intLit   : Int → Lit
  | strLit   : String → Lit
  | boolLit  : Bool → Lit
  deriving DecidableEq, Repr

def Lit.ty : Lit → PrimTy
  | .intLit _  => .int
  | .strLit _  => .string
  | .boolLit _ => .bool

inductive Expr : Type where
  | lit          : Lit → Expr
  | fieldGet     : FieldRef → Expr
  | agg          : AggFunc → FieldRef → Expr
  | select       : List Modality → List FieldRef → Expr
  | selectP      : List Modality → List FieldRef → ProofKind → String → Expr
  | proofWitness : ProofKind → String → Expr
  | pair         : Expr → Expr → Expr
  | fst          : Expr → Expr
  | snd          : Expr → Expr
  | unitVal      : Expr
  deriving DecidableEq, Repr

inductive IsValue : Expr → Prop where
  | litV      : IsValue (.lit l)
  | fieldV    : IsValue (.fieldGet f)
  | aggV      : IsValue (.agg g f)
  | selectV   : IsValue (.select ms fs)
  | selectPV  : IsValue (.selectP ms fs pk c)
  | proofWV   : IsValue (.proofWitness pk c)
  | unitV     : IsValue .unitVal
  | pairV     : IsValue e₁ → IsValue e₂ → IsValue (.pair e₁ e₂)

-- ============================================================================
-- 3. Typing
-- ============================================================================

abbrev Ctx := FieldRef → Option PrimTy

def Ctx.empty : Ctx := fun _ => none

inductive HasType : Ctx → Expr → Ty → Prop where
  | tLit      : HasType Γ (.lit l) (.prim l.ty)
  | tUnit     : HasType Γ .unitVal .unit
  | tField    : Γ fr = some pt → HasType Γ (.fieldGet fr) (.prim pt)
  | tAggCount : HasType Γ (.agg .count fr) (.prim .int)
  | tAggSumI  : Γ fr = some .int → HasType Γ (.agg .sum fr) (.prim .int)
  | tAggSumF  : Γ fr = some .float → HasType Γ (.agg .sum fr) (.prim .float)
  | tAggAvg   : Γ fr = some .int ∨ Γ fr = some .float →
                HasType Γ (.agg .avg fr) (.prim .float)
  | tAggMinMax : Γ fr = some pt → (g = .min ∨ g = .max) →
                 HasType Γ (.agg g fr) (.prim pt)
  | tSelect   : HasType Γ (.select ms fs) (.queryRes ms)
  | tSelectP  : HasType Γ (.selectP ms fs pk c) (.sigma (.queryRes ms) (.proof pk c))
  | tProofW   : HasType Γ (.proofWitness pk c) (.proof pk c)
  | tPair     : HasType Γ e₁ τ₁ → HasType Γ e₂ τ₂ →
                HasType Γ (.pair e₁ e₂) (.sigma τ₁ τ₂)
  | tFst      : HasType Γ e (.sigma τ₁ τ₂) → HasType Γ (.fst e) τ₁
  | tSnd      : HasType Γ e (.sigma τ₁ τ₂) → HasType Γ (.snd e) τ₂

-- ============================================================================
-- 4. Operational semantics
-- ============================================================================

inductive Step : Expr → Expr → Prop where
  | fstPair    : IsValue e₁ → IsValue e₂ → Step (.fst (.pair e₁ e₂)) e₁
  | sndPair    : IsValue e₁ → IsValue e₂ → Step (.snd (.pair e₁ e₂)) e₂
  | fstSelectP : Step (.fst (.selectP ms fs pk c)) (.select ms fs)
  | sndSelectP : Step (.snd (.selectP ms fs pk c)) (.proofWitness pk c)
  | fstStep    : Step e e' → Step (.fst e) (.fst e')
  | sndStep    : Step e e' → Step (.snd e) (.snd e')
  | pairStepL  : Step e₁ e₁' → Step (.pair e₁ e₂) (.pair e₁' e₂)
  | pairStepR  : IsValue e₁ → Step e₂ e₂' → Step (.pair e₁ e₂) (.pair e₁ e₂')

inductive Progress (e : Expr) : Prop where
  | done : IsValue e → Progress e
  | step : Step e e' → Progress e

-- ============================================================================
-- 5. Progress
-- ============================================================================

theorem progress {Γ : Ctx} {e : Expr} {τ : Ty} (ht : HasType Γ e τ) : Progress e := by
  induction ht with
  | tLit => exact .done .litV
  | tUnit => exact .done .unitV
  | tField _ => exact .done .fieldV
  | tAggCount => exact .done .aggV
  | tAggSumI _ => exact .done .aggV
  | tAggSumF _ => exact .done .aggV
  | tAggAvg _ => exact .done .aggV
  | tAggMinMax _ _ => exact .done .aggV
  | tSelect => exact .done .selectV
  | tSelectP => exact .done .selectPV
  | tProofW => exact .done .proofWV
  | tPair _ _ ih₁ ih₂ =>
    cases ih₁ with
    | done hv₁ =>
      cases ih₂ with
      | done hv₂ => exact .done (.pairV hv₁ hv₂)
      | step hs₂ => exact .step (.pairStepR hv₁ hs₂)
    | step hs₁ => exact .step (.pairStepL hs₁)
  | tFst hSigma ih =>
    cases ih with
    | done hv =>
      cases hSigma with
      | tPair h1 h2 =>
        cases hv with
        | pairV hv1 hv2 => exact .step (.fstPair hv1 hv2)
      | tSelectP =>
        exact .step .fstSelectP
      | tFst _ => cases hv
      | tSnd _ => cases hv
    | step hs => exact .step (.fstStep hs)
  | tSnd hSigma ih =>
    cases ih with
    | done hv =>
      cases hSigma with
      | tPair h1 h2 =>
        cases hv with
        | pairV hv1 hv2 => exact .step (.sndPair hv1 hv2)
      | tSelectP =>
        exact .step .sndSelectP
      | tFst _ => cases hv
      | tSnd _ => cases hv
    | step hs => exact .step (.sndStep hs)

-- ============================================================================
-- 6. Preservation
-- ============================================================================

theorem preservation {Γ : Ctx} {e e' : Expr} {τ : Ty}
    (ht : HasType Γ e τ) (hs : Step e e') : HasType Γ e' τ := by
  induction hs generalizing τ with
  | fstPair hv₁ hv₂ =>
    cases ht with
    | tFst hSigma =>
      cases hSigma with
      | tPair h1 _ => exact h1
  | sndPair hv₁ hv₂ =>
    cases ht with
    | tSnd hSigma =>
      cases hSigma with
      | tPair _ h2 => exact h2
  | fstSelectP =>
    cases ht with
    | tFst hSigma =>
      cases hSigma with
      | tSelectP => exact .tSelect
  | sndSelectP =>
    cases ht with
    | tSnd hSigma =>
      cases hSigma with
      | tSelectP => exact .tProofW
  | fstStep hsInner ih =>
    cases ht with
    | tFst hSigma => exact .tFst (ih hSigma)
  | sndStep hsInner ih =>
    cases ht with
    | tSnd hSigma => exact .tSnd (ih hSigma)
  | pairStepL hsL ih =>
    cases ht with
    | tPair h1 h2 => exact .tPair (ih h1) h2
  | pairStepR hv hsR ih =>
    cases ht with
    | tPair h1 h2 => exact .tPair h1 (ih h2)

-- ============================================================================
-- 7. Multi-step soundness corollary
-- ============================================================================

inductive Steps : Expr → Expr → Prop where
  | refl : Steps e e
  | trans : Step e e' → Steps e' e'' → Steps e e''

theorem preservationSteps {Γ : Ctx} {e e' : Expr} {τ : Ty}
    (ht : HasType Γ e τ) (hs : Steps e e') : HasType Γ e' τ := by
  induction hs with
  | refl => exact ht
  | trans hstep hrest ih =>
    exact ih (preservation ht hstep)

def HasTypeVal (v : Expr) (τ : Ty) : Prop := HasType Ctx.empty v τ ∧ IsValue v

theorem type_soundness {e v : Expr} {τ : Ty}
    (ht : HasType Ctx.empty e τ)
    (hs : Steps e v)
    (hv : IsValue v) :
    HasTypeVal v τ := by
  exact ⟨preservationSteps ht hs, hv⟩

-- ============================================================================
-- 8. Bidirectional synthesis/checking soundness
-- ============================================================================

inductive SubTy : Ty → Ty → Prop where
  | refl : SubTy τ τ
  | provedForget :
      SubTy (.sigma (.queryRes ms) (.proof pk c)) (.queryRes ms)

theorem subTy_trans {a b c : Ty} (h₁ : SubTy a b) (h₂ : SubTy b c) : SubTy a c := by
  cases h₁ with
  | refl => exact h₂
  | provedForget =>
    cases h₂ with
    | refl => exact .provedForget

inductive Synth : Ctx → Expr → Ty → Prop where
  | fromTyping : HasType Γ e τ → Synth Γ e τ

inductive Check : Ctx → Expr → Ty → Prop where
  | exact   : Synth Γ e τ → Check Γ e τ
  | subsume : Synth Γ e τ → SubTy τ τ' → Check Γ e τ'

theorem synth_sound {Γ : Ctx} {e : Expr} {τ : Ty}
    (hs : Synth Γ e τ) : HasType Γ e τ := by
  cases hs with
  | fromTyping ht => exact ht

theorem check_sound {Γ : Ctx} {e : Expr} {τ : Ty}
    (hc : Check Γ e τ) : ∃ τ', HasType Γ e τ' ∧ SubTy τ' τ := by
  cases hc with
  | exact hs =>
    exact ⟨τ, synth_sound hs, .refl⟩
  | subsume hs hsub =>
    exact ⟨_, synth_sound hs, hsub⟩

end VCLTypeSoundness
