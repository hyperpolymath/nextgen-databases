# Cerro Torre Package Manifest for Dragonfly In-Memory Datastore
# dragonfly/1.36.0

[metadata]
name = "dragonfly"
version = "1.36.0"
revision = 1
summary = "Dragonfly - a modern in-memory datastore, Redis-compatible"
description = """
A high-performance, in-memory datastore compatible with Redis and Memcached APIs.
Built from source on Debian Bookworm Slim.
"""
license = "BUSL-1.1" # Dragonfly's BSL license
homepage = "https://www.dragonflydb.io/"
maintainer = "cerro-torre:db-team"

[provenance]
upstream = "https://github.com/dragonflydb/dragonfly/archive/v1.36.0.tar.gz"
upstream_hash = "sha256:853ace6d57d86bc0b9fcf00a32c498f6fd142b49ada5a92a4f75cdf181fb3429"
imported_from = "dragonflydb:v1.36.0"
import_date = 2026-01-27T00:00:00Z # Today's date

[[inputs.sources]]
id = "dragonfly_source"
type = "tarball"
name = "dragonfly"
version = "1.36.0"

[[inputs.sources.artifacts]]
filename = "v1.36.0.tar.gz"
uri = "https://github.com/dragonflydb/dragonfly/archive/v1.36.0.tar.gz"
sha256 = "853ace6d57d86bc0b9fcf00a32c498f6fd142b49ada5a92a4f75cdf181fb3429"


[dependencies]
build = ["debian-bookworm-slim"]
runtime = [
    "debian-bookworm-slim",
]

[build]
system = "custom"

[[build.plan]]
step = "run"
using = "debian-bookworm-slim"
command = "apt-get"
args = ["update", "--no-cache"]
description = "Update Debian package index"

# Install build tools for Go and Rust
[[build.plan]]
step = "run"
using = "debian-bookworm-slim"
command = "apt-get"
args = ["install", "-y", "git", "build-essential", "pkg-config", "curl", "ca-certificates"]
description = "Install common build dependencies"

# Install Go (specific version as requested by Dragonfly)
# Assumes golang package name is 'golang' in Debian.
[[build.plan]]
step = "run"
using = "debian-bookworm-slim"
command = "apt-get"
args = ["install", "-y", "golang"]
description = "Install Golang"

# Install Rust (specific version as requested by Dragonfly)
# Assuming rustc and cargo packages are 'rustc' and 'cargo' in Debian.
[[build.plan]]
step = "run"
using = "debian-bookworm-slim"
command = "apt-get"
args = ["install", "-y", "rustc", "cargo"]
description = "Install Rust and Cargo"


# --- Dragonfly Build ---
[[build.plan]]
step = "run"
source = "dragonfly_source"
command = "tar"
args = ["xzf", "${SRC}/v1.36.0.tar.gz", "-C", "/tmp"]
description = "Extract Dragonfly source"

[[build.plan]]
step = "run"
command = "mv"
args = ["/tmp/dragonfly-1.36.0", "/tmp/dragonfly"] # Rename extracted dir
description = "Rename extracted directory"

[[build.plan]]
step = "run"
command = "sh"
args = ["-c", "cd /tmp/dragonfly && git config submodule.flatbuffers/third_party/flatbuffers/go.url https://github.com/google/flatbuffers/go.git"]
description = "Configure git submodule URL"

[[build.plan]]
step = "run"
command = "sh"
args = ["-c", "cd /tmp/dragonfly && git submodule update --init --recursive --jobs=$(nproc)"]
description = "Update git submodules"

[[build.plan]]
step = "run"
command = "sh"
args = ["-c", "cd /tmp/dragonfly && make all"] # Using make all as it seems to build everything needed
description = "Build Dragonfly"

[[build.plan]]
step = "run"
command = "cp"
args = ["/tmp/dragonfly/dragonfly", "/usr/local/bin/dragonfly"]
description = "Install Dragonfly binary"

# --- Cleanup ---
[[build.plan]]
step = "run"
command = "apt-get"
args = ["remove", "-y", "git", "build-essential", "pkg-config", "curl", "golang", "rustc", "cargo"]
description = "Remove build dependencies"

[[build.plan]]
step = "run"
command = "apt-get"
args = ["autoremove", "-y"]
description = "Autoremove unused packages"

[[build.plan]]
step = "run"
command = "apt-get"
args = ["clean"]
description = "Clean apt cache"

[[build.plan]]
step = "run"
command = "rm"
args = ["-rf", "/var/lib/apt/lists/*", "/tmp/dragonfly"]
description = "Clean up build artifacts and apt cache"

[[build.plan]]
step = "emit_oci_image"
[build.plan.image]
entrypoint = ["/usr/local/bin/dragonfly"]
cmd = ["--port", "6379"] # Default command to start Dragonfly
expose_ports = ["6379"]

[outputs]
primary = "dragonfly"

[attestations]
require = ["source-signature", "reproducible-build", "sbom-complete"]
recommend = ["security-audit"]
