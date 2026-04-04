// SPDX-License-Identifier: PMPL-1.0-or-later
// Author: Jonathan D.A. Jewell <6759885+hyperpolymath@users.noreply.github.com>
//! Write throughput, read latency, and VQL complexity benchmarks for VeriSimDB.
//!
//! This file augments `modality_benchmarks.rs` with system-level throughput
//! and latency measurements that correspond to the missing benchmarks listed
//! in `TEST-NEEDS.md`:
//!
//!   - Write throughput   — N octad inserts/second on the OctadStore hot path.
//!   - Read latency       — hot path (cached entity), cold path (uncached entity).
//!   - VQL execution time — by query complexity (simple, moderate, complex).
//!
//! The benchmarks use in-memory stores only (no persistent disk I/O) to give
//! reproducible baseline numbers across environments.
//!
//! ## Store construction
//!
//! `InMemoryOctadStore::new` takes 9 arguments (in this order):
//!   config, graph, vector, document, tensor, semantic, temporal, provenance, spatial
//!
//! We use `SimpleGraphStore` and `BruteForceVectorStore` — the same combination
//! that `verisim-api` uses in its `ConcreteOctadStore` type alias.

use criterion::{
    black_box, criterion_group, criterion_main, BenchmarkId, Criterion, Throughput,
};
use std::collections::HashMap;
use std::sync::Arc;
use tokio::runtime::Runtime;

use verisim_document::TantivyDocumentStore;
use verisim_graph::SimpleGraphStore;
use verisim_octad::{
    InMemoryOctadStore, OctadConfig, OctadDocumentInput, OctadInput, OctadSnapshot, OctadStore,
    OctadVectorInput,
};
use verisim_provenance::InMemoryProvenanceStore;
use verisim_semantic::InMemorySemanticStore;
use verisim_spatial::InMemorySpatialStore;
use verisim_temporal::InMemoryVersionStore;
use verisim_tensor::InMemoryTensorStore;
use verisim_vector::{BruteForceVectorStore, DistanceMetric};

// ============================================================================
// Concrete type alias
//
// Matches the `ConcreteOctadStore` type in `verisim-api/src/lib.rs` (the
// in-memory / non-persistent configuration).
// ============================================================================

type BenchOctadStore = InMemoryOctadStore<
    SimpleGraphStore,
    BruteForceVectorStore,
    TantivyDocumentStore,
    InMemoryTensorStore,
    InMemorySemanticStore,
    InMemoryVersionStore<OctadSnapshot>,
    InMemoryProvenanceStore,
    InMemorySpatialStore,
>;

// ============================================================================
// Store factory helpers
// ============================================================================

/// Create a fresh in-memory OctadStore for benchmarking.
///
/// All 9 modality stores are in-memory. This is the standard VeriSimDB
/// configuration deployed by consuming projects (IDApTIK, Burble, Hypatia).
fn make_octad_store() -> BenchOctadStore {
    let graph = Arc::new(SimpleGraphStore::new());
    let vector = Arc::new(BruteForceVectorStore::new(384, DistanceMetric::Cosine));
    let document = Arc::new(TantivyDocumentStore::in_memory().unwrap());
    let tensor = Arc::new(InMemoryTensorStore::new());
    let semantic = Arc::new(InMemorySemanticStore::new());
    let temporal = Arc::new(InMemoryVersionStore::new());
    let provenance = Arc::new(InMemoryProvenanceStore::new());
    let spatial = Arc::new(InMemorySpatialStore::new());

    let config = OctadConfig::default();

    InMemoryOctadStore::new(
        config, graph, vector, document, tensor, semantic, temporal, provenance, spatial,
    )
}

/// Build an OctadInput with document + vector modalities.
///
/// Each call produces a structurally unique entity via the counter `i`
/// to prevent deduplication from masking real insertion cost.
fn make_octad_input(i: usize) -> OctadInput {
    OctadInput {
        document: Some(OctadDocumentInput {
            title: format!("Throughput Benchmark Entity {}", i),
            body: format!(
                "Benchmark entity {} measuring write throughput and latency in VeriSimDB.",
                i
            ),
            fields: HashMap::new(),
        }),
        vector: Some(OctadVectorInput {
            embedding: {
                let mut v = vec![0.0f32; 384];
                v[0] = (i as f32) / 100_000.0;
                v
            },
            model: None,
        }),
        ..Default::default()
    }
}

// ============================================================================
// Write Throughput Benchmarks
//
// Measures the number of octad inserts per second on the hot path.
// Three batch sizes: 1, 10, 100 inserts per iteration.
// ============================================================================

fn bench_write_throughput(c: &mut Criterion) {
    let rt = Runtime::new().unwrap();
    let mut group = c.benchmark_group("write_throughput");

    for batch_size in [1usize, 10, 100].iter() {
        let n = *batch_size;
        group.throughput(Throughput::Elements(n as u64));

        group.bench_with_input(
            BenchmarkId::new("octad_insert_batch", n),
            &n,
            |b, &n| {
                b.to_async(&rt).iter_batched(
                    // Fresh store per iteration to prevent write hot-caching.
                    make_octad_store,
                    |store| async move {
                        for i in 0..n {
                            black_box(store.create(make_octad_input(i)).await.unwrap());
                        }
                    },
                    criterion::BatchSize::SmallInput,
                );
            },
        );
    }

    group.finish();
}

/// Single-entity write latency — wall-clock time for one `OctadStore::create`
/// with document + vector modalities.
fn bench_single_write_latency(c: &mut Criterion) {
    let rt = Runtime::new().unwrap();
    let mut group = c.benchmark_group("write_latency");

    let store = make_octad_store();
    let mut counter = 0usize;

    group.bench_function("single_octad_create", |b| {
        b.to_async(&rt).iter(|| {
            counter += 1;
            let input = make_octad_input(counter);
            async { black_box(store.create(input).await.unwrap()) }
        });
    });

    group.finish();
}

// ============================================================================
// Read Latency Benchmarks
//
// Hot path:  entity was just written; stores are warm.
// Cold path: entity written first, followed by 10,000 subsequent writes.
// ============================================================================

fn bench_read_latency_hot(c: &mut Criterion) {
    let rt = Runtime::new().unwrap();
    let mut group = c.benchmark_group("read_latency");

    let (hot_id, store) = rt.block_on(async {
        let s = make_octad_store();
        let octad = s.create(make_octad_input(0)).await.unwrap();
        (octad.id.clone(), s)
    });

    group.bench_function("hot_path_get_by_id", |b| {
        b.to_async(&rt).iter(|| async {
            black_box(store.get(&hot_id).await.unwrap())
        });
    });

    group.finish();
}

fn bench_read_latency_cold(c: &mut Criterion) {
    let rt = Runtime::new().unwrap();
    let mut group = c.benchmark_group("read_latency");

    // Write 10,000 entities; retrieve the first one (cold access).
    let (cold_id, store) = rt.block_on(async {
        let s = make_octad_store();
        let first = s.create(make_octad_input(0)).await.unwrap();
        let id = first.id.clone();
        for i in 1..10_000 {
            s.create(make_octad_input(i)).await.unwrap();
        }
        (id, s)
    });

    group.throughput(Throughput::Elements(10_000));

    group.bench_function("cold_path_get_by_id_after_10k_writes", |b| {
        b.to_async(&rt).iter(|| async {
            black_box(store.get(&cold_id).await.unwrap())
        });
    });

    group.finish();
}

// ============================================================================
// VQL Query Execution Time by Complexity
//
// Since the VQL executor runs in Elixir, we proxy three complexity tiers
// via direct OctadStore operations that a VQL query would invoke:
//
//   Simple:   single get-by-ID (1 store lookup)
//   Moderate: get-by-ID + vector similarity (2 store operations)
//   Complex:  full-text search + vector similarity over 1,000 entities
// ============================================================================

fn bench_vql_simple_get(c: &mut Criterion) {
    let rt = Runtime::new().unwrap();
    let mut group = c.benchmark_group("vql_complexity");

    let (entity_id, store) = rt.block_on(async {
        let s = make_octad_store();
        let octad = s.create(make_octad_input(42)).await.unwrap();
        (octad.id.clone(), s)
    });

    group.bench_function("simple_get_by_id", |b| {
        b.to_async(&rt).iter(|| async {
            black_box(store.get(&entity_id).await.unwrap())
        });
    });

    group.finish();
}

fn bench_vql_moderate_multimodal(c: &mut Criterion) {
    let rt = Runtime::new().unwrap();
    let mut group = c.benchmark_group("vql_complexity");

    let (entity_id, store) = rt.block_on(async {
        let s = make_octad_store();
        let mut target = None;
        for i in 0..100 {
            let o = s.create(make_octad_input(i)).await.unwrap();
            if i == 50 {
                target = Some(o.id.clone());
            }
        }
        (target.unwrap(), s)
    });

    // Moderate: get + vector similarity search (2 store operations).
    group.bench_function("moderate_get_plus_vector_search", |b| {
        let query_vec = vec![0.0005f32; 384];
        b.to_async(&rt).iter(|| async {
            let octad = store.get(&entity_id).await.unwrap();
            let similar = store.search_similar(&query_vec, 5).await.unwrap();
            black_box((octad, similar))
        });
    });

    group.finish();
}

fn bench_vql_complex_cross_modal(c: &mut Criterion) {
    let rt = Runtime::new().unwrap();
    let mut group = c.benchmark_group("vql_complexity");

    let store = rt.block_on(async {
        let s = make_octad_store();
        for i in 0..1_000 {
            s.create(make_octad_input(i)).await.unwrap();
        }
        s
    });

    group.throughput(Throughput::Elements(1_000));

    // Complex: full-text + vector search over 1,000 entities.
    group.bench_function("complex_fulltext_plus_vector_over_1k", |b| {
        let query_vec = vec![0.0005f32; 384];
        b.to_async(&rt).iter(|| async {
            let text_results = store.search_text("benchmark", 10).await.unwrap();
            let vec_results = store.search_similar(&query_vec, 10).await.unwrap();
            black_box((text_results, vec_results))
        });
    });

    group.finish();
}

// ============================================================================
// Write-then-Read Round-Trip Latency
//
// Single-node proxy for replication lag: combined cost of one write + one
// read of the same entity.
// ============================================================================

fn bench_write_then_read_latency(c: &mut Criterion) {
    let rt = Runtime::new().unwrap();
    let mut group = c.benchmark_group("replication_latency");

    let store = make_octad_store();
    let mut counter = 0usize;

    group.bench_function("write_then_read_roundtrip", |b| {
        b.to_async(&rt).iter(|| {
            counter += 1;
            let input = make_octad_input(counter);
            async {
                let octad = store.create(input).await.unwrap();
                let retrieved = store.get(&octad.id).await.unwrap();
                black_box((octad, retrieved))
            }
        });
    });

    group.finish();
}

// ============================================================================
// Benchmark Groups
// ============================================================================

criterion_group!(
    write_throughput_benches,
    bench_write_throughput,
    bench_single_write_latency,
);

criterion_group!(
    read_latency_benches,
    bench_read_latency_hot,
    bench_read_latency_cold,
);

criterion_group!(
    vql_complexity_benches,
    bench_vql_simple_get,
    bench_vql_moderate_multimodal,
    bench_vql_complex_cross_modal,
);

criterion_group!(
    replication_latency_benches,
    bench_write_then_read_latency,
);

criterion_main!(
    write_throughput_benches,
    read_latency_benches,
    vql_complexity_benches,
    replication_latency_benches,
);
