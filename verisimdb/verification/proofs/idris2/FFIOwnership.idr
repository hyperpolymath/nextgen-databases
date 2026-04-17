-- SPDX-License-Identifier: PMPL-1.0-or-later
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)
--
-- FFIOwnership.idr - V12: FFI pointer validity + ownership discipline.
--
-- Scope (spec V12):
--   (1) Non-null before dereference.
--   (2) Ownership state is explicit in the type.
--   (3) Double-free is blocked by type shape (`free` only accepts Alive).

module FFIOwnership

%default total

------------------------------------------------------------------------
-- Ownership state
------------------------------------------------------------------------

public export
data PtrState : Type where
  Alive : PtrState
  Freed : PtrState

------------------------------------------------------------------------
-- Raw pointer model + non-null witness
------------------------------------------------------------------------

public export
record RawPtr where
  constructor MkRawPtr
  addr : Nat

public export
data NonNull : Nat -> Type where
  IsNonNull : (k : Nat) -> NonNull (S k)

------------------------------------------------------------------------
-- Owned pointer token
------------------------------------------------------------------------

||| Ownership token indexed by pointer state.
|||
||| - `Owned Alive` carries a non-null proof.
||| - `Owned Freed` is a tombstone token that cannot be dereferenced or freed.
public export
record Owned (st : PtrState) where
  constructor MkOwned
  raw : RawPtr
  nonNull : case st of
              Alive => NonNull raw.addr
              Freed => ()

------------------------------------------------------------------------
-- Core API
------------------------------------------------------------------------

||| Allocate an owned pointer token from a non-zero address witness.
public export
alloc : (addr : Nat) -> NonNull addr -> Owned Alive
alloc addr nn = MkOwned (MkRawPtr addr) nn

||| Free consumes an `Alive` token and returns a `Freed` tombstone token.
||| No function in this module turns `Freed` back into `Alive`.
public export
free : Owned Alive -> Owned Freed
free (MkOwned rp _) = MkOwned rp ()

||| Dereference is only available for `Alive` tokens.
public export
derefAddr : Owned Alive -> Nat
derefAddr (MkOwned rp _) = rp.addr

------------------------------------------------------------------------
-- Proof obligations
------------------------------------------------------------------------

||| Non-null invariant for dereference: every dereference target is provably non-zero.
public export
derefNonNull : (o : Owned Alive) -> NonNull (derefAddr o)
derefNonNull (MkOwned _ nn) = nn

||| Capability witness: only `Alive` pointers are freeable.
public export
data CanFree : PtrState -> Type where
  FreeAlive : CanFree Alive

||| There is no capability to free a `Freed` token.
public export
noCanFreeFreed : CanFree Freed -> Void
noCanFreeFreed FreeAlive impossible

||| Freeing requires the `Alive` capability at the type level.
public export
freeWithCap : (st : PtrState) -> CanFree st -> Owned st -> Owned Freed
freeWithCap Alive FreeAlive o = free o

||| "Double free is impossible" witness: a second free would need `CanFree Freed`,
||| but that type is uninhabited.
public export
doubleFreeImpossible : (o : Owned Freed) -> CanFree Freed -> Void
doubleFreeImpossible _ cap = noCanFreeFreed cap

------------------------------------------------------------------------
-- Sanity checks
------------------------------------------------------------------------

public export
allocOneNonNull : derefNonNull (alloc 1 (IsNonNull 0)) = IsNonNull 0
allocOneNonNull = Refl

public export
freePreservesAddress : (o : Owned Alive) -> (free o).raw.addr = o.raw.addr
freePreservesAddress (MkOwned _ _) = Refl
