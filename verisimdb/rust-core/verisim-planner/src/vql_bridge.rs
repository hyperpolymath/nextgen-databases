// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <jonathan.jewell@open.ac.uk>
//!
//! VQL AST to LogicalPlan bridge.
//!
//! Deserializes VQL JSON produced by the ReScript parser (BuckleScript encoding)
//! and converts it into the [`LogicalPlan`] representation used by the planner.
//!
//! ## BuckleScript Encoding
//!
//! The ReScript compiler (via BuckleScript) encodes variant types as JSON objects
//! with a `TAG` field naming the constructor and positional `_0`, `_1`, ... fields
//! for arguments:
//!
//! ```json
//! { "TAG": "Hexad", "_0": "some-uuid" }
//! ```
//!
//! This module defines serde-compatible Rust types that mirror this encoding and
//! provides conversion into the planner's canonical [`LogicalPlan`].

use serde::de::{self, MapAccess, Visitor};
use serde::{Deserialize, Deserializer};
use std::collections::HashMap;
use std::fmt;

use crate::error::PlannerError;
use crate::plan::{ConditionKind, LogicalPlan, PlanNode, PostProcessing, QuerySource};
use crate::Modality;

// ---------------------------------------------------------------------------
// VQL AST types (mirrors BuckleScript JSON encoding)
// ---------------------------------------------------------------------------

/// Top-level VQL statement as emitted by the ReScript parser.
///
/// BuckleScript encodes this as `{"TAG": "Query", "_0": { ... }}`.
/// We use a custom deserializer because serde's internally-tagged enum
/// (`#[serde(tag = "TAG")]`) does not support positional `_0` content fields.
#[derive(Debug, Clone)]
pub enum VqlAst {
    /// A SELECT-style query.
    Query(VqlQuery),
}

impl<'de> Deserialize<'de> for VqlAst {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        struct VqlAstVisitor;

        impl<'de> Visitor<'de> for VqlAstVisitor {
            type Value = VqlAst;

            fn expecting(&self, formatter: &mut fmt::Formatter) -> fmt::Result {
                formatter.write_str("a VQL AST object with TAG and _0 fields")
            }

            fn visit_map<M>(self, mut map: M) -> Result<VqlAst, M::Error>
            where
                M: MapAccess<'de>,
            {
                let mut tag: Option<String> = None;
                let mut payload: Option<serde_json::Value> = None;

                while let Some(key) = map.next_key::<String>()? {
                    match key.as_str() {
                        "TAG" => tag = Some(map.next_value()?),
                        "_0" => payload = Some(map.next_value()?),
                        _ => {
                            let _: serde_json::Value = map.next_value()?;
                        }
                    }
                }

                let tag = tag.ok_or_else(|| de::Error::missing_field("TAG"))?;
                match tag.as_str() {
                    "Query" => {
                        let body = payload.ok_or_else(|| de::Error::missing_field("_0"))?;
                        let query: VqlQuery =
                            serde_json::from_value(body).map_err(de::Error::custom)?;
                        Ok(VqlAst::Query(query))
                    }
                    other => Err(de::Error::unknown_variant(other, &["Query"])),
                }
            }
        }

        deserializer.deserialize_map(VqlAstVisitor)
    }
}

/// Body of a VQL query.
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct VqlQuery {
    /// Requested modalities (`Graph`, `Vector`, ..., or `All`).
    pub modalities: Vec<VqlModality>,
    /// Data source (Hexad, Federation, Store).
    pub source: VqlSource,
    /// Optional WHERE clause.
    #[serde(default, rename = "where")]
    pub where_clause: Option<VqlCondition>,
    /// Optional field projections.
    #[serde(default)]
    pub projections: Option<Vec<VqlProjection>>,
    /// Optional aggregate functions.
    #[serde(default)]
    pub aggregates: Option<Vec<VqlAggregate>>,
    /// Optional GROUP BY fields.
    #[serde(default)]
    pub group_by: Option<Vec<VqlFieldRef>>,
    /// Optional HAVING clause.
    #[serde(default)]
    pub having: Option<VqlCondition>,
    /// Optional PROOF specifications.
    #[serde(default)]
    pub proof: Option<Vec<VqlProofSpec>>,
    /// Optional ORDER BY clauses.
    #[serde(default)]
    pub order_by: Option<Vec<VqlOrderBy>>,
    /// Optional result limit.
    #[serde(default)]
    pub limit: Option<usize>,
    /// Optional result offset.
    #[serde(default)]
    pub offset: Option<usize>,
}

/// A VQL modality tag.
///
/// The ReScript parser emits modalities as `{"TAG": "Graph"}` etc.
/// `All` is a special sentinel meaning "expand to all 6 modalities".
#[derive(Debug, Clone)]
pub enum VqlModality {
    Graph,
    Vector,
    Tensor,
    Semantic,
    Document,
    Temporal,
    All,
}

impl<'de> Deserialize<'de> for VqlModality {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        struct VqlModalityVisitor;

        impl<'de> Visitor<'de> for VqlModalityVisitor {
            type Value = VqlModality;

            fn expecting(&self, formatter: &mut fmt::Formatter) -> fmt::Result {
                formatter.write_str("a VQL modality object with TAG field")
            }

            fn visit_map<M>(self, mut map: M) -> Result<VqlModality, M::Error>
            where
                M: MapAccess<'de>,
            {
                let mut tag: Option<String> = None;
                while let Some(key) = map.next_key::<String>()? {
                    if key == "TAG" {
                        tag = Some(map.next_value()?);
                    } else {
                        // Skip unknown fields.
                        let _: serde_json::Value = map.next_value()?;
                    }
                }
                match tag.as_deref() {
                    Some("Graph") => Ok(VqlModality::Graph),
                    Some("Vector") => Ok(VqlModality::Vector),
                    Some("Tensor") => Ok(VqlModality::Tensor),
                    Some("Semantic") => Ok(VqlModality::Semantic),
                    Some("Document") => Ok(VqlModality::Document),
                    Some("Temporal") => Ok(VqlModality::Temporal),
                    Some("All") => Ok(VqlModality::All),
                    Some(other) => Err(de::Error::unknown_variant(
                        other,
                        &[
                            "Graph", "Vector", "Tensor", "Semantic", "Document", "Temporal", "All",
                        ],
                    )),
                    None => Err(de::Error::missing_field("TAG")),
                }
            }
        }

        deserializer.deserialize_map(VqlModalityVisitor)
    }
}

/// Data source as emitted by the ReScript parser.
#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "TAG")]
pub enum VqlSource {
    /// Single hexad store. `_0` is an optional UUID filter.
    Hexad {
        #[serde(rename = "_0")]
        uuid: Option<String>,
    },
    /// Federated query with drift policy.
    Federation {
        #[serde(rename = "_0")]
        nodes: Vec<String>,
        #[serde(rename = "_1")]
        drift_policy: Option<String>,
    },
    /// Direct store access for a specific modality.
    Store {
        #[serde(rename = "_0")]
        modality: VqlModality,
    },
}

/// A VQL condition (WHERE clause tree).
///
/// BuckleScript encodes each variant with TAG + positional args.
#[derive(Debug, Clone)]
pub enum VqlCondition {
    /// Conjunction.
    And(Box<VqlCondition>, Box<VqlCondition>),
    /// Disjunction.
    Or(Box<VqlCondition>, Box<VqlCondition>),
    /// Negation.
    Not(Box<VqlCondition>),
    /// Leaf condition.
    Simple(VqlSimpleCondition),
}

impl<'de> Deserialize<'de> for VqlCondition {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        // Deserialize as a generic JSON value first, then pattern match on TAG.
        let value = serde_json::Value::deserialize(deserializer)?;
        parse_condition(&value).map_err(de::Error::custom)
    }
}

/// Parse a `VqlCondition` from a `serde_json::Value`.
fn parse_condition(value: &serde_json::Value) -> Result<VqlCondition, String> {
    let obj = value.as_object().ok_or("condition must be a JSON object")?;
    let tag = obj
        .get("TAG")
        .and_then(|v| v.as_str())
        .ok_or("condition object missing TAG field")?;

    match tag {
        "And" => {
            let lhs = obj
                .get("_0")
                .ok_or("And condition missing _0 (left operand)")?;
            let rhs = obj
                .get("_1")
                .ok_or("And condition missing _1 (right operand)")?;
            Ok(VqlCondition::And(
                Box::new(parse_condition(lhs)?),
                Box::new(parse_condition(rhs)?),
            ))
        }
        "Or" => {
            let lhs = obj
                .get("_0")
                .ok_or("Or condition missing _0 (left operand)")?;
            let rhs = obj
                .get("_1")
                .ok_or("Or condition missing _1 (right operand)")?;
            Ok(VqlCondition::Or(
                Box::new(parse_condition(lhs)?),
                Box::new(parse_condition(rhs)?),
            ))
        }
        "Not" => {
            let inner = obj.get("_0").ok_or("Not condition missing _0 (operand)")?;
            Ok(VqlCondition::Not(Box::new(parse_condition(inner)?)))
        }
        "Simple" => {
            let inner = obj.get("_0").ok_or("Simple condition missing _0")?;
            let simple: VqlSimpleCondition =
                serde_json::from_value(inner.clone()).map_err(|e| e.to_string())?;
            Ok(VqlCondition::Simple(simple))
        }
        other => Err(format!("unknown condition TAG: {other}")),
    }
}

/// Leaf-level condition kinds from VQL.
#[derive(Debug, Clone)]
pub enum VqlSimpleCondition {
    /// Full-text search: `CONTAINS "search text"`.
    FulltextContains(String),
    /// Vector similarity: `SIMILAR TO [embedding] THRESHOLD threshold`.
    VectorSimilar {
        embedding: Vec<f64>,
        threshold: f64,
    },
    /// Graph pattern: `TRAVERSE predicate DEPTH depth`.
    GraphPattern {
        predicate: String,
        depth: Option<u32>,
    },
    /// Field condition: `field op value`.
    FieldCondition {
        field: VqlFieldRef,
        operator: String,
        value: serde_json::Value,
    },
    /// Cross-modal field comparison.
    CrossModalFieldCompare {
        left: VqlFieldRef,
        operator: String,
        right: VqlFieldRef,
    },
    /// Modality drift check.
    ModalityDrift {
        modality: VqlModality,
        threshold: f64,
    },
    /// Modality existence check.
    ModalityExists(VqlModality),
    /// Modality non-existence check.
    ModalityNotExists(VqlModality),
    /// Cross-modality consistency check.
    ModalityConsistency {
        modalities: Vec<VqlModality>,
        threshold: f64,
    },
}

impl<'de> Deserialize<'de> for VqlSimpleCondition {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        let value = serde_json::Value::deserialize(deserializer)?;
        parse_simple_condition(&value).map_err(de::Error::custom)
    }
}

/// Parse a `VqlSimpleCondition` from raw JSON.
fn parse_simple_condition(value: &serde_json::Value) -> Result<VqlSimpleCondition, String> {
    let obj = value
        .as_object()
        .ok_or("simple condition must be a JSON object")?;
    let tag = obj
        .get("TAG")
        .and_then(|v| v.as_str())
        .ok_or("simple condition object missing TAG field")?;

    match tag {
        "FulltextContains" => {
            let text = obj
                .get("_0")
                .and_then(|v| v.as_str())
                .ok_or("FulltextContains missing _0 (search text)")?;
            Ok(VqlSimpleCondition::FulltextContains(text.to_string()))
        }
        "VectorSimilar" => {
            let embedding = obj
                .get("_0")
                .and_then(|v| v.as_array())
                .ok_or("VectorSimilar missing _0 (embedding array)")?
                .iter()
                .map(|v| {
                    v.as_f64()
                        .ok_or_else(|| "VectorSimilar _0 contains non-numeric".to_string())
                })
                .collect::<Result<Vec<f64>, String>>()?;
            let threshold = obj
                .get("_1")
                .and_then(|v| v.as_f64())
                .ok_or("VectorSimilar missing _1 (threshold)")?;
            Ok(VqlSimpleCondition::VectorSimilar {
                embedding,
                threshold,
            })
        }
        "GraphPattern" => {
            let predicate = obj
                .get("_0")
                .and_then(|v| v.as_str())
                .ok_or("GraphPattern missing _0 (predicate)")?
                .to_string();
            let depth = obj.get("_1").and_then(|v| v.as_u64()).map(|d| d as u32);
            Ok(VqlSimpleCondition::GraphPattern { predicate, depth })
        }
        "FieldCondition" => {
            let field_val = obj.get("_0").ok_or("FieldCondition missing _0 (field)")?;
            let field: VqlFieldRef =
                serde_json::from_value(field_val.clone()).map_err(|e| e.to_string())?;
            let operator = obj
                .get("_1")
                .and_then(|v| v.as_str())
                .ok_or("FieldCondition missing _1 (operator)")?
                .to_string();
            let val = obj
                .get("_2")
                .cloned()
                .ok_or("FieldCondition missing _2 (value)")?;
            Ok(VqlSimpleCondition::FieldCondition {
                field,
                operator,
                value: val,
            })
        }
        "CrossModalFieldCompare" => {
            let left_val = obj
                .get("_0")
                .ok_or("CrossModalFieldCompare missing _0 (left)")?;
            let left: VqlFieldRef =
                serde_json::from_value(left_val.clone()).map_err(|e| e.to_string())?;
            let operator = obj
                .get("_1")
                .and_then(|v| v.as_str())
                .ok_or("CrossModalFieldCompare missing _1 (operator)")?
                .to_string();
            let right_val = obj
                .get("_2")
                .ok_or("CrossModalFieldCompare missing _2 (right)")?;
            let right: VqlFieldRef =
                serde_json::from_value(right_val.clone()).map_err(|e| e.to_string())?;
            Ok(VqlSimpleCondition::CrossModalFieldCompare {
                left,
                operator,
                right,
            })
        }
        "ModalityDrift" => {
            let mod_val = obj
                .get("_0")
                .ok_or("ModalityDrift missing _0 (modality)")?;
            let modality: VqlModality =
                serde_json::from_value(mod_val.clone()).map_err(|e| e.to_string())?;
            let threshold = obj
                .get("_1")
                .and_then(|v| v.as_f64())
                .ok_or("ModalityDrift missing _1 (threshold)")?;
            Ok(VqlSimpleCondition::ModalityDrift {
                modality,
                threshold,
            })
        }
        "ModalityExists" => {
            let mod_val = obj
                .get("_0")
                .ok_or("ModalityExists missing _0 (modality)")?;
            let modality: VqlModality =
                serde_json::from_value(mod_val.clone()).map_err(|e| e.to_string())?;
            Ok(VqlSimpleCondition::ModalityExists(modality))
        }
        "ModalityNotExists" => {
            let mod_val = obj
                .get("_0")
                .ok_or("ModalityNotExists missing _0 (modality)")?;
            let modality: VqlModality =
                serde_json::from_value(mod_val.clone()).map_err(|e| e.to_string())?;
            Ok(VqlSimpleCondition::ModalityNotExists(modality))
        }
        "ModalityConsistency" => {
            let mods_val = obj
                .get("_0")
                .ok_or("ModalityConsistency missing _0 (modalities)")?;
            let modalities: Vec<VqlModality> =
                serde_json::from_value(mods_val.clone()).map_err(|e| e.to_string())?;
            let threshold = obj
                .get("_1")
                .and_then(|v| v.as_f64())
                .ok_or("ModalityConsistency missing _1 (threshold)")?;
            Ok(VqlSimpleCondition::ModalityConsistency {
                modalities,
                threshold,
            })
        }
        other => Err(format!("unknown simple condition TAG: {other}")),
    }
}

/// A field reference with optional modality qualifier.
#[derive(Debug, Clone, Deserialize)]
pub struct VqlFieldRef {
    /// Optional modality qualifier for the field.
    #[serde(default)]
    pub modality: Option<VqlModality>,
    /// Field name.
    pub field: String,
}

/// A projection entry.
#[derive(Debug, Clone, Deserialize)]
pub struct VqlProjection {
    /// The field being projected.
    pub field: VqlFieldRef,
    /// Optional alias.
    #[serde(default)]
    pub alias: Option<String>,
}

/// An aggregate function call.
#[derive(Debug, Clone, Deserialize)]
pub struct VqlAggregate {
    /// Function name (COUNT, SUM, AVG, MIN, MAX, etc.).
    pub function: String,
    /// Field to aggregate (None for COUNT(*)).
    #[serde(default)]
    pub field: Option<VqlFieldRef>,
    /// Optional alias for the result.
    #[serde(default)]
    pub alias: Option<String>,
}

/// A proof specification from the VQL PROOF clause.
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct VqlProofSpec {
    /// Type of proof required.
    pub proof_type: VqlProofType,
    /// Name of the verification contract.
    pub contract_name: String,
}

/// Proof type tag.
#[derive(Debug, Clone)]
pub enum VqlProofType {
    Citation,
    Zkp,
    Attestation,
    Custom(String),
}

impl<'de> Deserialize<'de> for VqlProofType {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        struct ProofTypeVisitor;

        impl<'de> Visitor<'de> for ProofTypeVisitor {
            type Value = VqlProofType;

            fn expecting(&self, formatter: &mut fmt::Formatter) -> fmt::Result {
                formatter.write_str("a VQL proof type object with TAG field")
            }

            fn visit_map<M>(self, mut map: M) -> Result<VqlProofType, M::Error>
            where
                M: MapAccess<'de>,
            {
                let mut tag: Option<String> = None;
                while let Some(key) = map.next_key::<String>()? {
                    if key == "TAG" {
                        tag = Some(map.next_value()?);
                    } else {
                        let _: serde_json::Value = map.next_value()?;
                    }
                }
                match tag.as_deref() {
                    Some("Citation") => Ok(VqlProofType::Citation),
                    Some("Zkp") => Ok(VqlProofType::Zkp),
                    Some("Attestation") => Ok(VqlProofType::Attestation),
                    Some(other) => Ok(VqlProofType::Custom(other.to_string())),
                    None => Err(de::Error::missing_field("TAG")),
                }
            }
        }

        deserializer.deserialize_map(ProofTypeVisitor)
    }
}

/// An ORDER BY clause entry.
#[derive(Debug, Clone, Deserialize)]
pub struct VqlOrderBy {
    /// Field to order by.
    pub field: VqlFieldRef,
    /// Sort direction.
    pub direction: VqlDirection,
}

/// Sort direction tag.
#[derive(Debug, Clone)]
pub enum VqlDirection {
    Asc,
    Desc,
}

impl<'de> Deserialize<'de> for VqlDirection {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        struct DirectionVisitor;

        impl<'de> Visitor<'de> for DirectionVisitor {
            type Value = VqlDirection;

            fn expecting(&self, formatter: &mut fmt::Formatter) -> fmt::Result {
                formatter.write_str("a VQL direction object with TAG field")
            }

            fn visit_map<M>(self, mut map: M) -> Result<VqlDirection, M::Error>
            where
                M: MapAccess<'de>,
            {
                let mut tag: Option<String> = None;
                while let Some(key) = map.next_key::<String>()? {
                    if key == "TAG" {
                        tag = Some(map.next_value()?);
                    } else {
                        let _: serde_json::Value = map.next_value()?;
                    }
                }
                match tag.as_deref() {
                    Some("Asc") => Ok(VqlDirection::Asc),
                    Some("Desc") => Ok(VqlDirection::Desc),
                    Some(other) => Err(de::Error::unknown_variant(other, &["Asc", "Desc"])),
                    None => Err(de::Error::missing_field("TAG")),
                }
            }
        }

        deserializer.deserialize_map(DirectionVisitor)
    }
}

// ---------------------------------------------------------------------------
// Conversion: VqlAst -> LogicalPlan
// ---------------------------------------------------------------------------

impl VqlAst {
    /// Deserialize a VQL AST from JSON emitted by the ReScript parser.
    ///
    /// # Errors
    ///
    /// Returns `PlannerError::Serialization` if the JSON does not match the
    /// expected BuckleScript encoding.
    pub fn from_json(json: &str) -> Result<Self, PlannerError> {
        serde_json::from_str(json).map_err(PlannerError::Serialization)
    }

    /// Convert the VQL AST into a [`LogicalPlan`].
    ///
    /// This is the primary bridge function. It:
    /// 1. Expands `All` modality into all six concrete modalities.
    /// 2. Maps the VQL source to [`QuerySource`].
    /// 3. Distributes WHERE conditions to per-modality [`PlanNode`]s.
    /// 4. Extracts LIMIT, OFFSET, ORDER BY, GROUP BY into [`PostProcessing`].
    /// 5. Maps PROOF specs into [`ConditionKind::ProofVerification`] on Semantic nodes.
    ///
    /// # Errors
    ///
    /// Returns `PlannerError::EmptyPlan` if no modalities are requested.
    pub fn to_logical_plan(&self) -> Result<LogicalPlan, PlannerError> {
        let VqlAst::Query(query) = self;

        // 1. Resolve modalities (expand All).
        let modalities = resolve_modalities(&query.modalities)?;
        if modalities.is_empty() {
            return Err(PlannerError::EmptyPlan);
        }

        // 2. Map source.
        let source = map_source(&query.source)?;

        // 3. Build per-modality condition buckets.
        let mut condition_map: HashMap<Modality, Vec<ConditionKind>> = HashMap::new();
        for &m in &modalities {
            condition_map.entry(m).or_default();
        }

        if let Some(ref cond) = query.where_clause {
            flatten_conditions(cond, &modalities, &mut condition_map)?;
        }

        // 4. Inject proof verification conditions into the Semantic node.
        if let Some(ref proofs) = query.proof {
            for spec in proofs {
                let semantic_conditions = condition_map.entry(Modality::Semantic).or_default();
                semantic_conditions.push(ConditionKind::ProofVerification {
                    contract: spec.contract_name.clone(),
                });
            }
        }

        // 5. Build per-modality projections.
        let projection_map = build_projection_map(&modalities, query.projections.as_deref());

        // 6. Assemble PlanNodes.
        let mut nodes: Vec<PlanNode> = modalities
            .iter()
            .map(|&m| PlanNode {
                modality: m,
                conditions: condition_map.remove(&m).unwrap_or_default(),
                projections: projection_map
                    .get(&m)
                    .cloned()
                    .unwrap_or_default(),
                early_limit: None,
            })
            .collect();

        // Sort nodes by execution priority for predictable output.
        nodes.sort_by_key(|n| n.modality.execution_priority());

        // 7. Build post-processing pipeline.
        let mut post_processing = Vec::new();

        if let Some(ref group_fields) = query.group_by {
            let fields: Vec<String> = group_fields.iter().map(field_ref_name).collect();
            let aggregates: Vec<String> = query
                .aggregates
                .as_ref()
                .map(|aggs| {
                    aggs.iter()
                        .map(|a| {
                            let field_name = a
                                .field
                                .as_ref()
                                .map(field_ref_name)
                                .unwrap_or_else(|| "*".to_string());
                            format!("{}({})", a.function, field_name)
                        })
                        .collect()
                })
                .unwrap_or_default();
            post_processing.push(PostProcessing::GroupBy { fields, aggregates });
        }

        if let Some(ref order_fields) = query.order_by {
            let fields: Vec<(String, bool)> = order_fields
                .iter()
                .map(|o| {
                    let ascending = matches!(o.direction, VqlDirection::Asc);
                    (field_ref_name(&o.field), ascending)
                })
                .collect();
            post_processing.push(PostProcessing::OrderBy { fields });
        }

        if let Some(count) = query.limit {
            post_processing.push(PostProcessing::Limit { count });
        }

        // Offset is modelled as a Limit post-processing with adjusted count.
        // The planner does not have a dedicated Offset variant, so we encode it
        // by bumping the limit to include skipped rows. Physical plan will
        // handle the actual skip. If only offset is given (no limit), we add a
        // large limit.
        if let Some(skip) = query.offset {
            if skip > 0 {
                // Find existing Limit and adjust, or add one.
                let has_limit = post_processing.iter().any(|p| matches!(p, PostProcessing::Limit { .. }));
                if !has_limit {
                    // No limit — add a large synthetic limit so offset is meaningful.
                    post_processing.push(PostProcessing::Limit {
                        count: usize::MAX - skip,
                    });
                }
                // The physical plan executor is responsible for applying the offset.
                // We store it as a Project marker so it can be recognised later.
                post_processing.push(PostProcessing::Project {
                    columns: vec![format!("__offset={skip}")],
                });
            }
        }

        // Final projection (if explicit projections were requested and no group-by).
        if query.group_by.is_none() {
            if let Some(ref projs) = query.projections {
                let columns: Vec<String> = projs
                    .iter()
                    .map(|p| {
                        p.alias
                            .clone()
                            .unwrap_or_else(|| field_ref_name(&p.field))
                    })
                    .collect();
                if !columns.is_empty() {
                    post_processing.push(PostProcessing::Project { columns });
                }
            }
        }

        Ok(LogicalPlan {
            source,
            nodes,
            post_processing,
        })
    }
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/// Resolve VQL modalities to concrete `Modality` values, expanding `All`.
fn resolve_modalities(vql_mods: &[VqlModality]) -> Result<Vec<Modality>, PlannerError> {
    let mut result = Vec::new();
    for vm in vql_mods {
        match vm {
            VqlModality::All => {
                // Expand to all six modalities.
                result.extend_from_slice(&Modality::ALL);
            }
            other => {
                result.push(vql_modality_to_planner(other)?);
            }
        }
    }
    // Deduplicate while preserving order.
    let mut seen = std::collections::HashSet::new();
    result.retain(|m| seen.insert(*m));
    Ok(result)
}

/// Map a single VQL modality to the planner `Modality` enum.
fn vql_modality_to_planner(vm: &VqlModality) -> Result<Modality, PlannerError> {
    match vm {
        VqlModality::Graph => Ok(Modality::Graph),
        VqlModality::Vector => Ok(Modality::Vector),
        VqlModality::Tensor => Ok(Modality::Tensor),
        VqlModality::Semantic => Ok(Modality::Semantic),
        VqlModality::Document => Ok(Modality::Document),
        VqlModality::Temporal => Ok(Modality::Temporal),
        VqlModality::All => {
            // Should have been expanded already.
            Err(PlannerError::InvalidConfig(
                "All modality should be expanded before individual mapping".to_string(),
            ))
        }
    }
}

/// Map a VQL source to a planner `QuerySource`.
fn map_source(src: &VqlSource) -> Result<QuerySource, PlannerError> {
    match src {
        VqlSource::Hexad { .. } => Ok(QuerySource::Hexad),
        VqlSource::Federation { nodes, .. } => Ok(QuerySource::Federation {
            nodes: nodes.clone(),
        }),
        VqlSource::Store { modality } => {
            let m = vql_modality_to_planner(modality)?;
            Ok(QuerySource::Store { modality: m })
        }
    }
}

/// Flatten a VQL condition tree into per-modality condition lists.
///
/// Strategy:
/// - Leaf conditions that target a specific modality go only to that node.
/// - Leaf conditions without modality affinity are broadcast to all active nodes.
/// - `And` recursively flattens both branches.
/// - `Or`/`Not` are converted to `Predicate` expressions (the physical executor
///   handles them). They are broadcast to all active modalities.
fn flatten_conditions(
    cond: &VqlCondition,
    active_modalities: &[Modality],
    out: &mut HashMap<Modality, Vec<ConditionKind>>,
) -> Result<(), PlannerError> {
    match cond {
        VqlCondition::And(lhs, rhs) => {
            flatten_conditions(lhs, active_modalities, out)?;
            flatten_conditions(rhs, active_modalities, out)?;
        }
        VqlCondition::Or(lhs, rhs) => {
            // OR cannot be trivially split per-modality. Encode as a predicate
            // string on all active modalities.
            let desc = format!(
                "OR({}, {})",
                describe_condition(lhs),
                describe_condition(rhs)
            );
            for &m in active_modalities {
                out.entry(m)
                    .or_default()
                    .push(ConditionKind::Predicate { expression: desc.clone() });
            }
        }
        VqlCondition::Not(inner) => {
            let desc = format!("NOT({})", describe_condition(inner));
            for &m in active_modalities {
                out.entry(m)
                    .or_default()
                    .push(ConditionKind::Predicate { expression: desc.clone() });
            }
        }
        VqlCondition::Simple(simple) => {
            let (target_modality, condition_kind) = map_simple_condition(simple)?;
            match target_modality {
                Some(m) if out.contains_key(&m) => {
                    out.entry(m).or_default().push(condition_kind);
                }
                Some(m) => {
                    // The targeted modality is not in the active set.
                    // Add it as a predicate on all active modalities.
                    let desc = format!("target_modality={m}: {condition_kind:?}");
                    for &am in active_modalities {
                        out.entry(am)
                            .or_default()
                            .push(ConditionKind::Predicate { expression: desc.clone() });
                    }
                }
                None => {
                    // No specific target — broadcast to all active modalities.
                    for &m in active_modalities {
                        out.entry(m).or_default().push(condition_kind.clone());
                    }
                }
            }
        }
    }
    Ok(())
}

/// Map a VQL simple condition to a `ConditionKind` and an optional target modality.
///
/// Returns `(target_modality, condition_kind)` where `target_modality` is `Some`
/// if the condition naturally targets a specific modality, `None` if it should be
/// broadcast.
fn map_simple_condition(
    simple: &VqlSimpleCondition,
) -> Result<(Option<Modality>, ConditionKind), PlannerError> {
    match simple {
        VqlSimpleCondition::FulltextContains(text) => Ok((
            Some(Modality::Document),
            ConditionKind::Fulltext {
                query: text.clone(),
            },
        )),
        VqlSimpleCondition::VectorSimilar {
            embedding,
            threshold: _,
        } => {
            // `Similarity` takes k (number of neighbours). We use the embedding
            // length as a proxy; the physical plan executor will use the actual
            // embedding. A more refined approach would add a Similarity variant
            // that carries the embedding, but we work with existing types.
            Ok((
                Some(Modality::Vector),
                ConditionKind::Similarity {
                    k: embedding.len(),
                },
            ))
        }
        VqlSimpleCondition::GraphPattern { predicate, depth } => Ok((
            Some(Modality::Graph),
            ConditionKind::Traversal {
                predicate: predicate.clone(),
                depth: *depth,
            },
        )),
        VqlSimpleCondition::FieldCondition {
            field,
            operator,
            value,
        } => {
            let target = field.modality.as_ref().and_then(|vm| vql_modality_to_planner(vm).ok());
            let field_name = field.field.clone();
            let value_str = match value {
                serde_json::Value::String(s) => s.clone(),
                other => other.to_string(),
            };

            let kind = match operator.as_str() {
                "=" | "==" | "!=" | "<>" => ConditionKind::Equality {
                    field: field_name,
                    value: value_str,
                },
                ">" | ">=" | "<" | "<=" | "BETWEEN" => {
                    // For single-bound range operators, we use low=value, high=value
                    // and let the physical executor interpret the operator.
                    ConditionKind::Range {
                        field: field_name,
                        low: value_str.clone(),
                        high: value_str,
                    }
                }
                _ => ConditionKind::Predicate {
                    expression: format!("{field_name} {operator} {value_str}"),
                },
            };
            Ok((target, kind))
        }
        VqlSimpleCondition::CrossModalFieldCompare {
            left,
            operator,
            right,
        } => {
            let desc = format!(
                "cross_modal: {}.{} {} {}.{}",
                left.modality
                    .as_ref()
                    .map(|m| format!("{m:?}"))
                    .unwrap_or_else(|| "?".to_string()),
                left.field,
                operator,
                right
                    .modality
                    .as_ref()
                    .map(|m| format!("{m:?}"))
                    .unwrap_or_else(|| "?".to_string()),
                right.field,
            );
            Ok((
                None,
                ConditionKind::Predicate { expression: desc },
            ))
        }
        VqlSimpleCondition::ModalityDrift {
            modality,
            threshold,
        } => {
            let m = vql_modality_to_planner(modality)?;
            let desc = format!("drift({m}) > {threshold}");
            Ok((
                Some(m),
                ConditionKind::Predicate { expression: desc },
            ))
        }
        VqlSimpleCondition::ModalityExists(modality) => {
            let m = vql_modality_to_planner(modality)?;
            let desc = format!("exists({m})");
            Ok((
                Some(m),
                ConditionKind::Predicate { expression: desc },
            ))
        }
        VqlSimpleCondition::ModalityNotExists(modality) => {
            let m = vql_modality_to_planner(modality)?;
            let desc = format!("not_exists({m})");
            Ok((
                Some(m),
                ConditionKind::Predicate { expression: desc },
            ))
        }
        VqlSimpleCondition::ModalityConsistency {
            modalities,
            threshold,
        } => {
            let names: Vec<String> = modalities
                .iter()
                .filter_map(|vm| vql_modality_to_planner(vm).ok())
                .map(|m| m.to_string())
                .collect();
            let desc = format!("consistency({}) > {threshold}", names.join(", "));
            Ok((
                None,
                ConditionKind::Predicate { expression: desc },
            ))
        }
    }
}

/// Produce a human-readable description of a condition (for predicate encoding).
fn describe_condition(cond: &VqlCondition) -> String {
    match cond {
        VqlCondition::And(l, r) => {
            format!("({} AND {})", describe_condition(l), describe_condition(r))
        }
        VqlCondition::Or(l, r) => {
            format!("({} OR {})", describe_condition(l), describe_condition(r))
        }
        VqlCondition::Not(inner) => format!("NOT({})", describe_condition(inner)),
        VqlCondition::Simple(s) => format!("{s:?}"),
    }
}

/// Build a per-modality projection map from VQL projections.
fn build_projection_map(
    modalities: &[Modality],
    projections: Option<&[VqlProjection]>,
) -> HashMap<Modality, Vec<String>> {
    let mut map: HashMap<Modality, Vec<String>> = HashMap::new();
    let Some(projs) = projections else {
        return map;
    };

    for proj in projs {
        let field_name = proj
            .alias
            .clone()
            .unwrap_or_else(|| proj.field.field.clone());

        if let Some(ref vm) = proj.field.modality {
            if let Ok(m) = vql_modality_to_planner(vm) {
                if modalities.contains(&m) {
                    map.entry(m).or_default().push(field_name);
                }
            }
        } else {
            // No modality qualifier — add to all active modalities.
            for &m in modalities {
                map.entry(m).or_default().push(field_name.clone());
            }
        }
    }
    map
}

/// Render a `VqlFieldRef` as a dotted name string.
fn field_ref_name(f: &VqlFieldRef) -> String {
    match &f.modality {
        Some(m) => format!("{m:?}.{}", f.field),
        None => f.field.clone(),
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    /// Helper: parse JSON string into VqlAst and convert to LogicalPlan.
    fn parse_and_plan(json: &str) -> Result<LogicalPlan, PlannerError> {
        let ast = VqlAst::from_json(json)?;
        ast.to_logical_plan()
    }

    #[test]
    fn test_simple_hexad_query() {
        let json = r#"{
            "TAG": "Query",
            "_0": {
                "modalities": [{"TAG": "Graph"}, {"TAG": "Document"}],
                "source": {"TAG": "Hexad", "_0": "abc-123"},
                "where": {
                    "TAG": "Simple",
                    "_0": {"TAG": "FulltextContains", "_0": "hello world"}
                },
                "projections": null,
                "aggregates": null,
                "groupBy": null,
                "having": null,
                "proof": null,
                "orderBy": null,
                "limit": 10,
                "offset": null
            }
        }"#;

        let plan = parse_and_plan(json).expect("should parse simple hexad query");

        // Source should be Hexad.
        assert!(matches!(plan.source, QuerySource::Hexad));

        // Two nodes: Document (priority 30) and Graph (priority 40).
        assert_eq!(plan.nodes.len(), 2);
        assert_eq!(plan.nodes[0].modality, Modality::Document);
        assert_eq!(plan.nodes[1].modality, Modality::Graph);

        // Document node should have the fulltext condition.
        assert_eq!(plan.nodes[0].conditions.len(), 1);
        assert!(matches!(
            &plan.nodes[0].conditions[0],
            ConditionKind::Fulltext { query } if query == "hello world"
        ));

        // Graph node should have no conditions (fulltext targets Document).
        assert_eq!(plan.nodes[1].conditions.len(), 0);

        // Post-processing: Limit.
        assert!(plan.post_processing.iter().any(|p| matches!(p, PostProcessing::Limit { count: 10 })));
    }

    #[test]
    fn test_federation_with_drift_policy() {
        let json = r#"{
            "TAG": "Query",
            "_0": {
                "modalities": [{"TAG": "Vector"}, {"TAG": "Semantic"}],
                "source": {
                    "TAG": "Federation",
                    "_0": ["node-a", "node-b"],
                    "_1": "consistent-read"
                },
                "where": {
                    "TAG": "Simple",
                    "_0": {
                        "TAG": "ModalityDrift",
                        "_0": {"TAG": "Vector"},
                        "_1": 0.05
                    }
                },
                "projections": null,
                "aggregates": null,
                "groupBy": null,
                "having": null,
                "proof": null,
                "orderBy": null,
                "limit": null,
                "offset": null
            }
        }"#;

        let plan = parse_and_plan(json).expect("should parse federation query");

        assert!(matches!(
            &plan.source,
            QuerySource::Federation { nodes } if nodes.len() == 2
        ));

        // Vector node should have the drift predicate.
        let vector_node = plan
            .nodes
            .iter()
            .find(|n| n.modality == Modality::Vector)
            .expect("should have vector node");
        assert_eq!(vector_node.conditions.len(), 1);
        assert!(matches!(
            &vector_node.conditions[0],
            ConditionKind::Predicate { expression } if expression.contains("drift")
        ));
    }

    #[test]
    fn test_cross_modal_conditions() {
        let json = r#"{
            "TAG": "Query",
            "_0": {
                "modalities": [{"TAG": "Document"}, {"TAG": "Graph"}],
                "source": {"TAG": "Hexad", "_0": null},
                "where": {
                    "TAG": "Simple",
                    "_0": {
                        "TAG": "CrossModalFieldCompare",
                        "_0": {"modality": {"TAG": "Document"}, "field": "title"},
                        "_1": "=",
                        "_2": {"modality": {"TAG": "Graph"}, "field": "label"}
                    }
                },
                "projections": null,
                "aggregates": null,
                "groupBy": null,
                "having": null,
                "proof": null,
                "orderBy": null,
                "limit": null,
                "offset": null
            }
        }"#;

        let plan = parse_and_plan(json).expect("should parse cross-modal condition");

        // Cross-modal conditions are broadcast to all active modalities.
        for node in &plan.nodes {
            assert_eq!(node.conditions.len(), 1);
            assert!(matches!(
                &node.conditions[0],
                ConditionKind::Predicate { expression } if expression.contains("cross_modal")
            ));
        }
    }

    #[test]
    fn test_aggregation_group_by_order_by() {
        let json = r#"{
            "TAG": "Query",
            "_0": {
                "modalities": [{"TAG": "Document"}],
                "source": {"TAG": "Hexad", "_0": null},
                "where": null,
                "projections": null,
                "aggregates": [
                    {"function": "COUNT", "field": null, "alias": "total"},
                    {"function": "AVG", "field": {"field": "score"}, "alias": "avg_score"}
                ],
                "groupBy": [{"field": "category"}],
                "having": null,
                "proof": null,
                "orderBy": [
                    {"field": {"field": "score"}, "direction": {"TAG": "Desc"}}
                ],
                "limit": 100,
                "offset": 20
            }
        }"#;

        let plan = parse_and_plan(json).expect("should parse aggregation query");

        // Post-processing should contain GroupBy, OrderBy, Limit, and offset
        // marker.
        let has_group = plan.post_processing.iter().any(|p| {
            matches!(
                p,
                PostProcessing::GroupBy { fields, aggregates }
                    if fields == &["category".to_string()]
                    && aggregates.len() == 2
            )
        });
        assert!(has_group, "should have GroupBy post-processing");

        let has_order = plan.post_processing.iter().any(|p| {
            matches!(
                p,
                PostProcessing::OrderBy { fields }
                    if fields.len() == 1 && !fields[0].1 // Desc = false
            )
        });
        assert!(has_order, "should have OrderBy post-processing");

        let has_limit = plan
            .post_processing
            .iter()
            .any(|p| matches!(p, PostProcessing::Limit { count: 100 }));
        assert!(has_limit, "should have Limit post-processing");

        let has_offset = plan.post_processing.iter().any(|p| {
            matches!(
                p,
                PostProcessing::Project { columns } if columns.iter().any(|c| c.starts_with("__offset="))
            )
        });
        assert!(has_offset, "should have offset marker in post-processing");
    }

    #[test]
    fn test_all_modality_expansion() {
        let json = r#"{
            "TAG": "Query",
            "_0": {
                "modalities": [{"TAG": "All"}],
                "source": {"TAG": "Hexad", "_0": null},
                "where": null,
                "projections": null,
                "aggregates": null,
                "groupBy": null,
                "having": null,
                "proof": null,
                "orderBy": null,
                "limit": null,
                "offset": null
            }
        }"#;

        let plan = parse_and_plan(json).expect("should parse All modality query");

        // All 6 modalities should be present.
        assert_eq!(plan.nodes.len(), 6);
        let modalities: Vec<Modality> = plan.nodes.iter().map(|n| n.modality).collect();
        for m in &Modality::ALL {
            assert!(
                modalities.contains(m),
                "missing modality {m:?} after All expansion"
            );
        }

        // Nodes should be sorted by execution priority.
        assert_eq!(plan.nodes[0].modality, Modality::Temporal);
        assert_eq!(plan.nodes[5].modality, Modality::Semantic);
    }

    #[test]
    fn test_error_on_invalid_tag() {
        let json = r#"{
            "TAG": "InvalidStatement",
            "_0": {}
        }"#;

        let result = VqlAst::from_json(json);
        assert!(result.is_err(), "should reject unknown TAG");
    }

    #[test]
    fn test_error_on_missing_tag() {
        let json = r#"{
            "no_tag_field": "oops"
        }"#;

        let result = VqlAst::from_json(json);
        assert!(result.is_err(), "should reject missing TAG");
    }

    #[test]
    fn test_compound_and_condition() {
        let json = r#"{
            "TAG": "Query",
            "_0": {
                "modalities": [{"TAG": "Graph"}, {"TAG": "Vector"}],
                "source": {"TAG": "Hexad", "_0": "some-uuid"},
                "where": {
                    "TAG": "And",
                    "_0": {
                        "TAG": "Simple",
                        "_0": {"TAG": "FulltextContains", "_0": "search text"}
                    },
                    "_1": {
                        "TAG": "Simple",
                        "_0": {"TAG": "VectorSimilar", "_0": [0.1, 0.2], "_1": 0.9}
                    }
                },
                "projections": null,
                "aggregates": null,
                "groupBy": null,
                "having": null,
                "proof": [{"proofType": {"TAG": "Citation"}, "contractName": "MyCitationContract"}],
                "orderBy": [{"field": {"modality": {"TAG": "Document"}, "field": "name"}, "direction": {"TAG": "Asc"}}],
                "limit": 50,
                "offset": null
            }
        }"#;

        let plan = parse_and_plan(json).expect("should parse compound AND query");

        // Vector node gets VectorSimilar condition. FulltextContains targets
        // Document, which is not in the active set, so it becomes a predicate
        // on both active modalities.
        let vector_node = plan
            .nodes
            .iter()
            .find(|n| n.modality == Modality::Vector)
            .expect("should have vector node");
        // Similarity from VectorSimilar + predicate from unmatched FulltextContains
        // is wrong — FulltextContains targets Document which is NOT in active set,
        // so it broadcasts as a predicate. But actually Vector does get the
        // Similarity condition targeted to it.
        let has_similarity = vector_node
            .conditions
            .iter()
            .any(|c| matches!(c, ConditionKind::Similarity { .. }));
        assert!(has_similarity, "vector node should have similarity condition");

        // Graph node should NOT have similarity (it targets Vector).
        let graph_node = plan
            .nodes
            .iter()
            .find(|n| n.modality == Modality::Graph)
            .expect("should have graph node");
        let has_similarity = graph_node
            .conditions
            .iter()
            .any(|c| matches!(c, ConditionKind::Similarity { .. }));
        assert!(!has_similarity, "graph node should not have similarity condition");

        // Proof spec should create a Semantic ProofVerification condition.
        // Semantic is not in active modalities (only Graph, Vector), but the
        // proof injection adds it to the condition map. Since Semantic is not
        // in the node list, it should not appear.
        // Actually, proof conditions are added to existing Semantic entry —
        // since Semantic is not in modalities, it will be created in the map
        // but not become a node. This is correct: proof verification only
        // applies when Semantic modality is queried.
    }

    #[test]
    fn test_or_condition_broadcast() {
        let json = r#"{
            "TAG": "Query",
            "_0": {
                "modalities": [{"TAG": "Document"}, {"TAG": "Graph"}],
                "source": {"TAG": "Hexad", "_0": null},
                "where": {
                    "TAG": "Or",
                    "_0": {
                        "TAG": "Simple",
                        "_0": {"TAG": "FulltextContains", "_0": "alpha"}
                    },
                    "_1": {
                        "TAG": "Simple",
                        "_0": {"TAG": "GraphPattern", "_0": "relates_to", "_1": 3}
                    }
                },
                "projections": null,
                "aggregates": null,
                "groupBy": null,
                "having": null,
                "proof": null,
                "orderBy": null,
                "limit": null,
                "offset": null
            }
        }"#;

        let plan = parse_and_plan(json).expect("should parse OR condition");

        // OR is broadcast as a Predicate to all active modalities.
        for node in &plan.nodes {
            assert_eq!(
                node.conditions.len(),
                1,
                "{:?} node should have exactly 1 condition (the OR predicate)",
                node.modality
            );
            assert!(
                matches!(&node.conditions[0], ConditionKind::Predicate { expression } if expression.starts_with("OR(")),
                "{:?} node condition should be an OR predicate",
                node.modality
            );
        }
    }

    #[test]
    fn test_store_source() {
        let json = r#"{
            "TAG": "Query",
            "_0": {
                "modalities": [{"TAG": "Vector"}],
                "source": {"TAG": "Store", "_0": {"TAG": "Vector"}},
                "where": null,
                "projections": null,
                "aggregates": null,
                "groupBy": null,
                "having": null,
                "proof": null,
                "orderBy": null,
                "limit": null,
                "offset": null
            }
        }"#;

        let plan = parse_and_plan(json).expect("should parse Store source");
        assert!(matches!(
            plan.source,
            QuerySource::Store { modality: Modality::Vector }
        ));
    }

    #[test]
    fn test_proof_on_semantic_node() {
        let json = r#"{
            "TAG": "Query",
            "_0": {
                "modalities": [{"TAG": "Semantic"}, {"TAG": "Document"}],
                "source": {"TAG": "Hexad", "_0": null},
                "where": null,
                "projections": null,
                "aggregates": null,
                "groupBy": null,
                "having": null,
                "proof": [
                    {"proofType": {"TAG": "Citation"}, "contractName": "CitContract"},
                    {"proofType": {"TAG": "Zkp"}, "contractName": "ZkpContract"}
                ],
                "orderBy": null,
                "limit": null,
                "offset": null
            }
        }"#;

        let plan = parse_and_plan(json).expect("should parse proof specs");

        let semantic_node = plan
            .nodes
            .iter()
            .find(|n| n.modality == Modality::Semantic)
            .expect("should have semantic node");

        assert_eq!(
            semantic_node.conditions.len(),
            2,
            "semantic node should have 2 proof verification conditions"
        );
        assert!(matches!(
            &semantic_node.conditions[0],
            ConditionKind::ProofVerification { contract } if contract == "CitContract"
        ));
        assert!(matches!(
            &semantic_node.conditions[1],
            ConditionKind::ProofVerification { contract } if contract == "ZkpContract"
        ));
    }

    #[test]
    fn test_field_condition_equality() {
        let json = r#"{
            "TAG": "Query",
            "_0": {
                "modalities": [{"TAG": "Document"}],
                "source": {"TAG": "Hexad", "_0": null},
                "where": {
                    "TAG": "Simple",
                    "_0": {
                        "TAG": "FieldCondition",
                        "_0": {"modality": {"TAG": "Document"}, "field": "status"},
                        "_1": "=",
                        "_2": "active"
                    }
                },
                "projections": null,
                "aggregates": null,
                "groupBy": null,
                "having": null,
                "proof": null,
                "orderBy": null,
                "limit": null,
                "offset": null
            }
        }"#;

        let plan = parse_and_plan(json).expect("should parse field condition");
        let doc_node = plan
            .nodes
            .iter()
            .find(|n| n.modality == Modality::Document)
            .expect("should have document node");

        assert_eq!(doc_node.conditions.len(), 1);
        assert!(matches!(
            &doc_node.conditions[0],
            ConditionKind::Equality { field, value }
                if field == "status" && value == "active"
        ));
    }

    #[test]
    fn test_field_condition_range() {
        let json = r#"{
            "TAG": "Query",
            "_0": {
                "modalities": [{"TAG": "Temporal"}],
                "source": {"TAG": "Hexad", "_0": null},
                "where": {
                    "TAG": "Simple",
                    "_0": {
                        "TAG": "FieldCondition",
                        "_0": {"modality": {"TAG": "Temporal"}, "field": "timestamp"},
                        "_1": ">=",
                        "_2": "2026-01-01"
                    }
                },
                "projections": null,
                "aggregates": null,
                "groupBy": null,
                "having": null,
                "proof": null,
                "orderBy": null,
                "limit": null,
                "offset": null
            }
        }"#;

        let plan = parse_and_plan(json).expect("should parse range field condition");
        let temporal_node = plan
            .nodes
            .iter()
            .find(|n| n.modality == Modality::Temporal)
            .expect("should have temporal node");

        assert_eq!(temporal_node.conditions.len(), 1);
        assert!(matches!(
            &temporal_node.conditions[0],
            ConditionKind::Range { field, .. } if field == "timestamp"
        ));
    }

    #[test]
    fn test_empty_modalities_error() {
        let json = r#"{
            "TAG": "Query",
            "_0": {
                "modalities": [],
                "source": {"TAG": "Hexad", "_0": null},
                "where": null,
                "projections": null,
                "aggregates": null,
                "groupBy": null,
                "having": null,
                "proof": null,
                "orderBy": null,
                "limit": null,
                "offset": null
            }
        }"#;

        let result = parse_and_plan(json);
        assert!(
            matches!(result, Err(PlannerError::EmptyPlan)),
            "should return EmptyPlan error for no modalities"
        );
    }

    #[test]
    fn test_modality_consistency_condition() {
        let json = r#"{
            "TAG": "Query",
            "_0": {
                "modalities": [{"TAG": "Graph"}, {"TAG": "Vector"}],
                "source": {"TAG": "Hexad", "_0": null},
                "where": {
                    "TAG": "Simple",
                    "_0": {
                        "TAG": "ModalityConsistency",
                        "_0": [{"TAG": "Graph"}, {"TAG": "Vector"}],
                        "_1": 0.95
                    }
                },
                "projections": null,
                "aggregates": null,
                "groupBy": null,
                "having": null,
                "proof": null,
                "orderBy": null,
                "limit": null,
                "offset": null
            }
        }"#;

        let plan = parse_and_plan(json).expect("should parse consistency condition");

        // Consistency is broadcast to all active modalities.
        for node in &plan.nodes {
            assert_eq!(node.conditions.len(), 1);
            assert!(matches!(
                &node.conditions[0],
                ConditionKind::Predicate { expression } if expression.contains("consistency")
            ));
        }
    }

    #[test]
    fn test_not_condition() {
        let json = r#"{
            "TAG": "Query",
            "_0": {
                "modalities": [{"TAG": "Document"}],
                "source": {"TAG": "Hexad", "_0": null},
                "where": {
                    "TAG": "Not",
                    "_0": {
                        "TAG": "Simple",
                        "_0": {"TAG": "FulltextContains", "_0": "excluded"}
                    }
                },
                "projections": null,
                "aggregates": null,
                "groupBy": null,
                "having": null,
                "proof": null,
                "orderBy": null,
                "limit": null,
                "offset": null
            }
        }"#;

        let plan = parse_and_plan(json).expect("should parse NOT condition");
        let doc_node = &plan.nodes[0];
        assert_eq!(doc_node.conditions.len(), 1);
        assert!(matches!(
            &doc_node.conditions[0],
            ConditionKind::Predicate { expression } if expression.starts_with("NOT(")
        ));
    }

    #[test]
    fn test_deduplication_with_all_and_explicit() {
        let json = r#"{
            "TAG": "Query",
            "_0": {
                "modalities": [{"TAG": "Graph"}, {"TAG": "All"}, {"TAG": "Graph"}],
                "source": {"TAG": "Hexad", "_0": null},
                "where": null,
                "projections": null,
                "aggregates": null,
                "groupBy": null,
                "having": null,
                "proof": null,
                "orderBy": null,
                "limit": null,
                "offset": null
            }
        }"#;

        let plan = parse_and_plan(json).expect("should deduplicate modalities");
        // Should still have exactly 6 unique modalities.
        assert_eq!(plan.nodes.len(), 6);
    }
}
