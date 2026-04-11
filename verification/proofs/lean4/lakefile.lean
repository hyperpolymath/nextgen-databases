-- SPDX-License-Identifier: PMPL-1.0-or-later
import Lake
open Lake DSL

package verisimdb_proofs where
  name := "verisimdb_proofs"

lean_lib VeriSimDBProofs where
  roots := #[`VCLSubtyping, `RaftSafety]
