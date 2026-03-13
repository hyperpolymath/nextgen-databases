-- SPDX-License-Identifier: PMPL-1.0-or-later
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)
--
-- lakefile.lean - Lake build configuration for Form.Normalizer
--
-- Proof-carrying normalisation engine for Lithoglyph.
-- Provides functional dependency types, normal form predicates,
-- 3NF synthesis, BCNF decomposition, and FFI bridge to Zig core.

import Lake
open Lake DSL

package formNormalizer where
  leanOptions := #[
    ⟨`pp.unicode.fun, true⟩,  -- Use unicode λ in pretty printing
    ⟨`autoImplicit, false⟩    -- Require explicit type annotations
  ]

-- Main library: FunDep types, Bridge FFI, and Proofs integration
@[default_target]
lean_lib FormNormalizer where
  srcDir := "lean"
  roots := #[`FunDep, `Bridge, `Proofs]

-- Test executable (52 #eval assertions)
lean_exe tests where
  srcDir := "lean"
  root := `Tests
