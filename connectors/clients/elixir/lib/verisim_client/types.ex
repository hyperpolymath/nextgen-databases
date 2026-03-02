# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

defmodule VeriSimClient.Types do
  @moduledoc """
  Type definitions for the VeriSimDB Elixir client SDK.

  These types mirror the VeriSimDB JSON Schema and cover the full octad of
  modalities: Graph, Vector, Tensor, Semantic, Document, Temporal, Provenance,
  and Spatial.

  All types are plain maps (not structs) to maintain wire-format fidelity with
  the REST API. Type specs are provided for documentation and Dialyzer analysis.
  """

  # ---------------------------------------------------------------------------
  # Modality
  # ---------------------------------------------------------------------------

  @typedoc """
  The eight modalities supported by VeriSimDB's octad data model.
  """
  @type modality ::
          :graph
          | :vector
          | :tensor
          | :semantic
          | :document
          | :temporal
          | :provenance
          | :spatial

  @doc "List of all supported modality atoms."
  @spec all_modalities() :: [modality()]
  def all_modalities do
    [:graph, :vector, :tensor, :semantic, :document, :temporal, :provenance, :spatial]
  end

  # ---------------------------------------------------------------------------
  # ModalityStatus
  # ---------------------------------------------------------------------------

  @typedoc """
  Boolean flags indicating which modalities are currently active for a hexad.
  """
  @type modality_status :: %{
          graph: boolean(),
          vector: boolean(),
          tensor: boolean(),
          semantic: boolean(),
          document: boolean(),
          temporal: boolean(),
          provenance: boolean(),
          spatial: boolean()
        }

  # ---------------------------------------------------------------------------
  # HexadStatus (lightweight summary)
  # ---------------------------------------------------------------------------

  @typedoc """
  Lightweight status summary for a hexad entity.
  """
  @type hexad_status :: %{
          id: String.t(),
          created_at: String.t(),
          modified_at: String.t(),
          version: non_neg_integer(),
          modality_status: modality_status()
        }

  # ---------------------------------------------------------------------------
  # Hexad (full entity)
  # ---------------------------------------------------------------------------

  @typedoc """
  A complete hexad entity encompassing all eight modality payloads.
  """
  @type hexad :: %{
          id: String.t(),
          name: String.t(),
          description: String.t() | nil,
          created_at: String.t(),
          modified_at: String.t(),
          version: non_neg_integer(),
          modality_status: modality_status(),
          metadata: map() | nil,
          graph: map() | nil,
          vector: map() | nil,
          tensor: map() | nil,
          semantic: map() | nil,
          document: map() | nil,
          temporal: map() | nil,
          provenance: map() | nil,
          spatial: map() | nil
        }

  # ---------------------------------------------------------------------------
  # HexadInput (create / update payload)
  # ---------------------------------------------------------------------------

  @typedoc """
  Input payload for creating or updating a hexad entity.
  All fields are optional to support partial updates.
  """
  @type hexad_input :: %{
          optional(:name) => String.t(),
          optional(:description) => String.t(),
          optional(:metadata) => map(),
          optional(:graph) => hexad_graph_input(),
          optional(:vector) => hexad_vector_input(),
          optional(:tensor) => hexad_tensor_input(),
          optional(:semantic) => hexad_semantic_input(),
          optional(:document) => hexad_document_input(),
          optional(:temporal) => hexad_temporal_input(),
          optional(:provenance) => hexad_provenance_input(),
          optional(:spatial) => hexad_spatial_input()
        }

  # ---------------------------------------------------------------------------
  # Per-modality input types
  # ---------------------------------------------------------------------------

  @typedoc "Graph modality input: nodes, edges, and properties."
  @type hexad_graph_input :: %{
          optional(:nodes) => [String.t()],
          optional(:edges) => [graph_edge()],
          optional(:properties) => map()
        }

  @typedoc "A single directed edge in the graph modality."
  @type graph_edge :: %{
          source: String.t(),
          target: String.t(),
          label: String.t(),
          optional(:properties) => map()
        }

  @typedoc "Vector modality input: dense embeddings for similarity search."
  @type hexad_vector_input :: %{
          embedding: [float()],
          optional(:dimensions) => non_neg_integer(),
          optional(:model) => String.t()
        }

  @typedoc "Tensor modality input: multi-dimensional numeric data."
  @type hexad_tensor_input :: %{
          data: [float()],
          shape: [non_neg_integer()],
          optional(:dtype) => String.t()
        }

  @typedoc "Semantic modality input: RDF-style triples and ontology references."
  @type hexad_semantic_input :: %{
          optional(:triples) => [semantic_triple()],
          optional(:ontology) => String.t(),
          optional(:annotations) => map()
        }

  @typedoc "A single semantic triple (subject, predicate, object)."
  @type semantic_triple :: %{
          subject: String.t(),
          predicate: String.t(),
          object: String.t()
        }

  @typedoc "Document modality input: unstructured / semi-structured content."
  @type hexad_document_input :: %{
          content: String.t(),
          optional(:content_type) => String.t(),
          optional(:language) => String.t(),
          optional(:metadata) => map()
        }

  @typedoc "Temporal modality input: time-series events and temporal metadata."
  @type hexad_temporal_input :: %{
          timestamp: String.t(),
          optional(:duration_ms) => non_neg_integer(),
          optional(:recurrence) => String.t(),
          optional(:timezone) => String.t(),
          optional(:metadata) => map()
        }

  @typedoc "Provenance modality input: lineage and audit trail events."
  @type hexad_provenance_input :: %{
          event_type: String.t(),
          agent: String.t(),
          optional(:description) => String.t(),
          optional(:source_ids) => [String.t()],
          optional(:metadata) => map()
        }

  @typedoc "Spatial modality input: geospatial coordinates and geometries."
  @type hexad_spatial_input :: %{
          optional(:latitude) => float(),
          optional(:longitude) => float(),
          optional(:altitude) => float(),
          optional(:geometry) => map(),
          optional(:crs) => String.t()
        }

  # ---------------------------------------------------------------------------
  # DriftScore
  # ---------------------------------------------------------------------------

  @typedoc """
  Drift score for a hexad entity, measuring divergence from normalised baseline.
  """
  @type drift_score :: %{
          entity_id: String.t(),
          overall_score: float(),
          modality_scores: %{String.t() => float()},
          last_checked: String.t(),
          needs_normalization: boolean()
        }

  # ---------------------------------------------------------------------------
  # ProvenanceEvent
  # ---------------------------------------------------------------------------

  @typedoc """
  A single immutable event in a hexad's provenance chain.
  """
  @type provenance_event :: %{
          optional(:id) => String.t(),
          entity_id: String.t(),
          event_type: String.t(),
          agent: String.t(),
          optional(:description) => String.t(),
          optional(:timestamp) => String.t(),
          optional(:source_ids) => [String.t()],
          optional(:metadata) => map()
        }

  # ---------------------------------------------------------------------------
  # FederationResult
  # ---------------------------------------------------------------------------

  @typedoc """
  A single result from a federated cross-instance query.
  """
  @type federation_result :: %{
          store_id: String.t(),
          entity: hexad(),
          optional(:score) => float(),
          optional(:latency_ms) => non_neg_integer()
        }

  # ---------------------------------------------------------------------------
  # VqlResponse
  # ---------------------------------------------------------------------------

  @typedoc """
  Response from a VQL query execution or explain request.
  """
  @type vql_response :: %{
          success: boolean(),
          statement_type: String.t(),
          row_count: non_neg_integer(),
          data: term(),
          optional(:message) => String.t()
        }

  # ---------------------------------------------------------------------------
  # ErrorResponse
  # ---------------------------------------------------------------------------

  @typedoc """
  Standard error response body from the VeriSimDB REST API.
  """
  @type error_response :: %{
          error: String.t(),
          message: String.t(),
          optional(:details) => term()
        }

  # ---------------------------------------------------------------------------
  # PaginatedResponse
  # ---------------------------------------------------------------------------

  @typedoc """
  Generic wrapper for paginated list responses.
  """
  @type paginated_response :: %{
          data: [term()],
          total: non_neg_integer(),
          limit: non_neg_integer(),
          offset: non_neg_integer(),
          has_more: boolean()
        }
end
