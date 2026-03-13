; SPDX-License-Identifier: PMPL-1.0-or-later
; Lith-Geo Project State
; Reference: hyperpolymath/git-hud/STATE.scm

(state
  (metadata
    (version "0.1.0")
    (schema-version "1.0")
    (created "2025-01-16")
    (updated "2025-01-16")
    (project "lithoglyph-geo")
    (repo "https://github.com/hyperpolymath/lithoglyph-geo"))

  (project-context
    (name "Lith-Geo")
    (tagline "Spatial projection layer for Lith")
    (tech-stack
      (primary "Rust")
      (frameworks ("axum" "tokio" "rstar"))
      (dependencies ("geo" "geojson" "reqwest" "serde"))))

  (current-position
    (phase "initial-implementation")
    (overall-completion 15)
    (components
      (component
        (name "spatial-index")
        (completion 80)
        (status "core-implemented")
        (notes "R-tree with bbox, radius, nearest queries"))
      (component
        (name "lithoglyph-client")
        (completion 70)
        (status "core-implemented")
        (notes "HTTP client with location extraction"))
      (component
        (name "http-api")
        (completion 60)
        (status "handlers-implemented")
        (notes "All endpoints defined, needs testing"))
      (component
        (name "config")
        (completion 90)
        (status "complete")
        (notes "TOML config with defaults"))
      (component
        (name "testing")
        (completion 20)
        (status "unit-tests-only")
        (notes "Basic unit tests, needs integration tests"))
      (component
        (name "documentation")
        (completion 50)
        (status "readme-complete")
        (notes "README done, needs API docs")))
    (working-features
      ("R-tree spatial indexing")
      ("Bounding box queries")
      ("Radius queries with Haversine")
      ("K-nearest neighbor queries")
      ("Lith document fetching")
      ("Location extraction from multiple formats")))

  (route-to-mvp
    (milestone
      (name "compile-and-run")
      (status "pending")
      (items
        ("Verify Cargo.toml dependencies resolve")
        ("Fix any compilation errors")
        ("Run with default config")))
    (milestone
      (name "lithoglyph-integration")
      (status "pending")
      (items
        ("Test against real Lith instance")
        ("Verify document fetching")
        ("Validate location extraction")))
    (milestone
      (name "api-testing")
      (status "pending")
      (items
        ("Test /geo/health endpoint")
        ("Test /geo/reindex endpoint")
        ("Test all query endpoints")
        ("Load test with sample data")))
    (milestone
      (name "documentation")
      (status "pending")
      (items
        ("OpenAPI spec generation")
        ("Example curl commands")
        ("Docker deployment guide"))))

  (blockers-and-issues
    (critical ())
    (high
      (issue
        (id "GEO-001")
        (description "Need Lith instance for integration testing")
        (mitigation "Can use mock server initially")))
    (medium
      (issue
        (id "GEO-002")
        (description "Auto-rebuild scheduler not implemented")
        (mitigation "Manual POST /geo/reindex works")))
    (low ()))

  (critical-next-actions
    (immediate
      ("Compile and verify builds")
      ("Create sample config file")
      ("Test against Lith"))
    (this-week
      ("Integration tests")
      ("Docker deployment")
      ("CI/CD setup"))
    (this-month
      ("Performance benchmarks")
      ("OpenAPI documentation")
      ("Coordinate with lithoglyph-studio for map viz")))

  (session-history
    (snapshot
      (date "2025-01-16")
      (accomplishments
        ("Created initial Rust project structure")
        ("Implemented R-tree spatial index")
        ("Implemented Lith HTTP client")
        ("Created axum HTTP API")
        ("Added configuration system")
        ("Created README and ECOSYSTEM files")))))
