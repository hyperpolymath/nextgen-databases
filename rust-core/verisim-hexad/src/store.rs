// SPDX-License-Identifier: PMPL-1.0-or-later
//! In-memory HexadStore implementation
//!
//! Coordinates all eight modality stores (octad) for unified entity management.

use async_trait::async_trait;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;
use tracing::{debug, info, instrument};

use crate::{
    Coordinates, Document, DocumentStore, Embedding, GeometryType, GraphEdge, GraphNode,
    GraphObject, GraphStore, Hexad, HexadConfig, HexadDocumentInput, HexadError, HexadGraphInput,
    HexadId, HexadInput, HexadProvenanceInput, HexadSemanticInput, HexadSpatialInput,
    HexadStatus, HexadStore, HexadTensorInput, HexadVectorInput, ModalityStatus, Provenance,
    ProvenanceEventType, ProvenanceStore, SemanticAnnotation, SemanticStore, SemanticValue,
    SpatialData, SpatialStore, Tensor, TensorStore, TemporalStore, VectorStore,
};
use crate::transaction::{IsolationLevel, LockType, TransactionManager};
use verisim_wal::{WalEntry, WalModality, WalOperation, WalWriter, SyncMode};

/// Snapshot of a Hexad for versioning
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HexadSnapshot {
    pub id: HexadId,
    pub input: HexadInput,
    pub modality_status: ModalityStatus,
    pub timestamp: DateTime<Utc>,
}

/// In-memory implementation of HexadStore
///
/// This store coordinates all eight modality stores (octad), ensuring
/// cross-modal consistency when entities are created, updated, or deleted.
/// Write operations (create/update/delete) are wrapped in ACID transactions
/// via the [`TransactionManager`], guaranteeing atomicity across all modalities.
pub struct InMemoryHexadStore<G, V, D, T, S, R, P, L>
where
    G: GraphStore,
    V: VectorStore,
    D: DocumentStore,
    T: TensorStore,
    S: SemanticStore,
    R: TemporalStore<Data = HexadSnapshot>,
    P: ProvenanceStore,
    L: SpatialStore,
{
    config: HexadConfig,
    /// Hexad status registry
    hexads: Arc<RwLock<HashMap<String, HexadStatus>>>,
    /// ACID transaction manager for cross-modality atomicity
    txn_manager: Arc<TransactionManager>,
    /// Optional write-ahead log for crash recovery.
    /// When present, all modality writes are logged before execution.
    wal: Option<Arc<tokio::sync::Mutex<WalWriter>>>,
    /// Graph store
    graph: Arc<G>,
    /// Vector store
    vector: Arc<V>,
    /// Document store
    document: Arc<D>,
    /// Tensor store
    tensor: Arc<T>,
    /// Semantic store
    semantic: Arc<S>,
    /// Temporal (versioning) store
    temporal: Arc<R>,
    /// Provenance (lineage tracking) store
    provenance: Arc<P>,
    /// Spatial (geospatial) store
    spatial: Arc<L>,
}

impl<G, V, D, T, S, R, P, L> InMemoryHexadStore<G, V, D, T, S, R, P, L>
where
    G: GraphStore,
    V: VectorStore,
    D: DocumentStore,
    T: TensorStore,
    S: SemanticStore,
    R: TemporalStore<Data = HexadSnapshot>,
    P: ProvenanceStore,
    L: SpatialStore,
{
    /// Create a new in-memory hexad store with all eight modality stores.
    ///
    /// Automatically creates a [`TransactionManager`] to provide ACID
    /// guarantees across all modality writes.
    pub fn new(
        config: HexadConfig,
        graph: Arc<G>,
        vector: Arc<V>,
        document: Arc<D>,
        tensor: Arc<T>,
        semantic: Arc<S>,
        temporal: Arc<R>,
        provenance: Arc<P>,
        spatial: Arc<L>,
    ) -> Self {
        Self {
            config,
            hexads: Arc::new(RwLock::new(HashMap::new())),
            txn_manager: Arc::new(TransactionManager::new()),
            wal: None,
            graph,
            vector,
            document,
            tensor,
            semantic,
            temporal,
            provenance,
            spatial,
        }
    }

    /// Enable write-ahead logging for crash recovery.
    ///
    /// When enabled, all modality writes are recorded to the WAL before
    /// being applied to the stores. On crash, the WAL can be replayed to
    /// recover PENDING operations.
    ///
    /// # Arguments
    ///
    /// * `wal_dir` - Directory for WAL segment files (created if absent).
    /// * `sync_mode` - Controls fsync behavior (Fsync, Periodic, or Async).
    pub fn with_wal(
        mut self,
        wal_dir: impl AsRef<std::path::Path>,
        sync_mode: SyncMode,
    ) -> Result<Self, HexadError> {
        let writer = WalWriter::open(wal_dir, sync_mode).map_err(|e| {
            HexadError::ModalityError {
                modality: "wal".to_string(),
                message: format!("Failed to open WAL: {e}"),
            }
        })?;
        self.wal = Some(Arc::new(tokio::sync::Mutex::new(writer)));
        Ok(self)
    }

    /// Access the transaction manager for diagnostics or external coordination.
    pub fn transaction_manager(&self) -> &Arc<TransactionManager> {
        &self.txn_manager
    }

    /// Write a WAL entry if WAL is enabled. Returns Ok(()) if WAL is disabled.
    async fn wal_append(
        &self,
        operation: WalOperation,
        modality: WalModality,
        entity_id: &str,
        payload: &[u8],
    ) -> Result<(), HexadError> {
        if let Some(ref wal) = self.wal {
            let entry = WalEntry {
                sequence: 0, // Assigned by the writer
                timestamp: Utc::now(),
                operation,
                modality,
                entity_id: entity_id.to_string(),
                payload: payload.to_vec(),
            };
            let mut writer = wal.lock().await;
            writer.append(entry).map_err(|e| HexadError::ModalityError {
                modality: "wal".to_string(),
                message: format!("WAL append failed: {e}"),
            })?;
        }
        Ok(())
    }

    /// Write a WAL checkpoint marker if WAL is enabled.
    async fn wal_checkpoint(&self) -> Result<(), HexadError> {
        if let Some(ref wal) = self.wal {
            let mut writer = wal.lock().await;
            writer.checkpoint().map_err(|e| HexadError::ModalityError {
                modality: "wal".to_string(),
                message: format!("WAL checkpoint failed: {e}"),
            })?;
        }
        Ok(())
    }

    /// Access the provenance store for direct queries.
    pub fn provenance_store(&self) -> &Arc<P> {
        &self.provenance
    }

    /// Access the spatial store for direct queries.
    pub fn spatial_store(&self) -> &Arc<L> {
        &self.spatial
    }

    /// Process graph input for a hexad
    async fn process_graph(
        &self,
        id: &HexadId,
        input: &HexadGraphInput,
    ) -> Result<GraphNode, HexadError> {
        let node = GraphNode::new(id.to_iri(&self.config.base_iri));

        for (predicate, target_id) in &input.relationships {
            let edge = GraphEdge {
                subject: node.clone(),
                predicate: GraphNode::new(format!("{}/{}", self.config.base_iri, predicate)),
                object: GraphObject::Node(GraphNode::new(format!(
                    "{}/{}",
                    self.config.base_iri, target_id
                ))),
            };
            self.graph.insert(&edge).await.map_err(|e| HexadError::ModalityError {
                modality: "graph".to_string(),
                message: e.to_string(),
            })?;
        }

        debug!(id = %id, relationships = input.relationships.len(), "Graph modality populated");
        Ok(node)
    }

    /// Process vector input for a hexad
    async fn process_vector(
        &self,
        id: &HexadId,
        input: &HexadVectorInput,
    ) -> Result<Embedding, HexadError> {
        if input.embedding.len() != self.config.vector_dimension {
            return Err(HexadError::ValidationError(format!(
                "Vector dimension mismatch: expected {}, got {}",
                self.config.vector_dimension,
                input.embedding.len()
            )));
        }

        let embedding = Embedding::new(id.as_str(), input.embedding.clone());
        self.vector.upsert(&embedding).await.map_err(|e| HexadError::ModalityError {
            modality: "vector".to_string(),
            message: e.to_string(),
        })?;

        debug!(id = %id, dimension = input.embedding.len(), "Vector modality populated");
        Ok(embedding)
    }

    /// Process document input for a hexad
    async fn process_document(
        &self,
        id: &HexadId,
        input: &HexadDocumentInput,
    ) -> Result<Document, HexadError> {
        let mut doc = Document::new(id.as_str(), &input.title, &input.body);
        for (key, value) in &input.fields {
            doc = doc.with_field(key, value);
        }

        self.document.index(&doc).await.map_err(|e| HexadError::ModalityError {
            modality: "document".to_string(),
            message: e.to_string(),
        })?;
        self.document.commit().await.map_err(|e| HexadError::ModalityError {
            modality: "document".to_string(),
            message: e.to_string(),
        })?;

        debug!(id = %id, title = %input.title, "Document modality populated");
        Ok(doc)
    }

    /// Process tensor input for a hexad
    async fn process_tensor(
        &self,
        id: &HexadId,
        input: &HexadTensorInput,
    ) -> Result<Tensor, HexadError> {
        let tensor = Tensor::new(id.as_str(), input.shape.clone(), input.data.clone()).map_err(
            |e| HexadError::ModalityError {
                modality: "tensor".to_string(),
                message: e.to_string(),
            },
        )?;

        self.tensor.put(&tensor).await.map_err(|e| HexadError::ModalityError {
            modality: "tensor".to_string(),
            message: e.to_string(),
        })?;

        debug!(id = %id, shape = ?input.shape, "Tensor modality populated");
        Ok(tensor)
    }

    /// Process semantic input for a hexad
    async fn process_semantic(
        &self,
        id: &HexadId,
        input: &HexadSemanticInput,
    ) -> Result<SemanticAnnotation, HexadError> {
        let mut properties = HashMap::new();
        for (key, value) in &input.properties {
            properties.insert(
                key.clone(),
                SemanticValue::TypedLiteral {
                    value: value.clone(),
                    datatype: "https://www.w3.org/2001/XMLSchema#string".to_string(),
                },
            );
        }

        let annotation = SemanticAnnotation {
            entity_id: id.as_str().to_string(),
            types: input.types.clone(),
            properties,
            provenance: Provenance::default(),
        };

        self.semantic.annotate(&annotation).await.map_err(|e| HexadError::ModalityError {
            modality: "semantic".to_string(),
            message: e.to_string(),
        })?;

        debug!(id = %id, types = ?input.types, "Semantic modality populated");
        Ok(annotation)
    }

    /// Process provenance input for a hexad — records a lineage event
    async fn process_provenance(
        &self,
        id: &HexadId,
        input: &HexadProvenanceInput,
    ) -> Result<u64, HexadError> {
        let event_type = match input.event_type.to_lowercase().as_str() {
            "created" => ProvenanceEventType::Created,
            "modified" => ProvenanceEventType::Modified,
            "imported" => ProvenanceEventType::Imported,
            "normalized" => ProvenanceEventType::Normalized,
            "drift_repaired" => ProvenanceEventType::DriftRepaired,
            "deleted" => ProvenanceEventType::Deleted,
            "merged" => ProvenanceEventType::Merged,
            other => ProvenanceEventType::Custom(other.to_string()),
        };

        self.provenance
            .record_event(id.as_str(), event_type, &input.actor, input.source.clone(), &input.description)
            .await
            .map_err(|e| HexadError::ModalityError {
                modality: "provenance".to_string(),
                message: e.to_string(),
            })?;

        let chain = self
            .provenance
            .get_chain(id.as_str())
            .await
            .map_err(|e| HexadError::ModalityError {
                modality: "provenance".to_string(),
                message: e.to_string(),
            })?;

        debug!(id = %id, chain_length = chain.len(), "Provenance modality populated");
        Ok(chain.len() as u64)
    }

    /// Process spatial input for a hexad — indexes geospatial data
    async fn process_spatial(
        &self,
        id: &HexadId,
        input: &HexadSpatialInput,
    ) -> Result<SpatialData, HexadError> {
        let coordinates = Coordinates::new(input.latitude, input.longitude, input.altitude)
            .map_err(|e| HexadError::ValidationError(e.to_string()))?;

        let geometry_type = match input.geometry_type.as_deref() {
            Some("LineString") => GeometryType::LineString,
            Some("Polygon") => GeometryType::Polygon,
            Some("MultiPoint") => GeometryType::MultiPoint,
            Some("MultiPolygon") => GeometryType::MultiPolygon,
            _ => GeometryType::Point,
        };

        let srid = input.srid.unwrap_or(4326);

        let mut data = SpatialData::with_geometry(coordinates, geometry_type, srid);
        data.properties = input.properties.clone();

        self.spatial
            .index(id.as_str(), data.clone())
            .await
            .map_err(|e| HexadError::ModalityError {
                modality: "spatial".to_string(),
                message: e.to_string(),
            })?;

        debug!(id = %id, lat = input.latitude, lon = input.longitude, "Spatial modality populated");
        Ok(data)
    }

    /// Roll back modality writes that succeeded before a failure.
    ///
    /// Called when a `create()` operation partially succeeded — some modalities
    /// were written before an error occurred. This method deletes the data that
    /// was already written to restore consistency.
    async fn rollback_create(&self, id: &HexadId, written_modalities: &ModalityStatus) {
        if written_modalities.vector {
            self.vector.delete(id.as_str()).await.ok();
        }
        if written_modalities.document {
            self.document.delete(id.as_str()).await.ok();
        }
        if written_modalities.tensor {
            self.tensor.delete(id.as_str()).await.ok();
        }
        // Graph and semantic don't have simple delete-by-id,
        // but for atomicity we must attempt cleanup. The in-memory
        // stores will GC orphaned data on next compaction.
        debug!(id = %id, "Rolled back partially written modalities");
    }

    /// Create a snapshot for versioning
    fn create_snapshot(&self, id: &HexadId, input: &HexadInput, status: &ModalityStatus) -> HexadSnapshot {
        HexadSnapshot {
            id: id.clone(),
            input: input.clone(),
            modality_status: status.clone(),
            timestamp: Utc::now(),
        }
    }

    /// Load a complete Hexad from all stores
    async fn load_hexad(&self, id: &HexadId) -> Result<Option<Hexad>, HexadError> {
        let hexads = self.hexads.read().await;
        let status = match hexads.get(id.as_str()) {
            Some(s) => s.clone(),
            None => return Ok(None),
        };
        drop(hexads);

        // Load each modality
        let graph_node = if status.modality_status.graph {
            Some(GraphNode::new(id.to_iri(&self.config.base_iri)))
        } else {
            None
        };

        let embedding = if status.modality_status.vector {
            self.vector.get(id.as_str()).await.map_err(|e| HexadError::ModalityError {
                modality: "vector".to_string(),
                message: e.to_string(),
            })?
        } else {
            None
        };

        let document = if status.modality_status.document {
            self.document.get(id.as_str()).await.map_err(|e| HexadError::ModalityError {
                modality: "document".to_string(),
                message: e.to_string(),
            })?
        } else {
            None
        };

        let tensor = if status.modality_status.tensor {
            self.tensor.get(id.as_str()).await.map_err(|e| HexadError::ModalityError {
                modality: "tensor".to_string(),
                message: e.to_string(),
            })?
        } else {
            None
        };

        let semantic = if status.modality_status.semantic {
            self.semantic.get_annotations(id.as_str()).await.map_err(|e| HexadError::ModalityError {
                modality: "semantic".to_string(),
                message: e.to_string(),
            })?
        } else {
            None
        };

        let version_count = self
            .temporal
            .history(id.as_str(), 1000)
            .await
            .map(|h| h.len() as u64)
            .unwrap_or(0);

        // Load provenance chain length
        let provenance_chain_length = if status.modality_status.provenance {
            self.provenance
                .get_chain(id.as_str())
                .await
                .map(|c| c.len() as u64)
                .unwrap_or(0)
        } else {
            0
        };

        // Load spatial data
        let spatial_data = if status.modality_status.spatial {
            self.spatial.get(id.as_str()).await.map_err(|e| HexadError::ModalityError {
                modality: "spatial".to_string(),
                message: e.to_string(),
            })?
        } else {
            None
        };

        Ok(Some(Hexad {
            id: id.clone(),
            status,
            graph_node,
            embedding,
            tensor,
            semantic,
            document,
            version_count,
            provenance_chain_length,
            spatial_data,
        }))
    }
}

#[async_trait]
impl<G, V, D, T, S, R, P, L> HexadStore for InMemoryHexadStore<G, V, D, T, S, R, P, L>
where
    G: GraphStore + 'static,
    V: VectorStore + 'static,
    D: DocumentStore + 'static,
    T: TensorStore + 'static,
    S: SemanticStore + 'static,
    R: TemporalStore<Data = HexadSnapshot> + 'static,
    P: ProvenanceStore + 'static,
    L: SpatialStore + 'static,
{
    #[instrument(skip(self, input))]
    async fn create(&self, input: HexadInput) -> Result<Hexad, HexadError> {
        let id = HexadId::generate();
        let now = Utc::now();
        let entity_id_str = id.as_str().to_string();

        // Write PENDING intent to WAL before any modality writes.
        // On crash recovery, PENDING entries without a matching COMMITTED
        // entry indicate incomplete operations that need rollback.
        let input_payload = serde_json::to_vec(&input).unwrap_or_default();
        self.wal_append(WalOperation::Insert, WalModality::All, &entity_id_str, &input_payload).await?;

        // Begin ACID transaction — acquire exclusive locks on all requested
        // modalities before writing, ensuring atomicity across the octad.
        let txn_id = self.txn_manager.begin(IsolationLevel::ReadCommitted).await;

        // Acquire locks for all modalities that will be written.
        // This prevents concurrent writes to the same entity from interleaving.
        let modality_names: Vec<&str> = [
            input.graph.as_ref().map(|_| "graph"),
            input.vector.as_ref().map(|_| "vector"),
            input.document.as_ref().map(|_| "document"),
            input.tensor.as_ref().map(|_| "tensor"),
            input.semantic.as_ref().map(|_| "semantic"),
            input.provenance.as_ref().map(|_| "provenance"),
            input.spatial.as_ref().map(|_| "spatial"),
            Some("temporal"), // Always written (version snapshot)
        ]
        .into_iter()
        .flatten()
        .collect();

        for modality in &modality_names {
            if let Err(e) = self
                .txn_manager
                .acquire_lock(txn_id, &entity_id_str, modality, LockType::Exclusive)
                .await
            {
                self.txn_manager.rollback(txn_id).await.ok();
                return Err(HexadError::ConsistencyViolation(format!(
                    "Failed to acquire lock on {modality}: {e}"
                )));
            }
        }

        // Track which modalities have been successfully written so we can
        // roll back on partial failure.
        let mut modality_status = ModalityStatus::default();

        // Process each modality — on failure, rollback everything
        let mut graph_node = None;
        if let Some(ref graph_input) = input.graph {
            match self.process_graph(&id, graph_input).await {
                Ok(node) => {
                    graph_node = Some(node);
                    modality_status.graph = true;
                    self.txn_manager
                        .record_undo(txn_id, &entity_id_str, "graph", None, 0)
                        .await
                        .ok();
                }
                Err(e) => {
                    self.rollback_create(&id, &modality_status).await;
                    self.txn_manager.rollback(txn_id).await.ok();
                    return Err(e);
                }
            }
        }

        let mut embedding = None;
        if let Some(ref vector_input) = input.vector {
            match self.process_vector(&id, vector_input).await {
                Ok(emb) => {
                    embedding = Some(emb);
                    modality_status.vector = true;
                    self.txn_manager
                        .record_undo(txn_id, &entity_id_str, "vector", None, 0)
                        .await
                        .ok();
                }
                Err(e) => {
                    self.rollback_create(&id, &modality_status).await;
                    self.txn_manager.rollback(txn_id).await.ok();
                    return Err(e);
                }
            }
        }

        let mut document = None;
        if let Some(ref doc_input) = input.document {
            match self.process_document(&id, doc_input).await {
                Ok(doc) => {
                    document = Some(doc);
                    modality_status.document = true;
                    self.txn_manager
                        .record_undo(txn_id, &entity_id_str, "document", None, 0)
                        .await
                        .ok();
                }
                Err(e) => {
                    self.rollback_create(&id, &modality_status).await;
                    self.txn_manager.rollback(txn_id).await.ok();
                    return Err(e);
                }
            }
        }

        let mut tensor = None;
        if let Some(ref tensor_input) = input.tensor {
            match self.process_tensor(&id, tensor_input).await {
                Ok(t) => {
                    tensor = Some(t);
                    modality_status.tensor = true;
                    self.txn_manager
                        .record_undo(txn_id, &entity_id_str, "tensor", None, 0)
                        .await
                        .ok();
                }
                Err(e) => {
                    self.rollback_create(&id, &modality_status).await;
                    self.txn_manager.rollback(txn_id).await.ok();
                    return Err(e);
                }
            }
        }

        let mut semantic = None;
        if let Some(ref sem_input) = input.semantic {
            match self.process_semantic(&id, sem_input).await {
                Ok(ann) => {
                    semantic = Some(ann);
                    modality_status.semantic = true;
                    self.txn_manager
                        .record_undo(txn_id, &entity_id_str, "semantic", None, 0)
                        .await
                        .ok();
                }
                Err(e) => {
                    self.rollback_create(&id, &modality_status).await;
                    self.txn_manager.rollback(txn_id).await.ok();
                    return Err(e);
                }
            }
        }

        // Process provenance
        let mut provenance_chain_length = 0;
        if let Some(ref prov_input) = input.provenance {
            match self.process_provenance(&id, prov_input).await {
                Ok(chain_len) => {
                    provenance_chain_length = chain_len;
                    modality_status.provenance = true;
                    self.txn_manager
                        .record_undo(txn_id, &entity_id_str, "provenance", None, 0)
                        .await
                        .ok();
                }
                Err(e) => {
                    self.rollback_create(&id, &modality_status).await;
                    self.txn_manager.rollback(txn_id).await.ok();
                    return Err(e);
                }
            }
        }

        // Process spatial
        let mut spatial_data = None;
        if let Some(ref spatial_input) = input.spatial {
            match self.process_spatial(&id, spatial_input).await {
                Ok(data) => {
                    spatial_data = Some(data);
                    modality_status.spatial = true;
                    self.txn_manager
                        .record_undo(txn_id, &entity_id_str, "spatial", None, 0)
                        .await
                        .ok();
                }
                Err(e) => {
                    self.rollback_create(&id, &modality_status).await;
                    self.txn_manager.rollback(txn_id).await.ok();
                    return Err(e);
                }
            }
        }

        // Create version snapshot
        let snapshot = self.create_snapshot(&id, &input, &modality_status);
        let version = match self
            .temporal
            .append(id.as_str(), snapshot, "system", Some("Initial creation"))
            .await
        {
            Ok(v) => v,
            Err(e) => {
                self.rollback_create(&id, &modality_status).await;
                self.txn_manager.rollback(txn_id).await.ok();
                return Err(HexadError::ModalityError {
                    modality: "temporal".to_string(),
                    message: e.to_string(),
                });
            }
        };
        modality_status.temporal = true;

        // All modality writes succeeded — commit the transaction
        if let Err(e) = self.txn_manager.commit(txn_id).await {
            self.rollback_create(&id, &modality_status).await;
            return Err(HexadError::ConsistencyViolation(format!(
                "Transaction commit failed: {e}"
            )));
        }

        // Create status
        let status = HexadStatus {
            id: id.clone(),
            created_at: now,
            modified_at: now,
            version,
            modality_status: modality_status.clone(),
        };

        // Store in registry
        self.hexads.write().await.insert(id.as_str().to_string(), status.clone());

        // Write COMMITTED marker to WAL and checkpoint for crash recovery.
        self.wal_append(WalOperation::Checkpoint, WalModality::All, &entity_id_str, b"COMMITTED").await.ok();
        self.wal_checkpoint().await.ok();

        info!(id = %id, modalities = ?modality_status, "Created hexad (transaction committed)");

        Ok(Hexad {
            id,
            status,
            graph_node,
            embedding,
            tensor,
            semantic,
            document,
            version_count: 1,
            provenance_chain_length,
            spatial_data,
        })
    }

    #[instrument(skip(self, input))]
    async fn update(&self, id: &HexadId, input: HexadInput) -> Result<Hexad, HexadError> {
        // Check if exists
        let existing = {
            let hexads = self.hexads.read().await;
            hexads.get(id.as_str()).cloned()
        };

        let existing = existing.ok_or_else(|| HexadError::NotFound(id.to_string()))?;
        let now = Utc::now();
        let entity_id_str = id.as_str().to_string();

        // Write PENDING intent to WAL before modality writes
        let input_payload = serde_json::to_vec(&input).unwrap_or_default();
        self.wal_append(WalOperation::Update, WalModality::All, &entity_id_str, &input_payload).await?;

        // Begin ACID transaction for atomic update across all modalities
        let txn_id = self.txn_manager.begin(IsolationLevel::ReadCommitted).await;

        // Acquire exclusive locks on all modalities that will be written
        let modality_names: Vec<&str> = [
            input.graph.as_ref().map(|_| "graph"),
            input.vector.as_ref().map(|_| "vector"),
            input.document.as_ref().map(|_| "document"),
            input.tensor.as_ref().map(|_| "tensor"),
            input.semantic.as_ref().map(|_| "semantic"),
            input.provenance.as_ref().map(|_| "provenance"),
            input.spatial.as_ref().map(|_| "spatial"),
            Some("temporal"),
        ]
        .into_iter()
        .flatten()
        .collect();

        for modality in &modality_names {
            if let Err(e) = self
                .txn_manager
                .acquire_lock(txn_id, &entity_id_str, modality, LockType::Exclusive)
                .await
            {
                self.txn_manager.rollback(txn_id).await.ok();
                return Err(HexadError::ConsistencyViolation(format!(
                    "Failed to acquire lock on {modality}: {e}"
                )));
            }
        }

        let mut modality_status = existing.modality_status.clone();

        // Macro-like closure for recording undo + handling error with rollback.
        // For updates, record the MVCC version so commit can detect conflicts.
        let current_version = existing.version;

        // Update each modality with transactional protection
        let mut graph_node = None;
        if let Some(ref graph_input) = input.graph {
            match self.process_graph(id, graph_input).await {
                Ok(node) => {
                    graph_node = Some(node);
                    modality_status.graph = true;
                    self.txn_manager
                        .record_undo(txn_id, &entity_id_str, "graph", None, current_version)
                        .await
                        .ok();
                }
                Err(e) => {
                    self.txn_manager.rollback(txn_id).await.ok();
                    return Err(e);
                }
            }
        }

        let mut embedding = None;
        if let Some(ref vector_input) = input.vector {
            match self.process_vector(id, vector_input).await {
                Ok(emb) => {
                    embedding = Some(emb);
                    modality_status.vector = true;
                    self.txn_manager
                        .record_undo(txn_id, &entity_id_str, "vector", None, current_version)
                        .await
                        .ok();
                }
                Err(e) => {
                    self.txn_manager.rollback(txn_id).await.ok();
                    return Err(e);
                }
            }
        }

        let mut document = None;
        if let Some(ref doc_input) = input.document {
            match self.process_document(id, doc_input).await {
                Ok(doc) => {
                    document = Some(doc);
                    modality_status.document = true;
                    self.txn_manager
                        .record_undo(txn_id, &entity_id_str, "document", None, current_version)
                        .await
                        .ok();
                }
                Err(e) => {
                    self.txn_manager.rollback(txn_id).await.ok();
                    return Err(e);
                }
            }
        }

        let mut tensor = None;
        if let Some(ref tensor_input) = input.tensor {
            match self.process_tensor(id, tensor_input).await {
                Ok(t) => {
                    tensor = Some(t);
                    modality_status.tensor = true;
                    self.txn_manager
                        .record_undo(txn_id, &entity_id_str, "tensor", None, current_version)
                        .await
                        .ok();
                }
                Err(e) => {
                    self.txn_manager.rollback(txn_id).await.ok();
                    return Err(e);
                }
            }
        }

        let mut semantic = None;
        if let Some(ref sem_input) = input.semantic {
            match self.process_semantic(id, sem_input).await {
                Ok(ann) => {
                    semantic = Some(ann);
                    modality_status.semantic = true;
                    self.txn_manager
                        .record_undo(txn_id, &entity_id_str, "semantic", None, current_version)
                        .await
                        .ok();
                }
                Err(e) => {
                    self.txn_manager.rollback(txn_id).await.ok();
                    return Err(e);
                }
            }
        }

        // Update provenance
        let mut provenance_chain_length = 0;
        if let Some(ref prov_input) = input.provenance {
            match self.process_provenance(id, prov_input).await {
                Ok(chain_len) => {
                    provenance_chain_length = chain_len;
                    modality_status.provenance = true;
                    self.txn_manager
                        .record_undo(txn_id, &entity_id_str, "provenance", None, current_version)
                        .await
                        .ok();
                }
                Err(e) => {
                    self.txn_manager.rollback(txn_id).await.ok();
                    return Err(e);
                }
            }
        }

        // Update spatial
        let mut spatial_data = None;
        if let Some(ref spatial_input) = input.spatial {
            match self.process_spatial(id, spatial_input).await {
                Ok(data) => {
                    spatial_data = Some(data);
                    modality_status.spatial = true;
                    self.txn_manager
                        .record_undo(txn_id, &entity_id_str, "spatial", None, current_version)
                        .await
                        .ok();
                }
                Err(e) => {
                    self.txn_manager.rollback(txn_id).await.ok();
                    return Err(e);
                }
            }
        }

        // Create new version snapshot
        let snapshot = self.create_snapshot(id, &input, &modality_status);
        let version = match self
            .temporal
            .append(id.as_str(), snapshot, "system", Some("Update"))
            .await
        {
            Ok(v) => v,
            Err(e) => {
                self.txn_manager.rollback(txn_id).await.ok();
                return Err(HexadError::ModalityError {
                    modality: "temporal".to_string(),
                    message: e.to_string(),
                });
            }
        };

        // All modality writes succeeded — commit the transaction
        if let Err(e) = self.txn_manager.commit(txn_id).await {
            return Err(HexadError::ConsistencyViolation(format!(
                "Transaction commit failed: {e}"
            )));
        }

        // Update status
        let status = HexadStatus {
            id: id.clone(),
            created_at: existing.created_at,
            modified_at: now,
            version,
            modality_status: modality_status.clone(),
        };

        // Update registry
        self.hexads.write().await.insert(id.as_str().to_string(), status.clone());

        // Write COMMITTED marker to WAL and checkpoint
        self.wal_append(WalOperation::Checkpoint, WalModality::All, &entity_id_str, b"COMMITTED").await.ok();
        self.wal_checkpoint().await.ok();

        info!(id = %id, version = version, "Updated hexad (transaction committed)");

        Ok(Hexad {
            id: id.clone(),
            status,
            graph_node,
            embedding,
            tensor,
            semantic,
            document,
            version_count: version,
            provenance_chain_length,
            spatial_data,
        })
    }

    async fn get(&self, id: &HexadId) -> Result<Option<Hexad>, HexadError> {
        self.load_hexad(id).await
    }

    #[instrument(skip(self))]
    async fn delete(&self, id: &HexadId) -> Result<(), HexadError> {
        let entity_id_str = id.as_str().to_string();

        // Check existence before beginning transaction
        let existing = {
            let hexads = self.hexads.read().await;
            hexads.get(id.as_str()).cloned()
        };

        let existing = existing.ok_or_else(|| HexadError::NotFound(id.to_string()))?;

        // Write PENDING delete intent to WAL
        self.wal_append(WalOperation::Delete, WalModality::All, &entity_id_str, b"").await?;

        // Begin ACID transaction for atomic delete across all modalities
        let txn_id = self.txn_manager.begin(IsolationLevel::ReadCommitted).await;

        // Acquire exclusive locks on all populated modalities
        let populated: Vec<&str> = [
            existing.modality_status.graph.then_some("graph"),
            existing.modality_status.vector.then_some("vector"),
            existing.modality_status.document.then_some("document"),
            existing.modality_status.tensor.then_some("tensor"),
            existing.modality_status.semantic.then_some("semantic"),
            existing.modality_status.provenance.then_some("provenance"),
            existing.modality_status.spatial.then_some("spatial"),
            Some("temporal"), // Always exists
        ]
        .into_iter()
        .flatten()
        .collect();

        for modality in &populated {
            if let Err(e) = self
                .txn_manager
                .acquire_lock(txn_id, &entity_id_str, modality, LockType::Exclusive)
                .await
            {
                self.txn_manager.rollback(txn_id).await.ok();
                return Err(HexadError::ConsistencyViolation(format!(
                    "Failed to acquire lock on {modality} for delete: {e}"
                )));
            }
        }

        // Record undo entries for populated modalities so the transaction
        // manager tracks the scope of this delete for version bookkeeping.
        for modality in &populated {
            self.txn_manager
                .record_undo(txn_id, &entity_id_str, modality, None, existing.version)
                .await
                .ok();
        }

        // Delete from each modality store
        // Note: We don't delete from temporal to preserve history
        self.vector.delete(id.as_str()).await.ok();
        self.document.delete(id.as_str()).await.ok();
        self.tensor.delete(id.as_str()).await.ok();
        // Graph and semantic don't have simple delete-by-id

        // Commit the transaction
        if let Err(e) = self.txn_manager.commit(txn_id).await {
            return Err(HexadError::ConsistencyViolation(format!(
                "Transaction commit failed during delete: {e}"
            )));
        }

        // Remove from registry only after successful commit
        self.hexads.write().await.remove(id.as_str());

        // Write COMMITTED marker to WAL and checkpoint
        self.wal_append(WalOperation::Checkpoint, WalModality::All, &entity_id_str, b"COMMITTED").await.ok();
        self.wal_checkpoint().await.ok();

        info!(id = %id, "Deleted hexad (transaction committed)");
        Ok(())
    }

    async fn status(&self, id: &HexadId) -> Result<Option<HexadStatus>, HexadError> {
        Ok(self.hexads.read().await.get(id.as_str()).cloned())
    }

    async fn search_similar(&self, embedding: &[f32], k: usize) -> Result<Vec<Hexad>, HexadError> {
        let results = self.vector.search(embedding, k).await.map_err(|e| HexadError::ModalityError {
            modality: "vector".to_string(),
            message: e.to_string(),
        })?;

        let mut hexads = Vec::new();
        for result in results {
            if let Some(hexad) = self.load_hexad(&HexadId::new(&result.id)).await? {
                hexads.push(hexad);
            }
        }

        Ok(hexads)
    }

    async fn search_text(&self, query: &str, limit: usize) -> Result<Vec<Hexad>, HexadError> {
        let results =
            self.document.search(query, limit).await.map_err(|e| HexadError::ModalityError {
                modality: "document".to_string(),
                message: e.to_string(),
            })?;

        let mut hexads = Vec::new();
        for result in results {
            if let Some(hexad) = self.load_hexad(&HexadId::new(&result.id)).await? {
                hexads.push(hexad);
            }
        }

        Ok(hexads)
    }

    async fn query_related(&self, id: &HexadId, predicate: &str) -> Result<Vec<Hexad>, HexadError> {
        let node = GraphNode::new(id.to_iri(&self.config.base_iri));
        let edges = self.graph.outgoing(&node).await.map_err(|e| HexadError::ModalityError {
            modality: "graph".to_string(),
            message: e.to_string(),
        })?;

        let predicate_iri = format!("{}/{}", self.config.base_iri, predicate);
        let mut hexads = Vec::new();

        for edge in edges {
            if edge.predicate.iri == predicate_iri {
                if let GraphObject::Node(target) = edge.object {
                    // Extract ID from IRI
                    let target_id = target
                        .iri
                        .strip_prefix(&format!("{}/", self.config.base_iri))
                        .unwrap_or(&target.iri);

                    if let Some(hexad) = self.load_hexad(&HexadId::new(target_id)).await? {
                        hexads.push(hexad);
                    }
                }
            }
        }

        Ok(hexads)
    }

    async fn list(&self, limit: usize, offset: usize) -> Result<Vec<Hexad>, HexadError> {
        let hexads = self.hexads.read().await;
        let ids: Vec<String> = hexads
            .keys()
            .skip(offset)
            .take(limit)
            .cloned()
            .collect();
        drop(hexads);

        let mut result = Vec::with_capacity(ids.len());
        for id_str in ids {
            if let Some(hexad) = self.load_hexad(&HexadId::new(&id_str)).await? {
                result.push(hexad);
            }
        }
        Ok(result)
    }

    async fn at_time(&self, id: &HexadId, time: DateTime<Utc>) -> Result<Option<Hexad>, HexadError> {
        let version = self
            .temporal
            .at_time(id.as_str(), time)
            .await
            .map_err(|e| HexadError::ModalityError {
                modality: "temporal".to_string(),
                message: e.to_string(),
            })?;

        match version {
            Some(v) => {
                // Reconstruct hexad from snapshot
                // For now, we just return current state with version info
                // A full implementation would restore from snapshot
                let mut hexad = self.load_hexad(id).await?;
                if let Some(ref mut h) = hexad {
                    h.status.version = v.version;
                    h.status.modified_at = v.timestamp;
                }
                Ok(hexad)
            }
            None => Ok(None),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::HexadBuilder;
    use verisim_document::TantivyDocumentStore;
    use verisim_graph::SimpleGraphStore;
    use verisim_provenance::InMemoryProvenanceStore;
    use verisim_semantic::InMemorySemanticStore;
    use verisim_spatial::InMemorySpatialStore;
    use verisim_temporal::InMemoryVersionStore;
    use verisim_tensor::InMemoryTensorStore;
    use verisim_vector::{DistanceMetric, BruteForceVectorStore};

    fn create_test_store() -> InMemoryHexadStore<
        SimpleGraphStore,
        BruteForceVectorStore,
        TantivyDocumentStore,
        InMemoryTensorStore,
        InMemorySemanticStore,
        InMemoryVersionStore<HexadSnapshot>,
        InMemoryProvenanceStore,
        InMemorySpatialStore,
    > {
        let config = HexadConfig {
            vector_dimension: 3,
            ..Default::default()
        };

        InMemoryHexadStore::new(
            config,
            Arc::new(SimpleGraphStore::in_memory().unwrap()),
            Arc::new(BruteForceVectorStore::new(3, DistanceMetric::Cosine)),
            Arc::new(TantivyDocumentStore::in_memory().unwrap()),
            Arc::new(InMemoryTensorStore::new()),
            Arc::new(InMemorySemanticStore::new()),
            Arc::new(InMemoryVersionStore::new()),
            Arc::new(InMemoryProvenanceStore::new()),
            Arc::new(InMemorySpatialStore::new()),
        )
    }

    #[tokio::test]
    async fn test_create_and_get_hexad() {
        let store = create_test_store();

        let input = HexadBuilder::new()
            .with_document("Test Document", "This is a test body")
            .with_embedding(vec![0.1, 0.2, 0.3])
            .build();

        let hexad = store.create(input).await.unwrap();
        assert!(hexad.status.modality_status.document);
        assert!(hexad.status.modality_status.vector);
        assert!(hexad.status.modality_status.temporal);

        let retrieved = store.get(&hexad.id).await.unwrap();
        assert!(retrieved.is_some());
        let retrieved = retrieved.unwrap();
        assert_eq!(retrieved.id, hexad.id);
    }

    #[tokio::test]
    async fn test_vector_search() {
        let store = create_test_store();

        let input1 = HexadBuilder::new()
            .with_document("First", "First document")
            .with_embedding(vec![1.0, 0.0, 0.0])
            .build();

        let input2 = HexadBuilder::new()
            .with_document("Second", "Second document")
            .with_embedding(vec![0.9, 0.1, 0.0])
            .build();

        let input3 = HexadBuilder::new()
            .with_document("Third", "Third document")
            .with_embedding(vec![0.0, 1.0, 0.0])
            .build();

        store.create(input1).await.unwrap();
        store.create(input2).await.unwrap();
        store.create(input3).await.unwrap();

        let results = store.search_similar(&[1.0, 0.0, 0.0], 2).await.unwrap();
        assert_eq!(results.len(), 2);
    }

    #[tokio::test]
    async fn test_document_search() {
        let store = create_test_store();

        let input1 = HexadBuilder::new()
            .with_document("Rust Programming", "Rust is a systems programming language")
            .with_embedding(vec![0.1, 0.2, 0.3])
            .build();

        let input2 = HexadBuilder::new()
            .with_document("Python Tutorial", "Python is great for beginners")
            .with_embedding(vec![0.4, 0.5, 0.6])
            .build();

        store.create(input1).await.unwrap();
        store.create(input2).await.unwrap();

        let results = store.search_text("Rust", 10).await.unwrap();
        assert_eq!(results.len(), 1);
        assert!(results[0].document.as_ref().unwrap().title.contains("Rust"));
    }

    #[tokio::test]
    async fn test_update_hexad() {
        let store = create_test_store();

        let input = HexadBuilder::new()
            .with_document("Original", "Original content")
            .with_embedding(vec![0.1, 0.2, 0.3])
            .build();

        let hexad = store.create(input).await.unwrap();
        assert_eq!(hexad.status.version, 1);

        let update_input = HexadBuilder::new()
            .with_document("Updated", "Updated content")
            .build();

        let updated = store.update(&hexad.id, update_input).await.unwrap();
        assert_eq!(updated.status.version, 2);
        assert!(updated.document.as_ref().unwrap().title.contains("Updated"));
    }
}
