# Cerro Torre Package Manifest for WordPress with OpenLiteSpeed and Varnish
# wordpress-litespeed-varnish/6.8.3-1

[metadata]
name = "wordpress-litespeed-varnish"
version = "6.8.3"
revision = 1
summary = "WordPress 6.8.3 with OpenLiteSpeed 1.8.5 and Varnish Cache 7.5"
description = """
A hardened WordPress installation running on Alpine Linux,
served by OpenLiteSpeed and fronted by Varnish Cache,
built using cerro-torre for verifiable provenance.
"""
license = "GPL-2.0-or-later" # WordPress license
homepage = "https://wordpress.org/"
maintainer = "cerro-torre:web-team"

[provenance]
upstream = "https://wordpress.org/wordpress-6.8.3.zip"
upstream_hash = "sha256:a163fe8d0d3d89ce00139ca0e0618e109bb7441fae2f733cff6c72fc4d170fb9"
imported_from = "wordpress:6.8.3"
import_date = 2026-01-27T00:00:00Z

[[inputs.sources]]
id = "ols"
type = "tarball"
name = "openlitespeed"
version = "1.8.5"

[[inputs.sources.artifacts]]
filename = "openlitespeed-1.8.5.tar.gz"
uri = "https://github.com/litespeedtech/openlitespeed/archive/v1.8.5.tar.gz"
sha512 = "e7d6c1d50513c9fb2afd9f49207622ca235f42d059db6ad5c0e15a7aee94d17aea64f41eb4a250e3475dede0f488074df242bded9f3487587578a9920c8c5f51"

[[inputs.sources]]
id = "varnish"
type = "tarball"
name = "varnish-cache"
version = "7.5.0"

[[inputs.sources.artifacts]]
filename = "varnish-7.5.0.tgz"
uri = "https://varnish-cache.org/_downloads/varnish-7.5.0.tgz"
sha256 = "fca61b983139e1aac61c4546d12a1a3ab9807dbb1d8314571e3148c93ff72b5d"

[[inputs.sources]]
id = "wordpress"
type = "zip"
name = "wordpress"
version = "6.8.3"

[[inputs.sources.artifacts]]
filename = "wordpress-6.8.3.zip"
uri = "https://wordpress.org/wordpress-6.8.3.zip"
sha256 = "a163fe8d0d3d89ce00139ca0e0618e109bb7441fae2f733cff6c72fc4d170fb9"


[dependencies]
# Base image for the build
build = ["alpine-base"]
# Runtime dependencies (Alpine packages)
runtime = [
    "alpine-base", # This ensures the base OS is present.
    "php84",
    "php84-fpm",
    "php84-mysqli",
    "php84-opcache",
    "php84-session",
    "php84-gd",
    "php84-json",
    "php84-mbstring",
    "php84-xml",
    "php84-curl",
    "php84-dom",
    "php84-zip",
    "php84-zlib",
    "libressl-dev", # For OpenLiteSpeed build
    "pcre-dev",     # For OpenLiteSpeed build
    "zlib-dev",     # For OpenLiteSpeed build
    "cmake",        # For OpenLiteSpeed build
    "gcc",          # For OpenLiteSpeed build
    "make",         # For OpenLiteSpeed build
    "g++",          # For OpenLiteSpeed build
    "unzip",        # To extract WordPress
    "tar",          # To extract OLS and Varnish
    "autoconf",     # For Varnish build
    "automake",     # For Varnish build
    "libtool",      # For Varnish build
    "ncurses-dev",  # For Varnish build
    "json-c-dev",   # For Varnish build
    "pcre2-dev",    # For Varnish build
    "jemalloc-dev", # For Varnish build
    "util-linux"    # For Varnish build (uuidgen)
]

[build]
system = "custom" # Complex custom build process

[[build.plan]]
step = "run"
using = "alpine-base" # Use the base Alpine image
command = "apk"
args = ["update", "--no-cache"]

[[build.plan]]
step = "run"
using = "alpine-base"
command = "apk"
args = ["add", "--no-cache",
        "php84", "php84-fpm", "php84-mysqli", "php84-opcache", "php84-session",
        "php84-gd", "php84-json", "php84-mbstring", "php84-xml", "php84-curl",
        "php84-dom", "php84-zip", "php84-zlib",
        "libressl-dev", "pcre-dev", "zlib-dev", "cmake", "gcc", "make", "g++",
        "unzip", "tar", "autoconf", "automake", "libtool", "ncurses-dev",
        "json-c-dev", "pcre2-dev", "jemalloc-dev", "util-linux"]
description = "Install build tools and PHP dependencies"

# --- OpenLiteSpeed Build ---
[[build.plan]]
step = "run"
source = "ols"
command = "tar"
args = ["xzf", "${SRC}/openlitespeed-1.8.5.tar.gz", "-C", "/tmp"]
description = "Extract OpenLiteSpeed source"

[[build.plan]]
step = "run"
command = "sh"
args = ["-c", "cd /tmp/openlitespeed-1.8.5 && ./configure --with-litespeed-user=litespeed --with-litespeed-group=litespeed --prefix=/usr/local/lsws --enable-console --enable-selective-binding --enable-php-fpm --with-php-suid-daemon --with-openssl=/usr --enable-quic --enable-http3"]
description = "Configure OpenLiteSpeed"

[[build.plan]]
step = "run"
command = "sh"
args = ["-c", "cd /tmp/openlitespeed-1.8.5 && make -j$(nproc)"]
description = "Build OpenLiteSpeed"

[[build.plan]]
step = "run"
command = "sh"
args = ["-c", "cd /tmp/openlitespeed-1.8.5 && make install && rm -rf /tmp/openlitespeed-1.8.5"]
description = "Install OpenLiteSpeed and clean up source"

[[build.plan]]
step = "run"
command = "mkdir"
args = ["-p", "/usr/local/lsws/conf/vhosts/wordpress/"]
description = "Create OLS WordPress vhost directory"

[[build.plan]]
step = "copy"
from = "${SRC}/conf/ols_vhost.conf"
to = "/usr/local/lsws/conf/vhosts/wordpress/vhconf.conf"
description = "Copy OLS vhost configuration"

[[build.plan]]
step = "copy"
from = "${SRC}/conf/ols_php.conf"
to = "/usr/local/lsws/conf/php.conf"
description = "Copy OLS PHP configuration"

# --- Varnish Build ---
[[build.plan]]
step = "run"
source = "varnish"
command = "tar"
args = ["xzf", "${SRC}/varnish-7.5.0.tgz", "-C", "/tmp"]
description = "Extract Varnish source"

[[build.plan]]
step = "run"
command = "sh"
args = ["-c", "cd /tmp/varnish-7.5.0 && ./configure --prefix=/usr --enable-developer-warnings --enable-debugging-symbols"]
description = "Configure Varnish"

[[build.plan]]
step = "run"
command = "sh"
args = ["-c", "cd /tmp/varnish-7.5.0 && make -j$(nproc)"]
description = "Build Varnish"

[[build.plan]]
step = "run"
command = "sh"
args = ["-c", "cd /tmp/varnish-7.5.0 && make install && rm -rf /tmp/varnish-7.5.0"]
description = "Install Varnish and clean up source"

[[build.plan]]
step = "copy"
from = "${SRC}/conf/default.vcl"
to = "/etc/varnish/default.vcl"
description = "Copy Varnish VCL configuration"

# --- WordPress Installation ---
[[build.plan]]
step = "run"
source = "wordpress"
command = "unzip"
args = ["-q", "${SRC}/wordpress-6.8.3.zip", "-d", "/tmp"]
description = "Extract WordPress archive"

[[build.plan]]
step = "run"
command = "mv"
args = ["/tmp/wordpress", "/usr/local/lsws/html/wordpress"]
description = "Move WordPress to OpenLiteSpeed webroot"

[[build.plan]]
step = "run"
command = "chown"
args = ["-R", "litespeed:litespeed", "/usr/local/lsws/html/wordpress"]
description = "Set ownership for WordPress files"

[[build.plan]]
step = "run"
command = "chmod"
args = ["-R", "u+rwX,go+rX,go-w", "/usr/local/lsws/html/wordpress"]
description = "Set permissions for WordPress files"

# --- Final Cleanup and Configuration ---
[[build.plan]]
step = "run"
command = "rm"
args = ["-rf", "/tmp/*", "/var/cache/apk/*"]
description = "Clean up build artifacts and APK cache"

# Create necessary directories and set permissions for PHP-FPM and OLS
[[build.plan]]
step = "run"
command = "sh"
args = ["-c", "mkdir -p /run/php && chown litespeed:litespeed /run/php"]
description = "Create PHP-FPM socket directory"

[[build.plan]]
step = "run"
command = "sh"
args = ["-c", "mkdir -p /var/log/lsws && chown litespeed:litespeed /var/log/lsws"]
description = "Create OLS log directory"

[[build.plan]]
step = "run"
command = "sh"
args = ["-c", "mkdir -p /var/log/varnish && chown varnish:varnish /var/log/varnish"]
description = "Create Varnish log directory"

[[build.plan]]
step = "copy"
from = "${SRC}/ols-start.sh"
to = "/usr/local/bin/ols-start.sh"
mode = "0755"
description = "Copy OLS startup script and make executable"

[[build.plan]]
step = "emit_oci_image"
# Entrypoint and command to start OpenLiteSpeed and Varnish
[build.plan.image]
entrypoint = ["/usr/local/bin/ols-start.sh"] # Use the custom startup script
expose_ports = ["80", "443", "6081"] # OLS HTTP/HTTPS, Varnish admin

[outputs]
primary = "wordpress-litespeed-varnish"

[attestations]
require = ["source-signature", "reproducible-build", "sbom-complete"]
recommend = ["security-audit"]
