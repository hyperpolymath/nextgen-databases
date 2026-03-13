; SPDX-License-Identifier: PMPL-1.0-or-later
; Lith-Geo Meta Information
; Media Type: application/meta+scheme

(meta
  (architecture-decisions
    (adr
      (id "adr-001")
      (title "Use R-tree for spatial indexing")
      (status "accepted")
      (date "2025-01-16")
      (context "Need efficient spatial queries (bbox, radius, nearest) over geographic points")
      (decision "Use rstar crate which provides a pure-Rust R-tree implementation with bulk loading")
      (consequences
        ("O(log n) query performance for spatial operations")
        ("Memory-resident index requires rebuild on restart")
        ("Well-tested, production-ready implementation")))

    (adr
      (id "adr-002")
      (title "Projection architecture - Lith as source of truth")
      (status "accepted")
      (date "2025-01-16")
      (context "Lith philosophy prioritizes auditability over performance; spatial queries need fast lookups")
      (decision "lithoglyph-geo is a materialized projection that reads from Lith but does not persist spatial data independently")
      (consequences
        ("Spatial index must be rebuilt from Lith on restart")
        ("No risk of data divergence - Lith is always authoritative")
        ("Aligns with Lith's reversibility principle")))

    (adr
      (id "adr-003")
      (title "Haversine distance for geographic calculations")
      (status "accepted")
      (date "2025-01-16")
      (context "Need accurate distance calculations on Earth's surface for radius queries")
      (decision "Use Haversine formula via geo crate for distance calculations")
      (consequences
        ("Accurate for short to medium distances")
        ("Slightly less accurate than Vincenty for very long distances")
        ("Well-understood, standard approach")))

    (adr
      (id "adr-004")
      (title "HTTP API with axum")
      (status "accepted")
      (date "2025-01-16")
      (context "Need to expose spatial queries as a service that other Lith ecosystem tools can consume")
      (decision "Use axum framework for async HTTP API")
      (consequences
        ("Modern, ergonomic Rust web framework")
        ("Good integration with tokio runtime")
        ("Type-safe request extraction")))

    (adr
      (id "adr-005")
      (title "Support multiple location formats")
      (status "accepted")
      (date "2025-01-16")
      (context "Lith documents may store locations in various formats")
      (decision "Support object format {lat, lon}, array format [lon, lat], and GeoJSON Point")
      (consequences
        ("Flexibility for document authors")
        ("GeoJSON order is [lon, lat] which differs from common intuition")
        ("Must document supported formats clearly"))))

  (development-practices
    (code-style
      (formatter "rustfmt")
      (linter "clippy")
      (edition "2021"))
    (security
      (dependencies "Audit with cargo-audit")
      (input-validation "Validate all query parameters")
      (rate-limiting "TODO: Add rate limiting for production"))
    (testing
      (unit-tests "In module with #[cfg(test)]")
      (integration-tests "tests/ directory")
      (coverage-target 80))
    (versioning "Semantic versioning")
    (documentation
      (readme "README.adoc")
      (api-docs "OpenAPI 3.0 (planned)")
      (inline "/// doc comments"))
    (branching
      (main "main - stable releases")
      (develop "dev - integration branch")
      (features "feat/* - feature branches")))

  (design-rationale
    (why-rust
      "Performance-critical spatial operations benefit from Rust's zero-cost abstractions. The rstar R-tree implementation is pure Rust with excellent performance characteristics.")
    (why-separate-repo
      "Lith's philosophy explicitly deprioritizes performance (Auditability > Performance). Spatial queries require optimized data structures. Separation maintains Lith's principles while enabling fast spatial lookups.")
    (why-in-memory-index
      "Spatial data is derived from Lith, so persistence would duplicate data. In-memory index with rebuild-on-demand keeps the system simple and prevents data divergence.")
    (why-http-api
      "HTTP provides language-agnostic integration. lithoglyph-studio (ReScript), lithoglyph-analytics (Julia), and other tools can all consume the same spatial API.")))
