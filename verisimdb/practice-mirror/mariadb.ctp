# Cerro Torre Package Manifest for MariaDB
# mariadb/11.8.5-r1

[metadata]
name = "mariadb"
version = "11.8.5-r1"
revision = 1
summary = "MariaDB 11.8.5-r1 with binary logging enabled for WordPress"
description = """
A MariaDB server image built on Alpine Linux,
configured for binary logging (binlog) to support Change Data Capture (CDC)
for integration with verisimdb.
"""
license = "GPL-2.0-or-later" # MariaDB license
homepage = "https://mariadb.org/"
maintainer = "cerro-torre:db-team"

[provenance]
upstream = "https://pkgs.alpinelinux.org/package/edge/main/x86_64/mariadb"
upstream_hash = "sha256:PLACEHOLDER" # Hash of the Alpine package, will be filled by cerro-torre
imported_from = "alpine:mariadb/11.8.5-r1"
import_date = 2026-01-27T00:00:00Z

[dependencies]
build = ["alpine-base"]
runtime = [
    "alpine-base",
    "mariadb",
    "mariadb-client",
    "mariadb-common" # Ensure common files are present
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
args = ["add", "--no-cache", "mariadb", "mariadb-client", "mariadb-common"]
description = "Install MariaDB server and client"

# Create mysql user and group (apk add should do this, but ensure)
[[build.plan]]
step = "run"
command = "addgroup"
args = ["-S", "mysql"]
description = "Add mysql group"
optional = true # May already exist

[[build.plan]]
step = "run"
command = "adduser"
args = ["-S", "mysql", "mysql"]
description = "Add mysql user"
optional = true # May already exist

# Create necessary directories and set permissions
[[build.plan]]
step = "run"
command = "mkdir"
args = ["-p", "/run/mysqld"]
description = "Create /run/mysqld directory"

[[build.plan]]
step = "run"
command = "chown"
args = ["mysql:mysql", "/run/mysqld"]
description = "Set ownership for /run/mysqld"

[[build.plan]]
step = "run"
command = "mkdir"
args = ["-p", "/var/lib/mysql"]
description = "Create /var/lib/mysql data directory"

[[build.plan]]
step = "run"
command = "chown"
args = ["mysql:mysql", "/var/lib/mysql"]
description = "Set ownership for /var/lib/mysql"

# Copy custom my.cnf
[[build.plan]]
step = "copy"
from = "${SRC}/conf/my.cnf"
to = "/etc/my.cnf"
description = "Copy MariaDB configuration with binlog enabled"

# Copy and make executable the startup script
[[build.plan]]
step = "copy"
from = "${SRC}/mariadb-start.sh"
to = "/usr/local/bin/mariadb-start.sh"
mode = "0755"
description = "Copy MariaDB startup script and make executable"

# Cleanup
[[build.plan]]
step = "run"
command = "rm"
args = ["-rf", "/var/cache/apk/*"]
description = "Clean up APK cache"

[[build.plan]]
step = "emit_oci_image"
[build.plan.image]
entrypoint = ["/usr/local/bin/mariadb-start.sh"]
expose_ports = ["3306"]

[outputs]
primary = "mariadb"

[attestations]
require = ["source-signature", "reproducible-build", "sbom-complete"]
recommend = ["security-audit"]
