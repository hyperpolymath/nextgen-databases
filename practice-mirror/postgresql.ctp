# Cerro Torre Package Manifest for PostgreSQL
# postgresql/16

[metadata]
name = "postgresql"
version = "16"
revision = 1
summary = "PostgreSQL 16 on Debian Bookworm Slim for Discourse"
description = """
A PostgreSQL server image built on Debian Bookworm Slim,
configured for Discourse with an external APT repository for the latest stable version.
"""
license = "PostgreSQL" # PostgreSQL license
homepage = "https://www.postgresql.org/"
maintainer = "cerro-torre:db-team"

[provenance]
upstream = "https://www.postgresql.org/download/linux/debian/"
upstream_hash = "sha256:PLACEHOLDER_POSTGRESQL_APT_KEY_HASH" # Hash of the GPG key
imported_from = "debian:postgresql/16"
import_date = 2026-01-27T00:00:00Z # Today's date

[dependencies]
build = ["debian-bookworm-slim"]
runtime = [
    "debian-bookworm-slim",
    "postgresql-16",
    "postgresql-client-16"
]

[build]
system = "custom"

[[build.plan]]
step = "run"
using = "debian-bookworm-slim"
command = "apt-get"
args = ["update", "--no-cache"]
description = "Update Debian package index"

# Install tools for adding PGDG repository
[[build.plan]]
step = "run"
using = "debian-bookworm-slim"
command = "apt-get"
args = ["install", "-y", "wget", "ca-certificates", "gnupg"]
description = "Install wget, ca-certificates, gnupg"

# Add PostgreSQL PGDG APT Repository
[[build.plan]]
step = "run"
command = "sh"
args = ["-c", "wget -qO - https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg"]
description = "Add PostgreSQL GPG key"

[[build.plan]]
step = "run"
command = "sh"
args = ["-c", "echo \"deb http://apt.postgresql.org/pub/repos/apt/ bookworm-pgdg main\" > /etc/apt/sources.list.d/pgdg.list"]
description = "Add PostgreSQL APT repository"

[[build.plan]]
step = "run"
command = "apt-get"
args = ["update"]
description = "Update apt cache after adding new repo"

# Install PostgreSQL 16
[[build.plan]]
step = "run"
command = "apt-get"
args = ["install", "-y", "postgresql-16", "postgresql-client-16"]
description = "Install PostgreSQL 16 server and client"

# Create PostgreSQL user and group (apt install should do this, but ensure)
[[build.plan]]
step = "run"
command = "sh"
args = ["-c", "if ! id -u postgres >/dev/null 2>&1; then adduser --system --no-create-home --shell /bin/false --group postgres; fi"]
description = "Ensure postgres user exists"

# Create necessary directories and set permissions
[[build.plan]]
step = "run"
command = "mkdir"
args = ["-p", "/var/lib/postgresql/data"]
description = "Create /var/lib/postgresql/data directory"

[[build.plan]]
step = "run"
command = "chown"
args = ["-R", "postgres:postgres", "/var/lib/postgresql/data"]
description = "Set ownership for /var/lib/postgresql/data"

[[build.plan]]
step = "run"
command = "mkdir"
args = ["-p", "/var/log/postgresql"]
description = "Create /var/log/postgresql directory"

[[build.plan]]
step = "run"
command = "chown"
args = ["-R", "postgres:postgres", "/var/log/postgresql"]
description = "Set ownership for /var/log/postgresql"


# Copy custom configuration files
[[build.plan]]
step = "copy"
from = "${SRC}/conf/postgresql.conf"
to = "/etc/postgresql/postgresql.conf"
description = "Copy PostgreSQL configuration"

[[build.plan]]
step = "copy"
from = "${SRC}/conf/pg_hba.conf"
to = "/etc/postgresql/pg_hba.conf"
description = "Copy pg_hba.conf for host-based authentication"

# Copy and make executable the startup script
[[build.plan]]
step = "copy"
from = "${SRC}/postgresql-start.sh"
to = "/usr/local/bin/postgresql-start.sh"
mode = "0755"
description = "Copy PostgreSQL startup script and make executable"

# Cleanup
[[build.plan]]
step = "run"
command = "apt-get"
args = ["remove", "-y", "wget", "gnupg"]
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
args = ["-rf", "/var/lib/apt/lists/*"]
description = "Clean up APT cache"

[[build.plan]]
step = "emit_oci_image"
[build.plan.image]
entrypoint = ["/usr/local/bin/postgresql-start.sh"]
expose_ports = ["5432"]
user = "postgres" # Run as postgres user

[outputs]
primary = "postgresql"

[attestations]
require = ["source-signature", "reproducible-build", "sbom-complete"]
recommend = ["security-audit"]

