// SPDX-License-Identifier: PMPL-1.0-or-later

/**
 * Lith API Specification Types
 *
 * Internal representation of the API for code generation
 */

/** HTTP method */
type httpMethod = GET | POST | PUT | DELETE | PATCH

/** Parameter location */
type paramLocation = Path | Query | Header | Body

/** Data type for parameters and responses */
type dataType =
  | String
  | Int
  | Float
  | Bool
  | Array(dataType)
  | Object(array<(string, dataType)>)
  | Optional(dataType)
  | Enum(string, array<string>)
  | Ref(string)

/** API parameter */
type parameter = {
  name: string,
  location: paramLocation,
  dataType: dataType,
  required: bool,
  description: string,
}

/** API endpoint */
type endpoint = {
  name: string,
  method: httpMethod,
  path: string,
  description: string,
  parameters: array<parameter>,
  requestBody: option<dataType>,
  responseType: dataType,
  tags: array<string>,
}

/** Type definition for generated code */
type typeDef = {
  name: string,
  dataType: dataType,
  description: string,
}

/** Complete API specification */
type apiSpec = {
  name: string,
  version: string,
  baseUrl: string,
  description: string,
  endpoints: array<endpoint>,
  types: array<typeDef>,
}

/** Lith API specification */
let lithSpec: apiSpec = {
  name: "Lith",
  version: "0.0.6",
  baseUrl: "/v1",
  description: "Lith REST API - Narrative-first, reversible, audit-grade database",
  endpoints: [
    // Query
    {
      name: "query",
      method: POST,
      path: "/query",
      description: "Execute an FDQL query",
      parameters: [],
      requestBody: Some(Object([
        ("fdql", String),
        ("provenance", Optional(Ref("Provenance"))),
        ("explain", Optional(Bool)),
      ])),
      responseType: Ref("QueryResult"),
      tags: ["Query"],
    },
    // Collections
    {
      name: "listCollections",
      method: GET,
      path: "/collections",
      description: "List all collections",
      parameters: [],
      requestBody: None,
      responseType: Array(Ref("Collection")),
      tags: ["Collections"],
    },
    {
      name: "getCollection",
      method: GET,
      path: "/collections/{name}",
      description: "Get a specific collection",
      parameters: [{
        name: "name",
        location: Path,
        dataType: String,
        required: true,
        description: "Collection name",
      }],
      requestBody: None,
      responseType: Ref("Collection"),
      tags: ["Collections"],
    },
    {
      name: "createCollection",
      method: POST,
      path: "/collections",
      description: "Create a new collection",
      parameters: [],
      requestBody: Some(Object([
        ("name", String),
        ("type", Ref("CollectionType")),
        ("schema", Optional(Ref("JsonSchema"))),
      ])),
      responseType: Ref("Collection"),
      tags: ["Collections"],
    },
    {
      name: "deleteCollection",
      method: DELETE,
      path: "/collections/{name}",
      description: "Delete a collection",
      parameters: [{
        name: "name",
        location: Path,
        dataType: String,
        required: true,
        description: "Collection name",
      }],
      requestBody: None,
      responseType: Object([]),
      tags: ["Collections"],
    },
    // Journal
    {
      name: "getJournal",
      method: GET,
      path: "/journal",
      description: "Get journal entries",
      parameters: [
        {
          name: "since",
          location: Query,
          dataType: Optional(Int),
          required: false,
          description: "Sequence number to start from",
        },
        {
          name: "limit",
          location: Query,
          dataType: Optional(Int),
          required: false,
          description: "Maximum entries to return",
        },
        {
          name: "collection",
          location: Query,
          dataType: Optional(String),
          required: false,
          description: "Filter by collection",
        },
      ],
      requestBody: None,
      responseType: Array(Ref("JournalEntry")),
      tags: ["Journal"],
    },
    // Normalization
    {
      name: "discoverDependencies",
      method: POST,
      path: "/normalize/discover",
      description: "Discover functional dependencies",
      parameters: [],
      requestBody: Some(Object([
        ("collection", String),
        ("minConfidence", Optional(Float)),
      ])),
      responseType: Array(Ref("FunctionalDependency")),
      tags: ["Normalization"],
    },
    {
      name: "analyzeNormalForm",
      method: POST,
      path: "/normalize/analyze",
      description: "Analyze normal form",
      parameters: [],
      requestBody: Some(Object([("collection", String)])),
      responseType: Ref("NormalFormAnalysis"),
      tags: ["Normalization"],
    },
    // Migration
    {
      name: "startMigration",
      method: POST,
      path: "/migrate/start",
      description: "Start a migration",
      parameters: [],
      requestBody: Some(Object([
        ("collection", String),
        ("targetForm", Ref("NormalForm")),
      ])),
      responseType: Ref("MigrationStatus"),
      tags: ["Migration"],
    },
    {
      name: "commitMigration",
      method: POST,
      path: "/migrate/commit",
      description: "Commit a migration",
      parameters: [],
      requestBody: Some(Object([("migrationId", String)])),
      responseType: Object([]),
      tags: ["Migration"],
    },
    // Health
    {
      name: "health",
      method: GET,
      path: "/health",
      description: "Check server health",
      parameters: [],
      requestBody: None,
      responseType: Ref("HealthResponse"),
      tags: ["Health"],
    },
  ],
  types: [
    {
      name: "Provenance",
      dataType: Object([("actor", String), ("rationale", String)]),
      description: "Audit trail metadata",
    },
    {
      name: "QueryResult",
      dataType: Object([
        ("rows", Array(Object([]))),
        ("rowCount", Int),
        ("affectedCount", Optional(Int)),
        ("executionTimeMs", Optional(Float)),
      ]),
      description: "Query result",
    },
    {
      name: "CollectionType",
      dataType: Enum("CollectionType", ["document", "edge", "schema"]),
      description: "Collection type",
    },
    {
      name: "Collection",
      dataType: Object([
        ("name", String),
        ("type", Ref("CollectionType")),
        ("documentCount", Int),
        ("createdAt", String),
        ("updatedAt", String),
      ]),
      description: "Collection metadata",
    },
    {
      name: "JournalOperation",
      dataType: Enum("JournalOperation", [
        "INSERT", "UPDATE", "DELETE",
        "CREATE_COLLECTION", "DROP_COLLECTION",
        "MIGRATION_START", "MIGRATION_COMMIT", "MIGRATION_ROLLBACK",
      ]),
      description: "Journal operation type",
    },
    {
      name: "JournalEntry",
      dataType: Object([
        ("seq", Int),
        ("operation", Ref("JournalOperation")),
        ("collection", String),
        ("documentId", Optional(String)),
        ("timestamp", String),
        ("provenance", Optional(Ref("Provenance"))),
      ]),
      description: "Journal entry",
    },
    {
      name: "NormalForm",
      dataType: Enum("NormalForm", ["1NF", "2NF", "3NF", "BCNF"]),
      description: "Normal form level",
    },
    {
      name: "ConfidenceLevel",
      dataType: Enum("ConfidenceLevel", ["HIGH", "MEDIUM", "LOW"]),
      description: "Confidence level",
    },
    {
      name: "FunctionalDependency",
      dataType: Object([
        ("determinant", Array(String)),
        ("dependent", String),
        ("confidence", Ref("ConfidenceLevel")),
      ]),
      description: "Functional dependency",
    },
    {
      name: "NormalFormAnalysis",
      dataType: Object([
        ("collection", String),
        ("currentForm", Ref("NormalForm")),
        ("targetForm", Ref("NormalForm")),
        ("functionalDependencies", Array(Ref("FunctionalDependency"))),
        ("violations", Array(String)),
        ("recommendations", Array(String)),
      ]),
      description: "Normal form analysis result",
    },
    {
      name: "MigrationPhase",
      dataType: Enum("MigrationPhase", ["ANNOUNCE", "SHADOW", "COMMIT", "ROLLBACK"]),
      description: "Migration phase",
    },
    {
      name: "MigrationStatus",
      dataType: Object([
        ("id", String),
        ("phase", Ref("MigrationPhase")),
        ("collection", String),
        ("startedAt", String),
        ("narrative", String),
      ]),
      description: "Migration status",
    },
    {
      name: "HealthStatus",
      dataType: Enum("HealthStatus", ["HEALTHY", "DEGRADED", "UNHEALTHY"]),
      description: "Health status",
    },
    {
      name: "HealthResponse",
      dataType: Object([
        ("status", Ref("HealthStatus")),
        ("version", String),
        ("uptimeSeconds", Int),
      ]),
      description: "Health response",
    },
  ],
}
