-- SPDX-License-Identifier: PMPL-1.0
-- SPDX-FileCopyrightText: 2025 hyperpolymath
--
-- FqlDt.FFI - Foreign Function Interface module
--
-- Exports the Zig FFI bridge bindings for Lithoglyph operations.

import FbqlDt.FFI.Bridge

namespace FqlDt.FFI

-- Re-export from Bridge namespace
export FqlDt.FFI.FdbStatus (fromInt toInt isOk message)
export FqlDt.FFI.PromptScoresFFI (zero isValid)
export FqlDt.FFI.InsertResponseFFI (status isOk)
export FqlDt.FFI.InsertResult (success failure)

-- Re-export types and functions
open FqlDt.FFI in
def fdbStatus := FdbStatus
def promptScoresFFI := PromptScoresFFI
def insertResponseFFI := InsertResponseFFI
def insertResult := InsertResult
def proofVerifyResult := ProofVerifyResult

end FqlDt.FFI
