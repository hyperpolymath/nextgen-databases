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

import GqlDt.Types
import GqlDt.Types.BoundedNat
import GqlDt.Types.BoundedInt
import GqlDt.Types.NonEmptyString
import GqlDt.Types.Confidence

-- ============================================================================
-- PROMPT Score Types
-- ============================================================================

import GqlDt.Prompt
import GqlDt.Prompt.PromptDimension
import GqlDt.Prompt.PromptScores

-- ============================================================================
-- Provenance Tracking
-- ============================================================================

import GqlDt.Provenance
import GqlDt.Provenance.ActorId
import GqlDt.Provenance.Rationale
import GqlDt.Provenance.Tracked

-- ============================================================================
-- Type-Safe Query Construction
-- ============================================================================

import GqlDt.AST
import GqlDt.TypeSafe
import GqlDt.TypeChecker
import GqlDt.TypeSafeQueries

-- ============================================================================
-- Parser & Type Inference (M6)
-- ============================================================================

import GqlDt.Lexer
import GqlDt.Parser
import GqlDt.TypeInference
import GqlDt.IR
import GqlDt.Serialization.Types
import GqlDt.Serialization
import GqlDt.Pipeline

-- ============================================================================
-- FFI Bridge (Zig bindings)
-- ============================================================================

-- Note: Requires liblith_bridge.a to be linked for runtime use
import GqlDt.FFI
import GqlDt.FFI.Bridge

-- ============================================================================
-- Query Language (Legacy modules)
-- ============================================================================

import GqlDt.Query
import GqlDt.Query.AST
import GqlDt.Query.Parser
import GqlDt.Query.TypeCheck
import GqlDt.Query.Eval
import GqlDt.Query.Store
import GqlDt.Query.Schema
