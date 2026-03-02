// SPDX-License-Identifier: PMPL-1.0-or-later
//! Drift calculation algorithms
//!
//! Computes actual drift scores between modalities to detect consistency degradation.

use crate::DriftType;

/// Drift calculator for computing cross-modal consistency scores
pub struct DriftCalculator {
    /// Minimum similarity threshold below which drift is detected
    pub similarity_threshold: f64,
}

impl Default for DriftCalculator {
    fn default() -> Self {
        Self {
            similarity_threshold: 0.8,
        }
    }
}

impl DriftCalculator {
    /// Create a new drift calculator with custom threshold
    pub fn new(similarity_threshold: f64) -> Self {
        Self { similarity_threshold }
    }

    /// Calculate semantic-vector drift score
    ///
    /// Measures how well the vector embedding captures the semantic meaning.
    /// This is computed by comparing the embedding similarity with semantic type similarity.
    ///
    /// Returns a score from 0.0 (no drift) to 1.0 (maximum drift)
    pub fn semantic_vector_drift(
        &self,
        embedding: &[f32],
        semantic_types: &[String],
        type_embeddings: &[(String, Vec<f32>)],
    ) -> f64 {
        if semantic_types.is_empty() || type_embeddings.is_empty() {
            return 0.0; // No drift if no semantic types or embeddings to compare
        }

        // Find type embeddings for the entity's semantic types
        let relevant_embeddings: Vec<&Vec<f32>> = type_embeddings
            .iter()
            .filter(|(type_iri, _)| semantic_types.contains(type_iri))
            .map(|(_, emb)| emb)
            .collect();

        if relevant_embeddings.is_empty() {
            return 0.0;
        }

        // Compute average similarity with type embeddings
        let mut total_similarity = 0.0;
        for type_emb in &relevant_embeddings {
            total_similarity += cosine_similarity_f32(embedding, type_emb);
        }
        let avg_similarity = total_similarity / relevant_embeddings.len() as f64;

        // Convert similarity to drift score (inverse relationship)
        // High similarity = low drift, low similarity = high drift
        let drift_score = 1.0 - avg_similarity;
        drift_score.clamp(0.0, 1.0)
    }

    /// Calculate graph-document drift score
    ///
    /// Measures consistency between graph relationships and document content.
    /// Checks if entities mentioned in document have corresponding graph edges.
    ///
    /// Returns a score from 0.0 (no drift) to 1.0 (maximum drift)
    pub fn graph_document_drift(
        &self,
        document_text: &str,
        document_entities: &[String],
        graph_relationships: &[(String, String)], // (predicate, target)
    ) -> f64 {
        if document_entities.is_empty() {
            return 0.0;
        }

        // Count how many document entities have corresponding graph relationships
        let graph_targets: Vec<&String> = graph_relationships.iter().map(|(_, t)| t).collect();

        let mut matched = 0;
        for entity in document_entities {
            // Check if entity appears in graph relationships
            if graph_targets.iter().any(|t| t.contains(entity) || entity.contains(*t)) {
                matched += 1;
            }
            // Also check if entity is mentioned in document
            if !document_text.to_lowercase().contains(&entity.to_lowercase()) {
                // Entity in list but not in document text - potential issue
            }
        }

        // Drift score based on coverage
        let coverage = if !document_entities.is_empty() {
            matched as f64 / document_entities.len() as f64
        } else {
            1.0
        };

        // Also consider if there are graph relationships not reflected in document
        let extra_graph_ratio = if !graph_relationships.is_empty() {
            let unmatched_graph = graph_relationships
                .iter()
                .filter(|(_, t)| !document_entities.iter().any(|e| t.contains(e)))
                .count();
            unmatched_graph as f64 / graph_relationships.len() as f64
        } else {
            0.0
        };

        // Combine metrics: low coverage or high extra graph = high drift
        let drift_score = (1.0 - coverage + extra_graph_ratio) / 2.0;
        drift_score.clamp(0.0, 1.0)
    }

    /// Calculate temporal consistency drift score
    ///
    /// Measures if there are inconsistencies in the version history,
    /// such as conflicting updates or temporal anomalies.
    ///
    /// Returns a score from 0.0 (no drift) to 1.0 (maximum drift)
    pub fn temporal_consistency_drift(
        &self,
        version_timestamps: &[i64], // Unix timestamps
        version_hashes: &[u64],     // Content hashes for each version
    ) -> f64 {
        if version_timestamps.len() < 2 {
            return 0.0; // No drift with single version
        }

        let mut issues = 0.0;
        let total_checks = (version_timestamps.len() - 1) as f64;

        // Check for timestamp ordering issues
        for window in version_timestamps.windows(2) {
            if window[1] < window[0] {
                issues += 1.0; // Timestamp goes backwards
            }
        }

        // Check for duplicate content (same hash, different version)
        let mut hash_counts = std::collections::HashMap::new();
        for hash in version_hashes {
            *hash_counts.entry(hash).or_insert(0) += 1;
        }
        let duplicates = hash_counts.values().filter(|&&c| c > 1).count();
        issues += duplicates as f64 * 0.5; // Partial penalty for duplicates

        // Check for suspiciously large time gaps (might indicate data loss)
        if version_timestamps.len() >= 2 {
            let mut deltas: Vec<i64> = version_timestamps
                .windows(2)
                .map(|w| w[1] - w[0])
                .collect();
            deltas.sort();
            if deltas.len() >= 3 {
                let median = deltas[deltas.len() / 2];
                let max = *deltas.last().unwrap_or(&0);
                if median > 0 && max > median * 10 {
                    issues += 0.5; // Large gap detected
                }
            }
        }

        let drift_score = issues / (total_checks + 1.0);
        drift_score.clamp(0.0, 1.0)
    }

    /// Calculate tensor drift score
    ///
    /// Measures if tensor representations are consistent with expected properties.
    ///
    /// Returns a score from 0.0 (no drift) to 1.0 (maximum drift)
    pub fn tensor_drift(
        &self,
        tensor_data: &[f64],
        expected_shape: &[usize],
        actual_shape: &[usize],
        expected_stats: Option<TensorStats>,
    ) -> f64 {
        let mut drift_score = 0.0;

        // Check shape consistency
        if expected_shape != actual_shape {
            let shape_diff = expected_shape
                .iter()
                .zip(actual_shape.iter())
                .map(|(e, a)| (*e as f64 - *a as f64).abs() / *e as f64)
                .sum::<f64>()
                / expected_shape.len().max(actual_shape.len()) as f64;
            drift_score += shape_diff * 0.5;
        }

        // Check statistical properties if expected stats provided
        if let Some(expected) = expected_stats {
            let actual = TensorStats::compute(tensor_data);

            // Compare means
            if expected.mean.abs() > 1e-10 {
                let mean_diff = (actual.mean - expected.mean).abs() / expected.mean.abs();
                drift_score += mean_diff.min(1.0) * 0.2;
            }

            // Compare std deviations
            if expected.std_dev > 1e-10 {
                let std_diff = (actual.std_dev - expected.std_dev).abs() / expected.std_dev;
                drift_score += std_diff.min(1.0) * 0.2;
            }

            // Check for NaN/Inf values (always bad)
            if actual.has_nan || actual.has_inf {
                drift_score += 0.3;
            }
        }

        drift_score.clamp(0.0, 1.0)
    }

    /// Calculate provenance drift score
    ///
    /// Measures integrity of the provenance chain.  A broken chain (hash
    /// mismatch, missing parent) produces maximum drift.  Staleness (long
    /// gap since last event) produces moderate drift.
    ///
    /// Returns a score from 0.0 (no drift) to 1.0 (maximum drift)
    pub fn provenance_drift(
        &self,
        chain_valid: bool,
        chain_length: usize,
        seconds_since_last_event: Option<u64>,
        expected_max_gap_seconds: u64,
    ) -> f64 {
        let mut drift_score = 0.0;

        // Chain integrity is critical — broken chain = maximum provenance drift
        if !chain_valid {
            return 1.0;
        }

        // Empty chain for an existing entity is suspicious
        if chain_length == 0 {
            drift_score += 0.5;
        }

        // Staleness: if the last event is much older than expected, lineage
        // tracking may have stopped
        if let Some(gap) = seconds_since_last_event {
            if expected_max_gap_seconds > 0 && gap > expected_max_gap_seconds {
                let staleness = (gap as f64 / expected_max_gap_seconds as f64 - 1.0).min(1.0);
                drift_score += staleness * 0.3;
            }
        }

        drift_score.clamp(0.0, 1.0)
    }

    /// Calculate spatial drift score
    ///
    /// Measures consistency between spatial coordinates and location
    /// references in the document/graph modalities.  If an entity claims
    /// to be "in London" but has coordinates pointing to New York, that's
    /// spatial drift.
    ///
    /// Returns a score from 0.0 (no drift) to 1.0 (maximum drift)
    pub fn spatial_drift(
        &self,
        has_coordinates: bool,
        has_location_mentions: bool,
        coordinate_matches_mentions: bool,
        coordinates_valid: bool,
    ) -> f64 {
        let mut drift_score: f64 = 0.0;

        // Invalid coordinates (NaN, out of WGS84 range) = high drift
        if has_coordinates && !coordinates_valid {
            return 0.9;
        }

        // Document mentions locations but no spatial data indexed
        if has_location_mentions && !has_coordinates {
            drift_score += 0.4;
        }

        // Has coordinates but they don't match document location mentions
        if has_coordinates && has_location_mentions && !coordinate_matches_mentions {
            drift_score += 0.5;
        }

        // Has coordinates but no location context in other modalities
        if has_coordinates && !has_location_mentions {
            drift_score += 0.1; // Minor — coordinates without context is OK
        }

        drift_score.clamp(0.0, 1.0)
    }

    /// Calculate schema drift score
    ///
    /// Measures if the entity violates cross-modal schema constraints.
    ///
    /// Returns a score from 0.0 (no drift) to 1.0 (maximum drift)
    pub fn schema_drift(
        &self,
        required_modalities: &[&str],
        present_modalities: &[&str],
        schema_violations: usize,
        total_constraints: usize,
    ) -> f64 {
        let mut drift_score = 0.0;

        // Check modality coverage
        let missing_modalities = required_modalities
            .iter()
            .filter(|m| !present_modalities.contains(m))
            .count();
        if !required_modalities.is_empty() {
            drift_score += (missing_modalities as f64 / required_modalities.len() as f64) * 0.5;
        }

        // Check schema constraint violations
        if total_constraints > 0 {
            drift_score += (schema_violations as f64 / total_constraints as f64) * 0.5;
        }

        drift_score.clamp(0.0, 1.0)
    }

    /// Calculate overall quality drift score
    ///
    /// Aggregates all drift metrics into an overall quality score.
    /// Updated for octad (8 modalities) with provenance and spatial.
    ///
    /// Returns a score from 0.0 (no drift) to 1.0 (maximum drift)
    pub fn quality_drift(
        &self,
        semantic_vector: f64,
        graph_document: f64,
        temporal_consistency: f64,
        tensor: f64,
        schema: f64,
    ) -> f64 {
        // Weighted average of all drift scores
        // Weights reflect relative importance
        let weights = [
            (semantic_vector, 0.25),
            (graph_document, 0.25),
            (temporal_consistency, 0.20),
            (tensor, 0.15),
            (schema, 0.15),
        ];

        let weighted_sum: f64 = weights.iter().map(|(score, weight)| score * weight).sum();
        weighted_sum.clamp(0.0, 1.0)
    }

    /// Calculate overall quality drift score including all 8 modality drift types
    pub fn quality_drift_octad(
        &self,
        semantic_vector: f64,
        graph_document: f64,
        temporal_consistency: f64,
        tensor: f64,
        schema: f64,
        provenance: f64,
        spatial: f64,
    ) -> f64 {
        // Rebalanced weights for octad (8 modalities)
        let weights = [
            (semantic_vector, 0.20),
            (graph_document, 0.20),
            (temporal_consistency, 0.15),
            (tensor, 0.10),
            (schema, 0.10),
            (provenance, 0.15),
            (spatial, 0.10),
        ];

        let weighted_sum: f64 = weights.iter().map(|(score, weight)| score * weight).sum();
        weighted_sum.clamp(0.0, 1.0)
    }

    /// Determine drift type from individual scores
    pub fn primary_drift_type(
        &self,
        semantic_vector: f64,
        graph_document: f64,
        temporal_consistency: f64,
        tensor: f64,
        schema: f64,
    ) -> DriftType {
        let scores = [
            (DriftType::SemanticVectorDrift, semantic_vector),
            (DriftType::GraphDocumentDrift, graph_document),
            (DriftType::TemporalConsistencyDrift, temporal_consistency),
            (DriftType::TensorDrift, tensor),
            (DriftType::SchemaDrift, schema),
        ];

        scores
            .iter()
            .max_by(|a, b| a.1.partial_cmp(&b.1).unwrap_or(std::cmp::Ordering::Equal))
            .map(|(t, _)| *t)
            .unwrap_or(DriftType::QualityDrift)
    }

    /// Determine drift type from all octad scores (including provenance + spatial)
    pub fn primary_drift_type_octad(
        &self,
        semantic_vector: f64,
        graph_document: f64,
        temporal_consistency: f64,
        tensor: f64,
        schema: f64,
        provenance: f64,
        spatial: f64,
    ) -> DriftType {
        let scores = [
            (DriftType::SemanticVectorDrift, semantic_vector),
            (DriftType::GraphDocumentDrift, graph_document),
            (DriftType::TemporalConsistencyDrift, temporal_consistency),
            (DriftType::TensorDrift, tensor),
            (DriftType::SchemaDrift, schema),
            (DriftType::ProvenanceDrift, provenance),
            (DriftType::SpatialDrift, spatial),
        ];

        scores
            .iter()
            .max_by(|a, b| a.1.partial_cmp(&b.1).unwrap_or(std::cmp::Ordering::Equal))
            .map(|(t, _)| *t)
            .unwrap_or(DriftType::QualityDrift)
    }
}

/// Statistics for tensor data
#[derive(Debug, Clone)]
pub struct TensorStats {
    pub mean: f64,
    pub std_dev: f64,
    pub min: f64,
    pub max: f64,
    pub has_nan: bool,
    pub has_inf: bool,
}

impl TensorStats {
    /// Compute statistics from tensor data
    pub fn compute(data: &[f64]) -> Self {
        if data.is_empty() {
            return Self {
                mean: 0.0,
                std_dev: 0.0,
                min: 0.0,
                max: 0.0,
                has_nan: false,
                has_inf: false,
            };
        }

        let has_nan = data.iter().any(|x| x.is_nan());
        let has_inf = data.iter().any(|x| x.is_infinite());

        // Filter out NaN/Inf for statistics
        let valid: Vec<f64> = data.iter().copied().filter(|x| x.is_finite()).collect();

        if valid.is_empty() {
            return Self {
                mean: 0.0,
                std_dev: 0.0,
                min: 0.0,
                max: 0.0,
                has_nan,
                has_inf,
            };
        }

        let sum: f64 = valid.iter().sum();
        let mean = sum / valid.len() as f64;

        let variance: f64 = valid.iter().map(|x| (x - mean).powi(2)).sum::<f64>() / valid.len() as f64;
        let std_dev = variance.sqrt();

        let min = valid.iter().copied().fold(f64::INFINITY, f64::min);
        let max = valid.iter().copied().fold(f64::NEG_INFINITY, f64::max);

        Self {
            mean,
            std_dev,
            min,
            max,
            has_nan,
            has_inf,
        }
    }
}

/// Compute cosine similarity between two f32 vectors
fn cosine_similarity_f32(a: &[f32], b: &[f32]) -> f64 {
    if a.len() != b.len() || a.is_empty() {
        return 0.0;
    }

    let dot: f64 = a.iter().zip(b.iter()).map(|(x, y)| (*x as f64) * (*y as f64)).sum();
    let norm_a: f64 = a.iter().map(|x| (*x as f64).powi(2)).sum::<f64>().sqrt();
    let norm_b: f64 = b.iter().map(|x| (*x as f64).powi(2)).sum::<f64>().sqrt();

    if norm_a > 0.0 && norm_b > 0.0 {
        dot / (norm_a * norm_b)
    } else {
        0.0
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_semantic_vector_drift_no_drift() {
        let calc = DriftCalculator::default();

        // Embedding that matches type embedding
        let embedding = vec![1.0, 0.0, 0.0];
        let semantic_types = vec!["https://example.org/Person".to_string()];
        let type_embeddings = vec![(
            "https://example.org/Person".to_string(),
            vec![1.0, 0.0, 0.0],
        )];

        let drift = calc.semantic_vector_drift(&embedding, &semantic_types, &type_embeddings);
        assert!(drift < 0.1, "Expected low drift, got {}", drift);
    }

    #[test]
    fn test_semantic_vector_drift_high_drift() {
        let calc = DriftCalculator::default();

        // Embedding completely different from type embedding
        let embedding = vec![1.0, 0.0, 0.0];
        let semantic_types = vec!["https://example.org/Person".to_string()];
        let type_embeddings = vec![(
            "https://example.org/Person".to_string(),
            vec![0.0, 1.0, 0.0],
        )];

        let drift = calc.semantic_vector_drift(&embedding, &semantic_types, &type_embeddings);
        assert!(drift > 0.5, "Expected high drift, got {}", drift);
    }

    #[test]
    fn test_graph_document_drift() {
        let calc = DriftCalculator::default();

        let document_text = "Alice knows Bob and Charlie";
        let document_entities = vec!["Alice".to_string(), "Bob".to_string(), "Charlie".to_string()];
        let graph_relationships = vec![
            ("knows".to_string(), "Bob".to_string()),
            ("knows".to_string(), "Charlie".to_string()),
        ];

        let drift =
            calc.graph_document_drift(document_text, &document_entities, &graph_relationships);
        // Should have moderate drift since Alice is not a target in relationships
        assert!(drift < 0.7, "Drift score: {}", drift);
    }

    #[test]
    fn test_temporal_consistency_drift() {
        let calc = DriftCalculator::default();

        // Normal sequence
        let timestamps = vec![1000, 2000, 3000, 4000];
        let hashes = vec![1, 2, 3, 4];
        let drift = calc.temporal_consistency_drift(&timestamps, &hashes);
        assert!(drift < 0.1, "Expected low drift for normal sequence, got {}", drift);

        // Out of order timestamps
        let timestamps = vec![1000, 3000, 2000, 4000];
        let drift = calc.temporal_consistency_drift(&timestamps, &hashes);
        assert!(drift > 0.0, "Expected drift for out-of-order timestamps, got {}", drift);
    }

    #[test]
    fn test_tensor_drift() {
        let calc = DriftCalculator::default();

        let data = vec![1.0, 2.0, 3.0, 4.0];
        let expected_shape = vec![2, 2];
        let actual_shape = vec![2, 2];
        let expected_stats = Some(TensorStats {
            mean: 2.5,
            std_dev: 1.118,
            min: 1.0,
            max: 4.0,
            has_nan: false,
            has_inf: false,
        });

        let drift = calc.tensor_drift(&data, &expected_shape, &actual_shape, expected_stats);
        assert!(drift < 0.3, "Expected low drift for matching tensor, got {}", drift);

        // Test with NaN values
        let data_with_nan = vec![1.0, f64::NAN, 3.0, 4.0];
        let _drift = calc.tensor_drift(&data_with_nan, &expected_shape, &actual_shape, None);
        // Should not panic, just handle gracefully
    }

    #[test]
    fn test_schema_drift() {
        let calc = DriftCalculator::default();

        let required = vec!["graph", "vector", "document"];
        let present = vec!["graph", "vector"];

        let drift = calc.schema_drift(&required, &present, 1, 5);
        assert!(drift > 0.0, "Expected drift for missing modality");
        assert!(drift < 1.0, "Drift should be bounded");
    }

    #[test]
    fn test_quality_drift() {
        let calc = DriftCalculator::default();

        // All metrics good
        let drift = calc.quality_drift(0.1, 0.1, 0.1, 0.1, 0.1);
        assert!(drift < 0.2, "Expected low overall drift");

        // Some metrics bad
        let drift = calc.quality_drift(0.8, 0.2, 0.1, 0.1, 0.1);
        assert!(drift > 0.1, "Expected higher drift with semantic-vector issues");
    }

    #[test]
    fn test_tensor_stats() {
        let data = vec![1.0, 2.0, 3.0, 4.0, 5.0];
        let stats = TensorStats::compute(&data);

        assert!((stats.mean - 3.0).abs() < 1e-10);
        assert!((stats.min - 1.0).abs() < 1e-10);
        assert!((stats.max - 5.0).abs() < 1e-10);
        assert!(!stats.has_nan);
        assert!(!stats.has_inf);
    }
}
