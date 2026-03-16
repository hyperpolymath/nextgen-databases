; SPDX-License-Identifier: PMPL-1.0-or-later
; Lith-Geo Ecosystem Definition
; Media Type: application/vnd.ecosystem+scm

(ecosystem
  (version "1.0.0")
  (name "lithoglyph-geo")
  (type "projection-service")
  (purpose "Spatial indexing and geospatial queries over Lith documents")

  (position-in-ecosystem
    (layer "query-projection")
    (role "Provides R-tree spatial indexing as a materialized projection over Lith")
    (data-flow "Lith → lithoglyph-geo (read-only projection)")
    (integration-point "HTTP API consuming Lith collections"))

  (related-projects
    (project
      (name "lith")
      (relationship "upstream-dependency")
      (description "Source of truth for all document data")
      (integration "HTTP API fetch from collections"))

    (project
      (name "lithoglyph-studio")
      (relationship "sibling-service")
      (description "GUI for Lith - may consume geo API for map visualization")
      (integration "Could call /geo/* endpoints for location-based UI"))

    (project
      (name "lithoglyph-analytics")
      (relationship "sibling-service")
      (description "OLAP analytics layer - may use geo data for spatial aggregations")
      (integration "Could share spatial projections"))

    (project
      (name "bofig")
      (relationship "potential-consumer")
      (description "Evidence graph for journalism with location-tagged evidence")
      (integration "Could use geo queries for location-based evidence retrieval"))

    (project
      (name "anamnesis")
      (relationship "potential-consumer")
      (description "Conversation knowledge extraction with location context")
      (integration "Could enrich conversations with spatial relationships")))

  (what-this-is
    ("R-tree spatial index over Lith documents")
    ("Materialized projection - Lith remains source of truth")
    ("HTTP API for bounding box, radius, and nearest-neighbor queries")
    ("Haversine distance calculations for geographic accuracy")
    ("Automatic reindexing from Lith on demand"))

  (what-this-is-not
    ("Not a spatial database - just an index/projection")
    ("Not a data store - reads from Lith, stores nothing persistent")
    ("Not a replacement for PostGIS or similar - lightweight projection only")
    ("Not geospatial analysis - just spatial queries")
    ("Not responsible for data integrity - Lith handles that")))
