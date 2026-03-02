;; SPDX-License-Identifier: PMPL-1.0-or-later
;; Media type: application/vnd.ecosystem+scm

(ecosystem
  (version "1.0.0")
  (name "verisimdb")
  (type "database-system")
  (purpose "Cross-system entity consistency engine with drift detection, self-normalisation, and formally verified queries. Eight data modalities — the octad (Graph, Vector, Tensor, Semantic, Document, Temporal, Provenance, Spatial). Operates as standalone database OR heterogeneous federation coordinator over existing databases (ArangoDB, PostgreSQL, Elasticsearch, etc.).")

  (position-in-ecosystem
    (layer "infrastructure")
    (role "core-database")
    (dependencies-on ["oxigraph" "hnsw" "tantivy" "proven" "sactify-php"])
    (provides-to ["researchers" "ai-systems" "knowledge-workers" "federated-institutions"]))

  (related-projects
    (sibling-standard
      (project "verisimdb-debugger")
      (relationship "provides-observability-for")
      (url "https://github.com/hyperpolymath/verisimdb-debugger")
      (rationale "VeriSimDB Debugger (v2) is a separate TUI tool for tracing queries, visualizing drift, and inspecting ZKP proofs. It connects to VeriSimDB instances via API."))

    (potential-consumer
      (project "vql-language-server")
      (relationship "could-provide-ide-integration")
      (url "https://github.com/hyperpolymath/vql-language-server")
      (rationale "Future Language Server Protocol implementation for VQL, providing IDE features like autocomplete, diagnostics, and inline documentation."))

    (potential-consumer
      (project "hypatia")
      (relationship "could-use-for-storage")
      (url "https://github.com/hyperpolymath/hypatia")
      (rationale "Hypatia research assistant could leverage VeriSimDB's multimodal storage for citations (graph), embeddings (vector), and semantic relationships."))

    (dependency
      (project "oxigraph")
      (relationship "uses-for-graph-store")
      (url "https://github.com/oxigraph/oxigraph")
      (rationale "Oxigraph provides RDF/SPARQL support for the graph modality store (verisim-graph)."))

    (dependency
      (project "proven")
      (relationship "uses-for-zkp")
      (url "https://github.com/proven-network/proven")
      (rationale "Proven library provides zero-knowledge proof generation and verification for VQL queries with PROOF clauses."))

    (dependency
      (project "sactify-php")
      (relationship "uses-for-federation-signatures")
      (url "https://github.com/hyperpolymath/sactify-php")
      (rationale "Sactify provides cryptographic signatures for federation store registration and Byzantine fault tolerance."))

    (inspiration
      (project "datomic")
      (relationship "architectural-inspiration")
      (url "https://www.datomic.com")
      (rationale "Datomic's immutable temporal log and separation of storage/query influenced VeriSimDB's temporal modality and hexad architecture."))

    (inspiration
      (project "apache-kafka")
      (relationship "architectural-inspiration")
      (url "https://kafka.apache.org")
      (rationale "KRaft (Kafka without ZooKeeper) inspired VeriSimDB's federated registry design with metadata quorum and Raft consensus."))

    (related-standard
      (project "fair-principles")
      (relationship "implements")
      (url "https://www.go-fair.org/fair-principles/")
      (rationale "VeriSimDB implements FAIR principles (Findable, Accessible, Interoperable, Reusable) through ZKP proofs, federation, semantic types, and provenance lineage."))

    (competitor-space
      (project "great-expectations")
      (relationship "competes-at-different-level")
      (url "https://greatexpectations.io")
      (rationale "Great Expectations validates single tables/columns. VerisimDB validates cross-system entity consistency. Different granularity, different problem."))

    (competitor-space
      (project "monte-carlo-data")
      (relationship "competes-at-different-level")
      (url "https://www.montecarlodata.com")
      (rationale "Monte Carlo detects statistical anomalies in one warehouse. VerisimDB detects semantic inconsistencies across multiple systems at entity level."))

    (first-integration
      (project "idaptik")
      (relationship "first-heterogeneous-federation-consumer")
      (url "https://github.com/hyperpolymath/idaptik")
      (rationale "IDApTIK's database bridge (ArangoDB for game data + VerisimDB for level data) is the first working example of heterogeneous federation — VerisimDB coordinating with a non-VerisimDB database."))

    (interface-layer
      (project "panll")
      (relationship "primary-human-interface")
      (url "https://github.com/hyperpolymath/panll")
      (rationale "PanLL eNSAID (Environment for NeSy-Agentic Integrated Development) is VeriSimDB's primary accessibility layer. Three-pane Binary Star HTI maps directly to VQL-DT: Pane-L shows proof obligations and type constraints, Pane-N shows agentic inference suggestions, Pane-W shows query results, drift heatmaps, and entity explorer. Anti-Crash circuit breaker prevents malformed queries from corrupting data. Vexometer monitors cognitive load during complex VQL-DT sessions. Replaces need for standalone VQL workbench — PanLL is the neurosymbolic agentic DbVisualizer."))

    (sibling-databases
      (project "quandledb")
      (relationship "sibling-nextgen-database")
      (url "https://github.com/hyperpolymath/nextgen-databases")
      (rationale "QuandleDB is a sibling database in the nextgen-databases monorepo. Future PanLL integration will provide unified interface across VeriSimDB (VQL/VQL-DT), QuandleDB (KQL), and LithoGlyph (GQL) — building on the NQC Web UI pattern already demonstrated at nextgen-databases/nqc/web/.")))

  (what-this-is
    "VeriSimDB is a cross-system entity consistency engine. It provides:\n  - Eight modalities (the octad) in one namespace: Graph, Vector, Tensor, Semantic, Document, Temporal, Provenance, Spatial\n  - Drift detection: Detects when different representations of the same entity disagree across systems\n  - Self-normalisation: Automatically repairs inconsistencies by regenerating drifted modalities\n  - Heterogeneous federation: Watches external databases (ArangoDB, PostgreSQL, Elasticsearch) for cross-system consistency without requiring data migration\n  - VQL with dependent types (VQL-DT): Formally verified query results with machine-checkable proof certificates\n  - Provenance/lineage: Tracks where data came from, how it was transformed, and who touched it — across system boundaries\n  - Tensor modality: Multi-dimensional representation with active research into novel applications beyond traditional numeric storage\n  - Zero-knowledge proofs: Verifiable query results without exposing private data (GDPR, HIPAA, FAIR compliance)\n\nThree-layer differentiator:\n  1. Drift detection — the door-opener (easy to explain, everyone has the problem)\n  2. Heterogeneous federation — enterprise value (watches your existing databases)\n  3. VQL-DT formal verification — technical moat (years to replicate)\n\nTarget users: Enterprise data teams (cross-system consistency), regulated industries (formal verification), researchers (citation networks + provenance), arts and digital identity (complex entity triangulation).")

  (what-this-is-not
    "- NOT a traditional relational database (use PostgreSQL for that)\n- NOT a pure graph database (use Neo4j if you only need graphs)\n- NOT a pure vector database (use Pinecone/Weaviate if you only need embeddings)\n- NOT a document store with full-text search only (use Elasticsearch for that)\n- NOT a blockchain (immutable log ≠ distributed ledger)\n- NOT a data lake (VeriSimDB enforces types and semantics)\n- NOT a message queue (though temporal store provides event log)\n- NOT an ETL tool (VeriSimDB eliminates need for ETL between modalities)\n- NOT a single-language system (uses ReScript, Elixir, Rust for different components)\n- NOT production-ready yet (v0.1.0-alpha, ~88% complete, security-hardened)\n- NOT limited to traditional database use cases (octad architecture enables arts, digital identity, and complex entity consistency domains)"))
