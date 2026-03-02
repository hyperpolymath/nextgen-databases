// SPDX-License-Identifier: PMPL-1.0-or-later
//! Planner error types.

use thiserror::Error;

/// Errors that can occur during query planning.
#[derive(Error, Debug)]
pub enum PlannerError {
    #[error("empty plan: no modality nodes to optimize")]
    EmptyPlan,

    #[error("unknown modality: {0}")]
    UnknownModality(String),

    #[error("invalid configuration: {0}")]
    InvalidConfig(String),

    #[error("cost estimation failed: {0}")]
    CostEstimation(String),

    #[error("serialization error: {0}")]
    Serialization(#[from] serde_json::Error),
}
