// SPDX-License-Identifier: PMPL-1.0-or-later
//! Performance benchmarks for VeriSimDB modality stores

use criterion::{black_box, criterion_group, criterion_main, BenchmarkId, Criterion, Throughput};
use std::collections::HashMap;
use std::sync::Arc;
use tokio::runtime::Runtime;

use verisim_document::{Document, DocumentStore, TantivyDocumentStore};
use verisim_drift::{DriftDetector, DriftThresholds, DriftType};
use verisim_graph::{GraphEdge, GraphNode, GraphObject, GraphStore, OxiGraphStore};
use verisim_hexad::{
    HexadConfig, HexadDocumentInput, HexadId, HexadInput, HexadSnapshot, HexadStore,
    HexadVectorInput, HexadSemanticInput, InMemoryHexadStore,
};
use verisim_semantic::{
    InMemorySemanticStore, ProofBlob, ProofType, SemanticStore, SemanticType,
};
use verisim_temporal::{InMemoryVersionStore, TemporalStore};
use verisim_tensor::{InMemoryTensorStore, ReduceOp, Tensor, TensorStore};
use verisim_vector::{DistanceMetric, Embedding, HnswConfig, HnswVectorStore, VectorStore};

// ============================================================================
// Document Store Benchmarks
// ============================================================================

fn bench_document_create(c: &mut Criterion) {
    let rt = Runtime::new().unwrap();
    let mut group = c.benchmark_group("document");

    group.bench_function("create_document", |b| {
        let store = TantivyDocumentStore::in_memory().unwrap();
        b.to_async(&rt).iter(|| async {
            let doc = Document::new("test-id", "Benchmark Title", "Benchmark body content for testing indexing performance.");
            black_box(store.index(&doc).await.unwrap())
        });
    });

    group.finish();
}

fn bench_document_search(c: &mut Criterion) {
    let rt = Runtime::new().unwrap();
    let store = TantivyDocumentStore::in_memory().unwrap();

    // Index 1000 documents
    rt.block_on(async {
        for i in 0..1000 {
            let doc = Document::new(
                format!("doc-{}", i),
                format!("Document {}", i),
                format!("This is document number {} with searchable content about machine learning and databases.", i),
            );
            store.index(&doc).await.unwrap();
        }
        store.commit().await.unwrap();
    });

    let mut group = c.benchmark_group("document");
    group.throughput(Throughput::Elements(1000));

    group.bench_function("search_text", |b| {
        b.to_async(&rt).iter(|| async {
            black_box(store.search("machine learning", 10).await.unwrap())
        });
    });

    group.finish();
}

// ============================================================================
// Vector Store Benchmarks
// ============================================================================

fn bench_vector_insert(c: &mut Criterion) {
    let rt = Runtime::new().unwrap();
    let mut group = c.benchmark_group("vector");

    for dim in [128, 384, 768].iter() {
        group.bench_with_input(BenchmarkId::new("upsert", dim), dim, |b, &dim| {
            let store = HnswVectorStore::new(dim, DistanceMetric::Cosine, HnswConfig::default());
            let mut counter = 0u64;

            b.to_async(&rt).iter(|| {
                counter += 1;
                let embedding = Embedding {
                    id: format!("vec-{}", counter),
                    vector: vec![0.5; dim],
                    metadata: HashMap::new(),
                };
                let store_ref = &store;
                async move {
                    black_box(store_ref.upsert(&embedding).await.unwrap())
                }
            });
        });
    }

    group.finish();
}

fn bench_vector_search(c: &mut Criterion) {
    let rt = Runtime::new().unwrap();
    let mut group = c.benchmark_group("vector");

    for dim in [128, 384, 768].iter() {
        group.bench_with_input(BenchmarkId::new("search", dim), dim, |b, &dim| {
            let store = HnswVectorStore::new(dim, DistanceMetric::Cosine, HnswConfig::default());

            // Insert 10000 vectors
            rt.block_on(async {
                for i in 0..10000 {
                    let mut vec_data = vec![0.0f32; dim];
                    vec_data[0] = (i as f32) / 10000.0;
                    let embedding = Embedding {
                        id: format!("vec-{}", i),
                        vector: vec_data,
                        metadata: HashMap::new(),
                    };
                    store.upsert(&embedding).await.unwrap();
                }
            });

            let query = vec![0.5f32; dim];

            b.to_async(&rt).iter(|| async {
                black_box(store.search(&query, 10).await.unwrap())
            });
        });
    }

    group.throughput(Throughput::Elements(10000));
    group.finish();
}

// ============================================================================
// Graph Store Benchmarks
// ============================================================================

fn bench_graph_operations(c: &mut Criterion) {
    let rt = Runtime::new().unwrap();
    let mut group = c.benchmark_group("graph");

    group.bench_function("insert_edge", |b| {
        let store = OxiGraphStore::in_memory().unwrap();
        let mut counter = 0u64;

        b.to_async(&rt).iter(|| {
            counter += 1;
            let edge = GraphEdge {
                subject: GraphNode::new(format!("https://example.org/node/{}", counter)),
                predicate: GraphNode::new("https://example.org/relates_to"),
                object: GraphObject::Node(GraphNode::new(format!("https://example.org/target/{}", counter))),
            };
            let store_ref = &store;
            async move {
                black_box(store_ref.insert(&edge).await.unwrap())
            }
        });
    });

    // Pre-populate for query benchmark
    let query_store = OxiGraphStore::in_memory().unwrap();
    let query_node = GraphNode::new("https://example.org/hub");
    rt.block_on(async {
        for i in 0..100 {
            let edge = GraphEdge {
                subject: query_node.clone(),
                predicate: GraphNode::new("https://example.org/connects"),
                object: GraphObject::Node(GraphNode::new(format!("https://example.org/target/{}", i))),
            };
            query_store.insert(&edge).await.unwrap();
        }
    });

    group.bench_function("query_outgoing", |b| {
        b.to_async(&rt).iter(|| async {
            black_box(query_store.outgoing(&query_node).await.unwrap())
        });
    });

    group.finish();
}

// ============================================================================
// Hexad Store Benchmarks
// ============================================================================

fn bench_hexad_operations(c: &mut Criterion) {
    let rt = Runtime::new().unwrap();
    let mut group = c.benchmark_group("hexad");

    let graph_store = Arc::new(OxiGraphStore::in_memory().unwrap());
    let vector_store = Arc::new(HnswVectorStore::new(384, DistanceMetric::Cosine, HnswConfig::default()));
    let document_store = Arc::new(TantivyDocumentStore::in_memory().unwrap());
    let tensor_store = Arc::new(InMemoryTensorStore::new());
    let semantic_store = Arc::new(InMemorySemanticStore::new());
    let temporal_store: Arc<InMemoryVersionStore<HexadSnapshot>> = Arc::new(InMemoryVersionStore::new());

    let config = HexadConfig::default();

    let store = InMemoryHexadStore::new(
        config,
        graph_store,
        vector_store,
        document_store,
        tensor_store,
        semantic_store,
        temporal_store,
    );

    group.bench_function("create_hexad", |b| {
        b.to_async(&rt).iter(|| async {
            let input = HexadInput {
                document: Some(HexadDocumentInput {
                    title: "Benchmark Hexad".to_string(),
                    body: "Testing hexad creation performance.".to_string(),
                    fields: HashMap::new(),
                }),
                vector: Some(HexadVectorInput {
                    embedding: vec![0.5; 384],
                    model: None,
                }),
                ..Default::default()
            };
            black_box(store.create(input).await.unwrap())
        });
    });

    // Create hexads for retrieval benchmark
    let mut hexad_ids = vec![];
    rt.block_on(async {
        for i in 0..100 {
            let input = HexadInput {
                document: Some(HexadDocumentInput {
                    title: format!("Hexad {}", i),
                    body: format!("Content {}", i),
                    fields: HashMap::new(),
                }),
                vector: Some(HexadVectorInput {
                    embedding: vec![i as f32 / 100.0; 384],
                    model: None,
                }),
                ..Default::default()
            };
            let hexad = store.create(input).await.unwrap();
            hexad_ids.push(hexad.id.clone());
        }
    });

    group.bench_function("get_hexad", |b| {
        let id = hexad_ids[0].clone();
        b.to_async(&rt).iter(|| async {
            black_box(store.get(&id).await.unwrap())
        });
    });

    group.finish();
}

// ============================================================================
// Drift Detection Benchmarks
// ============================================================================

fn bench_drift_detection(c: &mut Criterion) {
    let rt = Runtime::new().unwrap();
    let mut group = c.benchmark_group("drift");

    let detector = DriftDetector::new(DriftThresholds::default());

    group.bench_function("record_drift", |b| {
        b.to_async(&rt).iter(|| async {
            black_box(
                detector
                    .record(
                        DriftType::SemanticVectorDrift,
                        0.15,
                        vec!["entity-bench".to_string()],
                    )
                    .await
                    .unwrap()
            )
        });
    });

    group.bench_function("health_check", |b| {
        b.iter(|| {
            black_box(detector.health_check().unwrap())
        });
    });

    group.finish();
}

// ============================================================================
// Cross-Modal Query Benchmarks
// ============================================================================

fn bench_cross_modal_query(c: &mut Criterion) {
    let rt = Runtime::new().unwrap();
    let mut group = c.benchmark_group("cross_modal");

    let graph_store = Arc::new(OxiGraphStore::in_memory().unwrap());
    let vector_store = Arc::new(HnswVectorStore::new(384, DistanceMetric::Cosine, HnswConfig::default()));
    let document_store = Arc::new(TantivyDocumentStore::in_memory().unwrap());
    let tensor_store = Arc::new(InMemoryTensorStore::new());
    let semantic_store = Arc::new(InMemorySemanticStore::new());
    let temporal_store: Arc<InMemoryVersionStore<HexadSnapshot>> = Arc::new(InMemoryVersionStore::new());

    let config = HexadConfig::default();

    let store = InMemoryHexadStore::new(
        config,
        graph_store,
        vector_store,
        document_store,
        tensor_store,
        semantic_store,
        temporal_store,
    );

    // Create 1000 hexads with multiple modalities
    rt.block_on(async {
        for i in 0..1000 {
            let mut embedding = vec![0.0f32; 384];
            embedding[0] = (i as f32) / 1000.0;

            let input = HexadInput {
                document: Some(HexadDocumentInput {
                    title: format!("Multi-modal Document {}", i),
                    body: format!("Content about machine learning topic {}", i),
                    fields: HashMap::new(),
                }),
                vector: Some(HexadVectorInput {
                    embedding,
                    model: None,
                }),
                semantic: Some(HexadSemanticInput {
                    types: vec!["https://example.org/Document".to_string()],
                    properties: HashMap::new(),
                }),
                ..Default::default()
            };
            store.create(input).await.unwrap();
        }
    });

    group.throughput(Throughput::Elements(1000));

    group.bench_function("vector_similarity_search", |b| {
        let query = vec![0.5f32; 384];
        b.to_async(&rt).iter(|| async {
            black_box(store.search_similar(&query, 10).await.unwrap())
        });
    });

    group.bench_function("fulltext_search", |b| {
        b.to_async(&rt).iter(|| async {
            black_box(store.search_text("machine learning", 10).await.unwrap())
        });
    });

    group.finish();
}

// ============================================================================
// Tensor Store Benchmarks
// ============================================================================

fn bench_tensor_operations(c: &mut Criterion) {
    let rt = Runtime::new().unwrap();
    let mut group = c.benchmark_group("tensor");

    group.bench_function("store_create_64x64", |b| {
        let store = InMemoryTensorStore::new();
        b.to_async(&rt).iter(|| async {
            let data: Vec<f64> = (0..4096).map(|i| (i as f64) * 0.001).collect();
            let tensor = Tensor::new("bench-tensor", vec![64, 64], data).unwrap();
            black_box(store.put(&tensor).await.unwrap())
        });
    });

    // Pre-populate for get benchmark
    let get_store = InMemoryTensorStore::new();
    rt.block_on(async {
        for i in 0..100 {
            let data: Vec<f64> = (0..4096).map(|j| ((i * 4096 + j) as f64) * 0.001).collect();
            let tensor = Tensor::new(format!("tensor-{}", i), vec![64, 64], data).unwrap();
            get_store.put(&tensor).await.unwrap();
        }
    });

    group.bench_function("store_get", |b| {
        b.to_async(&rt).iter(|| async {
            black_box(get_store.get("tensor-50").await.unwrap())
        });
    });

    // Reduce benchmark: sum along axis 0 of a 64x64 tensor
    let reduce_store = InMemoryTensorStore::new();
    rt.block_on(async {
        let data: Vec<f64> = (0..4096).map(|i| (i as f64) * 0.001).collect();
        let tensor = Tensor::new("reduce-tensor", vec![64, 64], data).unwrap();
        reduce_store.put(&tensor).await.unwrap();
    });

    group.bench_function("reduce_sum_axis0", |b| {
        b.to_async(&rt).iter(|| async {
            black_box(reduce_store.reduce("reduce-tensor", 0, ReduceOp::Sum).await.unwrap())
        });
    });

    group.finish();
}

// ============================================================================
// Semantic Store Benchmarks
// ============================================================================

fn bench_semantic_operations(c: &mut Criterion) {
    let rt = Runtime::new().unwrap();
    let mut group = c.benchmark_group("semantic");

    group.bench_function("register_type", |b| {
        let store = InMemorySemanticStore::new();
        let mut counter = 0u64;
        b.to_async(&rt).iter(|| {
            counter += 1;
            let iri = format!("https://example.org/Type{}", counter);
            let typ = SemanticType::new(&iri, "BenchType");
            let store_ref = &store;
            async move {
                black_box(store_ref.register_type(&typ).await.unwrap())
            }
        });
    });

    // Pre-populate for get_type benchmark
    let type_store = InMemorySemanticStore::new();
    rt.block_on(async {
        for i in 0..100 {
            let typ = SemanticType::new(
                format!("https://example.org/Type{}", i),
                format!("Type {}", i),
            );
            type_store.register_type(&typ).await.unwrap();
        }
    });

    group.bench_function("get_type", |b| {
        b.to_async(&rt).iter(|| async {
            black_box(type_store.get_type("https://example.org/Type50").await.unwrap())
        });
    });

    // Proof creation + CBOR serialization
    group.bench_function("proof_create_cbor", |b| {
        let store = InMemorySemanticStore::new();
        b.to_async(&rt).iter(|| async {
            let proof = ProofBlob::new(
                "entity:bench is-a Document",
                ProofType::TypeAssignment,
                vec![1, 2, 3, 4, 5, 6, 7, 8],
            );
            let cbor = black_box(proof.to_cbor().unwrap());
            black_box(store.store_proof(&proof).await.unwrap());
            cbor
        });
    });

    // Proof verification
    let verify_store = InMemorySemanticStore::new();
    rt.block_on(async {
        for i in 0..50 {
            let proof = ProofBlob::new(
                "entity:verify-bench is-a Document",
                ProofType::Attestation,
                vec![i as u8; 32],
            );
            verify_store.store_proof(&proof).await.unwrap();
        }
    });

    group.bench_function("proof_verify", |b| {
        b.to_async(&rt).iter(|| async {
            black_box(verify_store.verify_proofs("entity:verify-bench is-a Document").await.unwrap())
        });
    });

    group.finish();
}

// ============================================================================
// Temporal Store Benchmarks
// ============================================================================

fn bench_temporal_operations(c: &mut Criterion) {
    let rt = Runtime::new().unwrap();
    let mut group = c.benchmark_group("temporal");

    group.bench_function("version_create", |b| {
        let store: InMemoryVersionStore<String> = InMemoryVersionStore::new();
        let mut counter = 0u64;
        b.to_async(&rt).iter(|| {
            counter += 1;
            let entity = format!("entity-{}", counter % 10);
            let data = format!("version data {}", counter);
            let store_ref = &store;
            async move {
                black_box(store_ref.append(&entity, data, "bench-author", Some("bench commit")).await.unwrap())
            }
        });
    });

    // Pre-populate for retrieval benchmarks
    let version_store: InMemoryVersionStore<String> = InMemoryVersionStore::new();
    rt.block_on(async {
        for v in 0..100 {
            version_store
                .append("bench-entity", format!("data v{}", v), "bench-author", Some(&format!("commit {}", v)))
                .await
                .unwrap();
        }
    });

    group.bench_function("version_get_by_number", |b| {
        b.to_async(&rt).iter(|| async {
            black_box(version_store.at_version("bench-entity", 50).await.unwrap())
        });
    });

    group.bench_function("version_get_latest", |b| {
        b.to_async(&rt).iter(|| async {
            black_box(version_store.latest("bench-entity").await.unwrap())
        });
    });

    group.bench_function("history_10", |b| {
        b.to_async(&rt).iter(|| async {
            black_box(version_store.history("bench-entity", 10).await.unwrap())
        });
    });

    group.bench_function("history_100", |b| {
        b.to_async(&rt).iter(|| async {
            black_box(version_store.history("bench-entity", 100).await.unwrap())
        });
    });

    group.finish();
}

// ============================================================================
// Benchmark Groups
// ============================================================================

criterion_group!(
    document_benches,
    bench_document_create,
    bench_document_search
);

criterion_group!(
    vector_benches,
    bench_vector_insert,
    bench_vector_search
);

criterion_group!(
    graph_benches,
    bench_graph_operations
);

criterion_group!(
    hexad_benches,
    bench_hexad_operations
);

criterion_group!(
    drift_benches,
    bench_drift_detection
);

criterion_group!(
    cross_modal_benches,
    bench_cross_modal_query
);

criterion_group!(
    tensor_benches,
    bench_tensor_operations
);

criterion_group!(
    semantic_benches,
    bench_semantic_operations
);

criterion_group!(
    temporal_benches,
    bench_temporal_operations
);

criterion_main!(
    document_benches,
    vector_benches,
    graph_benches,
    hexad_benches,
    drift_benches,
    cross_modal_benches,
    tensor_benches,
    semantic_benches,
    temporal_benches
);
