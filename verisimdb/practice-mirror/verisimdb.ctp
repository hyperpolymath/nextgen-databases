# Cerro Torre Package Manifest for VeriSimDB
# verisimdb/latest

[metadata]
name = "verisimdb"
version = "0.1.0" # Placeholder, actual version from verisimdb project
revision = 1
summary = "VeriSimDB - The Veridical Simulacrum Database"
description = """
A multimodal database with federation capabilities,
built using Rust and Elixir on Debian Bookworm Slim,
as defined by its Containerfile and cerro-torre manifest.
"""
license = "PMPL-1.0-or-later" # VeriSimDB license from Containerfile
homepage = "https://github.com/hyperpolymath/verisimdb"
maintainer = "cerro-torre:db-team"

[provenance]
upstream = "https://github.com/hyperpolymath/verisimdb"
# Commit hash for verisimdb source, to be provided by user
upstream_hash = "sha1:fd3b385d4dd8a1424fc3d7d9a6a8e9b2a7d50279"
imported_from = "verisimdb:fd3b385d4dd8a1424fc3d7d9a6a8e9b2a7d50279"
import_date = 2026-01-27T00:00:00Z # Today's date

# We'll treat the entire verisimdb repository as a single source for simplicity
# and copy it into the build context.
[[inputs.sources]]
id = "verisimdb_repo"
type = "git" # Assuming it's a git repo
name = "verisimdb"
version = "fd3b385d4dd8a1424fc3d7d9a6a8e9b2a7d50279" # Specific commit hash
# We need to specify the commit hash here for provenance
# SHA256 of the git tarball for the specific commit or tag
# The user needs to provide this.
# For now, placeholder for the git source itself.
[[inputs.sources.artifacts]]
filename = "fd3b385d4dd8a1424fc3d7d9a6a8e9b2a7d50279.tar.gz" # Representing the tarball of the specific commit
uri = "https://github.com/hyperpolymath/verisimdb/archive/fd3b385d4dd8a1424fc3d7d9a6a8e9b2a7d50279.tar.gz"
sha256 = "716b9e8053fe43a85d85a863f12d325a4ab3337aa06b90b74c23f409a198983d"


[dependencies]
build = ["debian-bookworm-slim"] # Base image for build context
runtime = [
    "debian-bookworm-slim",
    "libssl3", # Runtime dependency for Rust binaries
    "ca-certificates" # Runtime dependency
]

[build]
system = "custom"

[[build.plan]]
step = "run"
using = "debian-bookworm-slim"
command = "apt-get"
args = ["update", "--no-cache"]
description = "Update Debian package index"

# Install build tools for Rust and Elixir
[[build.plan]]
step = "run"
using = "debian-bookworm-slim"
command = "apt-get"
args = ["install", "-y", "git", "pkg-config", "libssl-dev", "ca-certificates"]
description = "Install common build dependencies"

[[build.plan]]
step = "run"
using = "debian-bookworm-slim"
command = "sh"
args = ["-c", "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain 1.83.0"]
description = "Install Rust (version 1.83.0 as per Dockerfile)"

[[build.plan]]
step = "run"
using = "debian-bookworm-slim"
command = "sh"
args = ["-c", "export PATH=\"$HOME/.cargo/bin:$PATH\"; rustup toolchain install 1.17.0; rustup default 1.17.0; curl -fsSL https://raw.githubusercontent.com/asdf-vm/asdf-install/main/asdf.sh | bash; asdf plugin add elixir https://github.com/asdf-vm/asdf-elixir.git; asdf install elixir 1.17.0; asdf global elixir 1.17.0;"]
description = "Install Elixir (version 1.17.0 as per Dockerfile) and ASDF for management."

[[build.plan]]
step = "run"
command = "sh"
args = ["-c", "export PATH=\"$HOME/.cargo/bin:$PATH\"; rustc --version"]
description = "Verify Rust installation"

[[build.plan]]
step = "run"
command = "sh"
args = ["-c", "export PATH=\"$HOME/.asdf/bin:$HOME/.asdf/shims:$PATH\"; elixir --version"]
description = "Verify Elixir installation"

# Copy VeriSimDB source code into the build context
[[build.plan]]
step = "run"
command = "mkdir"
args = ["-p", "/build"]
description = "Create build directory"

[[build.plan]]
step = "copy"
from = "${SRC}/verisimdb_repo/" # Copy the entire source repository
to = "/build/"
description = "Copy verisimdb source repository"

# Stage 1: Build Rust
[[build.plan]]
step = "run"
command = "sh"
args = ["-c", "export PATH=\"$HOME/.cargo/bin:$PATH\"; cd /build && cargo build --release"]
description = "Build verisimdb Rust components"

# Stage 2: Build Elixir (if releases were configured, otherwise just copy source)
[[build.plan]]
step = "run"
command = "sh"
args = ["-c", "export PATH=\"$HOME/.asdf/bin:$HOME/.asdf/shims:$PATH\"; cd /build/elixir-orchestration && mix local.hex --force && mix local.rebar --force && mix deps.get --only prod && mix compile"]
description = "Compile verisimdb Elixir components"

# Runtime Environment
[[build.plan]]
step = "run"
command = "mkdir"
args = ["-p", "/app"]
description = "Create /app directory for runtime"

[[build.plan]]
step = "copy"
from = "/build/target/release/verisim-api"
to = "/app/verisim-api"
description = "Copy compiled Rust binary to runtime directory"

# Copy Elixir artifacts if they were built (assuming elixir-orchestration is a top-level dir)
# For now, as per original Containerfile, assuming Elixir is not built into a release here.
# User will need to specify how Elixir is deployed if not just via "mix run"
#[[build.plan]]
#step = "copy"
#from = "/build/elixir-orchestration/_build/prod/rel/verisim"
#to = "/app/elixir/"
#description = "Copy compiled Elixir release"

# Cleanup build artifacts
[[build.plan]]
step = "run"
command = "apt-get"
args = ["remove", "-y", "git", "pkg-config", "libssl-dev", "build-essential"]
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
args = ["-rf", "/var/lib/apt/lists/*", "/build", "~/.cargo", "~/.rustup", "~/.asdf"]
description = "Clean up build directories and caches"

[[build.plan]]
step = "emit_oci_image"
[build.plan.image]
entrypoint = ["/app/verisim-api"] # As per original Containerfile
expose_ports = ["8080"]
env = [
    "RUST_LOG=info",
    "VERISIM_HOST=0.0.0.0",
    "VERISIM_PORT=8080"
]

[outputs]
primary = "verisimdb"

[attestations]
require = ["source-signature", "reproducible-build", "sbom-complete"]
recommend = ["security-audit"]

