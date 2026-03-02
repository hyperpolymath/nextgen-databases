# Cerro Torre Package Manifest for VeriSimDB Connector (V-lang)
# verisimdb-connector/0.1.0

[metadata]
name = "verisimdb-connector"
version = "0.1.0" # Initial version for the connector
revision = 1
summary = "V-lang connector for MariaDB to verisimdb CDC"
description = """
A V-lang application to perform Change Data Capture (CDC)
from MariaDB (binlog) and push data to verisimdb's Hexad API.
Built on Alpine Linux.
"""
license = "MIT" # Placeholder, actual license will be from V-lang project
homepage = "https://github.com/hyperpolymath/verisimdb-connector" # Placeholder
maintainer = "cerro-torre:connector-team"

[provenance]

imported_from = "vlang:weekly.2026.04"
import_date = 2026-01-27T00:00:00Z # Today's date

[[inputs.sources]]
id = "vlang_compiler"
type = "zip"
name = "vlang"
version = "weekly.2026.04"

[[inputs.sources.artifacts]]
filename = "v_linux.zip"
uri = "https://github.com/vlang/v/releases/download/weekly.2026.04/v_linux.zip"
sha256 = "2c68815f5befbe3b849575f17a832ad53d115498ce0dc70ac1c964f6a6264eab"

[[inputs.sources]]
id = "connector_source"
type = "git" # Assuming the connector source is a git repo. This is just a placeholder.
name = "verisimdb-connector-source"
version = "0.1.0" # Or commit hash if it's in a git repo
# For now, it's a local file. We'll add it via copy step.


[dependencies]
build = ["alpine-base"]
runtime = [
    "alpine-base",
    # Add any runtime dependencies for the compiled V-lang app
]

[build]
system = "custom"

[[build.plan]]
step = "run"
using = "alpine-base"
command = "apk"
args = ["update", "--no-cache"]
description = "Update Alpine package index"

[[build.plan]]
step = "run"
using = "alpine-base"
command = "apk"
args = ["add", "--no-cache", "build-base", "curl", "git", "unzip"] # unzip for V-lang zip
description = "Install build tools and git"

# --- Install V-lang ---
[[build.plan]]
step = "run"
source = "vlang_compiler"
command = "unzip"
args = ["-q", "${SRC}/v_linux.zip", "-d", "/tmp/vlang"]
description = "Extract V-lang compiler"

[[build.plan]]
step = "run"
command = "sh"
args = ["-c", "cd /tmp/vlang && make && mv v /usr/local/bin/"]
description = "Build and install V-lang compiler"

# --- Build Connector ---
[[build.plan]]
step = "run"
command = "mkdir"
args = ["-p", "/app/connector"]
description = "Create app directory for connector source"

[[build.plan]]
step = "copy"
from = "${SRC}/connector/" # Copy the connector source directory
to = "/app/connector/"
description = "Copy verisimdb connector V-lang source"

[[build.plan]]
step = "run"
command = "sh"
args = ["-c", "cd /app/connector && /usr/local/bin/v -prod -enable-globals -skip-unused main.v"] # Compile V-lang app
description = "Compile verisimdb connector application"

# --- Cleanup ---
[[build.plan]]
step = "run"
command = "apk"
args = ["del", "--no-cache", "build-base", "curl", "git", "unzip"]
description = "Remove build dependencies"

[[build.plan]]
step = "run"
command = "apk"
args = ["autoremove", "--no-cache"]
description = "Autoremove unused packages"

[[build.plan]]
step = "run"
command = "rm"
args = ["-rf", "/var/cache/apk/*", "/tmp/vlang", "/usr/local/bin/vlib"] # Remove V-lang build artifacts and cache
description = "Clean up build artifacts and APK cache"

[[build.plan]]
step = "emit_oci_image"
[build.plan.image]
entrypoint = ["/app/connector/main"] # The compiled V-lang binary
env = [
    "VERISIMDB_HOST=verisimdb", # Placeholder, will be linked via compose
    "VERISIMDB_PORT=8080",
    "MARIADB_HOST=mariadb",
    "MARIADB_PORT=3306",
    # Add other database credentials here
]

[outputs]
primary = "verisimdb-connector"

[attestations]
require = ["source-signature", "reproducible-build", "sbom-complete"]
recommend = ["security-audit"]
