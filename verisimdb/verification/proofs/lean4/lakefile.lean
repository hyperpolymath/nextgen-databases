-- SPDX-License-Identifier: MPL-2.0
import Lake
open Lake DSL

package verisimdb_proofs where
  name := `verisimdb_proofs

lean_lib VeriSimDBProofs where
  roots := #[`VCLSubtyping, `VCLTypeSoundness, `RaftSafety, `WALIntegrity]
