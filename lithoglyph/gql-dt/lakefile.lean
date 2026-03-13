-- SPDX-License-Identifier: PMPL-1.0
-- SPDX-FileCopyrightText: 2025 hyperpolymath
--
-- lakefile.lean - Lake build configuration for GQLdt

import Lake
open Lake DSL

package fqldt where
  leanOptions := #[
    ⟨`pp.unicode.fun, true⟩,  -- Use unicode λ in pretty printing
    ⟨`autoImplicit, false⟩    -- Require explicit type annotations
  ]

-- Mathlib4 for tactics (omega, simp, etc.) and proof automation
require mathlib from git
  "https://github.com/leanprover-community/mathlib4" @ "v4.15.0"

-- Main library
@[default_target]
lean_lib FbqlDt where
  srcDir := "src"
  roots := #[`FbqlDt]

-- FFI Test executable (requires Zig library to be built first)
-- Build Zig lib: cd bridge && zig build
lean_exe ffi_test where
  srcDir := "test"
  root := `FFITest
  -- Link against the Zig FFI bridge library
  moreLinkArgs := #[
    "-Lbridge/zig-out/lib",
    "-lfdb_bridge"
  ]

-- Parser test executable
lean_exe parser_test where
  srcDir := "test"
  root := `ParserTest

-- GQLdt CLI/REPL (with FFI persistence backend)
lean_exe fqldt where
  srcDir := "src"
  root := `Main
  -- Link against the Zig FFI bridge library for persistence
  moreLinkArgs := #[
    "-Lbridge/zig-out/lib",
    "-lfdb_bridge"
  ]
