// SPDX-License-Identifier: PMPL-1.0-or-later
// Example VCL queries for the playground.
// Covers all 8 octad modalities, real backend queries, and VCL-UT proof types.

type example = {
  label: string,
  query: string,
  vclDt: bool,
}

let examples = [
  // --- Standard VCL examples ---
  {
    label: "List all hexads",
    query: "SELECT * FROM hexads LIMIT 10",
    vclDt: false,
  },
  {
    label: "Full-text search",
    query: "SEARCH TEXT 'multimodal database' LIMIT 10",
    vclDt: false,
  },
  {
    label: "Vector similarity search",
    query: "SEARCH VECTOR [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8] LIMIT 5",
    vclDt: false,
  },
  {
    label: "Graph traversal",
    query: "SEARCH RELATED 'entity-1' BY 'relates_to'",
    vclDt: false,
  },
  {
    label: "Insert a hexad",
    query: "INSERT INTO hexads (title, body)\nVALUES ('My Entity', 'A multimodal entity in VeriSimDB')",
    vclDt: false,
  },
  {
    label: "Show server status",
    query: "SHOW STATUS",
    vclDt: false,
  },
  {
    label: "Show drift metrics",
    query: "SHOW DRIFT",
    vclDt: false,
  },
  {
    label: "Explain a query",
    query: "EXPLAIN SELECT * FROM hexads WHERE id = 'my-entity' LIMIT 1",
    vclDt: false,
  },
  {
    label: "Count hexads",
    query: "COUNT hexads",
    vclDt: false,
  },
  {
    label: "Multi-modality query (demo)",
    query: "SELECT GRAPH, VECTOR, DOCUMENT, PROVENANCE\nFROM HEXAD\nWHERE name CONTAINS 'example'\nORDER BY score DESC\nLIMIT 20",
    vclDt: false,
  },
  {
    label: "Temporal query (demo)",
    query: "SELECT TEMPORAL, PROVENANCE\nFROM HEXAD\nAT TIME '2026-02-28T00:00:00Z'\nWHERE id = 'entity-123'\nLIMIT 1",
    vclDt: false,
  },
  {
    label: "Federation query (demo)",
    query: "SELECT GRAPH\nFROM FEDERATION STORE 'remote-cluster-1'\nHEXAD\nWHERE region = 'eu-west'\nLIMIT 25",
    vclDt: false,
  },
  // --- VCL-UT examples ---
  {
    label: "Proof of existence (VCL-UT)",
    query: "SELECT SEMANTIC\nFROM HEXAD\nPROOF EXISTENCE\nTHRESHOLD 0.95\nWHERE type = 'Certificate'\nLIMIT 10",
    vclDt: true,
  },
  {
    label: "Integrity proof (VCL-UT)",
    query: "SELECT SEMANTIC, DOCUMENT\nFROM HEXAD\nPROOF INTEGRITY\nTHRESHOLD 0.99\nWHERE classification = 'audit-trail'\nLIMIT 5",
    vclDt: true,
  },
  {
    label: "Consistency check (VCL-UT)",
    query: "SELECT GRAPH, SEMANTIC\nFROM HEXAD\nPROOF CONSISTENCY\nTHRESHOLD 0.9\nWHERE DRIFT THRESHOLD 0.1\nLIMIT 20",
    vclDt: true,
  },
  {
    label: "Provenance proof (VCL-UT)",
    query: "SELECT PROVENANCE, SEMANTIC\nFROM HEXAD\nPROOF PROVENANCE\nTHRESHOLD 0.95\nWHERE source = 'verified-origin'\nLIMIT 10",
    vclDt: true,
  },
  {
    label: "Freshness proof (VCL-UT)",
    query: "SELECT TEMPORAL, SEMANTIC\nFROM HEXAD\nPROOF FRESHNESS\nTHRESHOLD 0.99\nWHERE age_ms < 86400000\nLIMIT 10",
    vclDt: true,
  },
  {
    label: "Multi-proof composition (VCL-UT)",
    query: "SELECT SEMANTIC, PROVENANCE, TEMPORAL\nFROM HEXAD\nPROOF EXISTENCE AND INTEGRITY AND FRESHNESS\nTHRESHOLD 0.95\nWHERE type = 'critical-entity'\nLIMIT 5",
    vclDt: true,
  },
]

let forMode = (vclDt: bool): array<example> =>
  examples->Array.filter(e => !e.vclDt || vclDt)
