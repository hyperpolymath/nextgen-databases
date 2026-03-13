-- SPDX-License-Identifier: PMPL-1.0
-- SPDX-FileCopyrightText: 2025 hyperpolymath
--
-- GqlDt.FFI - Foreign Function Interface module
--
-- Exports the Zig FFI bridge bindings for Lithoglyph operations.

import GqlDt.FFI.Bridge

namespace GqlDt.FFI

-- Re-export from Bridge namespace
export GqlDt.FFI.LithStatus (fromInt toInt isOk message)
export GqlDt.FFI.PromptScoresFFI (zero isValid)
export GqlDt.FFI.InsertResponseFFI (status isOk)
export GqlDt.FFI.InsertResult (success failure)

-- Re-export types and functions
open GqlDt.FFI in
def lithStatus := LithStatus
def promptScoresFFI := PromptScoresFFI
def insertResponseFFI := InsertResponseFFI
def insertResult := InsertResult
def proofVerifyResult := ProofVerifyResult

end GqlDt.FFI
