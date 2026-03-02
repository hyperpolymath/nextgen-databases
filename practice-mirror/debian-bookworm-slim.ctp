# Cerro Torre Package Manifest
# debian-bookworm-slim/latest

[metadata]
name = "debian-bookworm-slim"
version = "1.0.0" # A logical version for this base image
revision = 1
summary = "Debian Bookworm Slim base image for Cerro Torre"
description = "A minimal Debian Bookworm Slim base image imported via Cerro Torre's build plan, mimicking docker.io/debian:bookworm-slim."
license = "MIT" # Debian is Free Software
homepage = "https://www.debian.org/"
maintainer = "cerro-torre:system-team"

[provenance]
upstream = "https://hub.docker.com/_/debian" # Reference to upstream source
upstream_hash = "sha256:PLACEHOLDER" # Will be filled by cerro-torre during build process
imported_from = "docker.io/debian:bookworm-slim"
import_date = 2026-01-27T00:00:00Z # Today's date

[upstream]
family = "debian"
suite = "bookworm-slim"
snapshot_service = "snapshot.debian.org" # Debian snapshot service
snapshot_timestamp = 2026-01-27T00:00:00Z # Pin to a specific timestamp for reproducibility

[[build.plan]]
step = "import"
using = "debian"
profile = "bookworm-slim" # Requesting the slim profile

[[build.plan]]
step = "emit_oci_image" # Output as an OCI compatible image

[outputs]
primary = "debian-bookworm-slim"

[attestations]
require = ["source-signature", "reproducible-build", "sbom-complete"]
recommend = ["security-audit"]
