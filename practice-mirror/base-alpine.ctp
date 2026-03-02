# Cerro Torre Package Manifest
# alpine-base/3.20.0-1 (example version, will use latest stable in practice)

[metadata]
name = "alpine-base"
version = "3.20.0" # Placeholder, will be determined by actual Alpine version used by cerro-torre
revision = 1
summary = "Base Alpine Linux image for Cerro Torre"
description = "A minimal Alpine Linux base image imported via Cerro Torre's build plan."
license = "MIT" # Alpine is MIT licensed
homepage = "https://www.alpinelinux.org/"
maintainer = "cerro-torre:system-team" # Placeholder maintainer

[provenance]
# For an imported base image, upstream might be implicitly handled by cerro-torre's import
# We'll use a generic reference here for now. Actual source hashes will be managed by cerro-torre.
upstream = "https://www.alpinelinux.org/"
upstream_hash = "sha256:PLACEHOLDER" # Will be filled by cerro-torre during build process
imported_from = "alpine:edge" # Refers to the latest Alpine stable
import_date = 2026-01-27T00:00:00Z # Today's date

[upstream]
family = "alpine"
suite = "edge" # Using 'edge' for the latest stable Alpine. Can be changed to a specific version.
snapshot_service = "dl-cdn.alpinelinux.org" # Official Alpine mirrors
snapshot_timestamp = 2026-01-27T00:00:00Z # Pin to a specific timestamp for reproducibility

[[build.plan]]
step = "import"
using = "alpine"
profile = "minimal" # Requesting a minimal Alpine import profile

[[build.plan]]
step = "emit_oci_image" # Output as an OCI compatible image

[outputs]
primary = "alpine-base" # The name of the primary output package

[attestations]
require = ["source-signature", "reproducible-build", "sbom-complete"]
recommend = ["security-audit"]
