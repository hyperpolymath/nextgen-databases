-- SPDX-License-Identifier: PMPL-1.0-or-later
-- SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (@hyperpolymath)
--
-- GQL-DT - Lithoglyph Query Language with Dependent Types
--
-- This module provides compile-time verification of database constraints
-- through dependent types, enabling:
-- - Bounded values (BoundedNat, BoundedFloat) with proofs
-- - Non-empty strings (NonEmptyString, Rationale) with proofs
-- - Provenance tracking (Tracked) with type-level guarantees
-- - PROMPT score verification (PromptScores) with auto-computation
-- - Type-safe query construction (AST, TypeSafe)
-- - Two-tier architecture (GQL-DT + GQL)
-- - Native IR execution (preserves dependent types)

-- ============================================================================
-- Core Refinement Types
-- ============================================================================

import FbqlDt.Types
import FbqlDt.Types.BoundedNat
import FbqlDt.Types.BoundedInt
import FbqlDt.Types.NonEmptyString
import FbqlDt.Types.Confidence

-- ============================================================================
-- PROMPT Score Types
-- ============================================================================

import FbqlDt.Prompt
import FbqlDt.Prompt.PromptDimension
import FbqlDt.Prompt.PromptScores

-- ============================================================================
-- Provenance Tracking
-- ============================================================================

import FbqlDt.Provenance
import FbqlDt.Provenance.ActorId
import FbqlDt.Provenance.Rationale
import FbqlDt.Provenance.Tracked

-- ============================================================================
-- Type-Safe Query Construction
-- ============================================================================

import FbqlDt.AST
import FbqlDt.TypeSafe
import FbqlDt.TypeChecker
import FbqlDt.TypeSafeQueries

-- ============================================================================
-- Parser & Type Inference (M6)
-- ============================================================================

import FbqlDt.Lexer
import FbqlDt.Parser
import FbqlDt.TypeInference
import FbqlDt.IR
import FbqlDt.Serialization.Types
import FbqlDt.Serialization
import FbqlDt.Pipeline

-- ============================================================================
-- FFI Bridge (Zig bindings)
-- ============================================================================

-- Note: Requires libfdb_bridge.a to be linked for runtime use
import FbqlDt.FFI
import FbqlDt.FFI.Bridge

-- ============================================================================
-- Query Language (Legacy modules)
-- ============================================================================

import FbqlDt.Query
import FbqlDt.Query.AST
import FbqlDt.Query.Parser
import FbqlDt.Query.TypeCheck
import FbqlDt.Query.Eval
import FbqlDt.Query.Store
import FbqlDt.Query.Schema
