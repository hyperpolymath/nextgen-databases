# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim.Federation.Adapter do
  @moduledoc """
  Behaviour for heterogeneous federation adapters.

  VeriSimDB federates across heterogeneous databases — each peer in the
  federation may be a different database system (ArangoDB, PostgreSQL,
  Elasticsearch, or another VeriSimDB instance). Adapters translate between
  VeriSimDB's octad modality model and each backend's native capabilities.

  ## Implementing an Adapter

  Each adapter must implement 5 callbacks:

  - `connect/1` — Establish or verify connectivity to the backend.
  - `query/3` — Translate a VeriSimDB modality query into the backend's
    native query language and return normalised results.
  - `health_check/1` — Check backend availability and return latency.
  - `supported_modalities/1` — Declare which VeriSimDB modalities the
    backend can serve (e.g., PostgreSQL with pgvector supports `:vector`).
  - `translate_results/2` — Normalise backend-specific results into
    VeriSimDB's `FederationResult` format.

  ## Modality Mapping

  Adapters map VeriSimDB's 8 octad modalities to native capabilities:

      ┌─────────────┬──────────────┬─────────────────┬───────────────┐
      │ Modality    │ ArangoDB     │ PostgreSQL      │ Elasticsearch │
      ├─────────────┼──────────────┼─────────────────┼───────────────┤
      │ :graph      │ AQL traversal│ recursive CTE   │ —             │
      │ :vector     │ —            │ pgvector <=>    │ dense_vector  │
      │ :tensor     │ —            │ —               │ —             │
      │ :semantic   │ document     │ JSONB           │ nested object │
      │ :document   │ fulltext idx │ tsvector/GIN    │ full-text     │
      │ :temporal   │ document     │ tstzrange       │ date_range    │
      │ :provenance │ edge coll.   │ audit table     │ —             │
      │ :spatial    │ GeoJSON idx  │ PostGIS         │ geo_shape     │
      └─────────────┴──────────────┴─────────────────┴───────────────┘

      Extended adapters (10 additional backends):

      ┌─────────────┬──────────┬───────┬────────┬────────────┬───────────┐
      │ Modality    │ MongoDB  │ Redis │ DuckDB │ ClickHouse │ SurrealDB │
      ├─────────────┼──────────┼───────┼────────┼────────────┼───────────┤
      │ :graph      │ $graphLkp│ Graph │ rCTE   │ —          │ native    │
      │ :vector     │ AtlasVS  │ VSS   │ HNSW   │ annoy      │ —         │
      │ :tensor     │ —        │ —     │ array  │ —          │ —         │
      │ :semantic   │ BSON     │ JSON  │ JSON   │ JSON       │ schema-   │
      │ :document   │ text idx │ FT    │ FTS    │ fulltext   │ FTS       │
      │ :temporal   │ ISODate  │ TS    │ tstamp │ DateTime64 │ datetime  │
      │ :provenance │ chg strm │ Strm  │ —      │ —          │ —         │
      │ :spatial    │ 2dsphere │ —     │ spat   │ geo funcs  │ —         │
      └─────────────┴──────────┴───────┴────────┴────────────┴───────────┘

      ┌─────────────┬──────────┬──────────┬──────────┬──────────────┐
      │ Modality    │ SQLite   │ Neo4j    │ VectorDB │ InfluxDB     │
      ├─────────────┼──────────┼──────────┼──────────┼──────────────┤
      │ :graph      │ rCTE     │ Cypher   │ —        │ —            │
      │ :vector     │ vss      │ vec idx  │ native   │ —            │
      │ :tensor     │ —        │ —        │ —        │ —            │
      │ :semantic   │ JSON1    │ props    │ payload  │ tags         │
      │ :document   │ FTS5     │ FT idx   │ —        │ —            │
      │ :temporal   │ datetime │ temporal │ ts filt  │ native TS    │
      │ :provenance │ —        │ —        │ —        │ —            │
      │ :spatial    │ —        │ spatial  │ geo filt │ —            │
      └─────────────┴──────────┴──────────┴──────────┴──────────────┘

      ObjectStorage (MinIO/S3): :document, :temporal, :provenance, :semantic

  ## Peer Configuration

  When registering a peer, the `adapter_type` field selects the adapter:

      VeriSim.Federation.Resolver.register_peer("arango-prod", %{
        endpoint: "http://arango.internal:8529",
        adapter_type: :arangodb,
        adapter_config: %{
          database: "_system",
          collection: "hexads",
          auth: {:basic, "root", "password"}
        },
        modalities: [:graph, :document, :semantic, :spatial]
      })

  ## Result Format

  All adapters must return results conforming to `federation_result()`:

      %{
        source_store: "peer-id",
        hexad_id: "entity-id-or-equivalent",
        score: 0.85,
        drifted: false,
        data: %{...},          # Raw data from the backend
        response_time_ms: 42
      }
  """

  # ---------------------------------------------------------------------------
  # Types
  # ---------------------------------------------------------------------------

  @typedoc "Adapter configuration passed during peer registration."
  @type adapter_config :: %{
          optional(:database) => String.t(),
          optional(:collection) => String.t(),
          optional(:index) => String.t(),
          optional(:table) => String.t(),
          optional(:schema) => String.t(),
          optional(:auth) => auth(),
          optional(atom()) => term()
        }

  @typedoc "Authentication credentials for the backend."
  @type auth ::
          {:basic, String.t(), String.t()}
          | {:bearer, String.t()}
          | {:api_key, String.t()}
          | :none

  @typedoc "Peer connection details passed to adapter callbacks."
  @type peer_info :: %{
          store_id: String.t(),
          endpoint: String.t(),
          adapter_config: adapter_config()
        }

  @typedoc "A VeriSimDB modality that can be queried."
  @type modality ::
          :graph
          | :vector
          | :tensor
          | :semantic
          | :document
          | :temporal
          | :provenance
          | :spatial

  @typedoc "Query parameters passed to the adapter."
  @type query_params :: %{
          required(:modalities) => [modality()],
          required(:limit) => non_neg_integer(),
          optional(:text_query) => String.t(),
          optional(:vector_query) => [float()],
          optional(:graph_pattern) => String.t(),
          optional(:spatial_bounds) => map(),
          optional(:temporal_range) => map(),
          optional(:filters) => map()
        }

  @typedoc "Normalised result from a federated query."
  @type federation_result :: %{
          source_store: String.t(),
          hexad_id: String.t(),
          score: float(),
          drifted: boolean(),
          data: map(),
          response_time_ms: non_neg_integer()
        }

  @typedoc "Health check result with latency measurement."
  @type health_result ::
          {:ok, non_neg_integer()}
          | {:error, term()}

  # ---------------------------------------------------------------------------
  # Callbacks
  # ---------------------------------------------------------------------------

  @doc """
  Verify connectivity to the backend.

  Called during peer registration and periodically during health checks.
  Should return `:ok` if the backend is reachable and properly configured,
  or `{:error, reason}` otherwise.
  """
  @callback connect(peer_info()) :: :ok | {:error, term()}

  @doc """
  Execute a query against the backend.

  Translates VeriSimDB's modality-based query into the backend's native
  query language (AQL, SQL, Elasticsearch DSL, etc.), executes it, and
  returns normalised results.

  The `query_params` map contains the requested modalities and any
  modality-specific query parameters (text queries, vector embeddings,
  graph traversal patterns, spatial bounds, etc.).

  Results must be normalised to `[federation_result()]` format.
  """
  @callback query(peer_info(), query_params(), keyword()) ::
              {:ok, [federation_result()]} | {:error, term()}

  @doc """
  Check backend health and return response latency in milliseconds.

  Used by the federation resolver to update peer trust levels.
  A successful health check increases trust; failures decrease it.
  """
  @callback health_check(peer_info()) :: health_result()

  @doc """
  Declare which VeriSimDB modalities this backend can serve.

  Called during peer registration to validate that the peer's declared
  modalities are actually supported by the adapter. Returns the subset
  of modalities the backend can serve.

  For example, a PostgreSQL instance with pgvector and PostGIS installed
  might return `[:document, :vector, :spatial, :semantic, :temporal]`.
  """
  @callback supported_modalities(adapter_config()) :: [modality()]

  @doc """
  Normalise backend-specific results into VeriSimDB's federation format.

  This is called internally by `query/3` but is exposed as a callback
  so that custom result transforms can be tested independently.
  """
  @callback translate_results([map()], peer_info()) :: [federation_result()]

  # ---------------------------------------------------------------------------
  # Adapter Registry
  # ---------------------------------------------------------------------------

  @doc """
  Look up the adapter module for a given adapter type atom.

  ## Examples

      iex> VeriSim.Federation.Adapter.module_for(:verisimdb)
      {:ok, VeriSim.Federation.Adapters.VeriSimDB}

      iex> VeriSim.Federation.Adapter.module_for(:arangodb)
      {:ok, VeriSim.Federation.Adapters.ArangoDB}

      iex> VeriSim.Federation.Adapter.module_for(:unknown)
      {:error, :unknown_adapter}
  """
  @spec module_for(atom()) :: {:ok, module()} | {:error, :unknown_adapter}
  def module_for(:verisimdb), do: {:ok, VeriSim.Federation.Adapters.VeriSimDB}
  def module_for(:arangodb), do: {:ok, VeriSim.Federation.Adapters.ArangoDB}
  def module_for(:postgresql), do: {:ok, VeriSim.Federation.Adapters.PostgreSQL}
  def module_for(:elasticsearch), do: {:ok, VeriSim.Federation.Adapters.Elasticsearch}
  def module_for(:mongodb), do: {:ok, VeriSim.Federation.Adapters.MongoDB}
  def module_for(:redis), do: {:ok, VeriSim.Federation.Adapters.Redis}
  def module_for(:duckdb), do: {:ok, VeriSim.Federation.Adapters.DuckDB}
  def module_for(:clickhouse), do: {:ok, VeriSim.Federation.Adapters.ClickHouse}
  def module_for(:surrealdb), do: {:ok, VeriSim.Federation.Adapters.SurrealDB}
  def module_for(:sqlite), do: {:ok, VeriSim.Federation.Adapters.SQLite}
  def module_for(:neo4j), do: {:ok, VeriSim.Federation.Adapters.Neo4j}
  def module_for(:vector_db), do: {:ok, VeriSim.Federation.Adapters.VectorDB}
  def module_for(:influxdb), do: {:ok, VeriSim.Federation.Adapters.InfluxDB}
  def module_for(:object_storage), do: {:ok, VeriSim.Federation.Adapters.ObjectStorage}
  def module_for(_), do: {:error, :unknown_adapter}

  @doc """
  List all registered adapter types.
  """
  @spec adapter_types() :: [atom()]
  def adapter_types do
    [
      :verisimdb,
      :arangodb,
      :postgresql,
      :elasticsearch,
      :mongodb,
      :redis,
      :duckdb,
      :clickhouse,
      :surrealdb,
      :sqlite,
      :neo4j,
      :vector_db,
      :influxdb,
      :object_storage
    ]
  end
end
