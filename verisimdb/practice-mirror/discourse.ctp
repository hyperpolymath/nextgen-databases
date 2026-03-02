# Cerro Torre Package Manifest for Discourse
# discourse/v2026.1.0

[metadata]
name = "discourse"
version = "v2026.1.0"
revision = 1
summary = "Discourse forum platform (latest stable) on Debian"
description = """
A Discourse forum instance built from source on Debian Bookworm Slim,
with Nginx as a reverse proxy and Puma application server.
"""
license = "GPL-2.0-only" # Discourse license
homepage = "https://www.discourse.org/"
maintainer = "cerro-torre:web-team"

[provenance]
upstream = "https://github.com/discourse/discourse"
upstream_hash = "sha1:b3efdbbdc5b1b508318bfec1a20ecd409511071b" # Commit hash for v2026.1.0 tag
imported_from = "discourse:v2026.1.0"
import_date = 2026-01-27T00:00:00Z # Today's date

[dependencies]
build = ["debian-bookworm-slim"]
runtime = [
    "debian-bookworm-slim",
    "nginx", # Nginx is installed via apt
    # Ruby and Node.js are managed via rbenv/nvm for specific versions
]

[build]
system = "custom"

[[build.plan]]
step = "run"
using = "debian-bookworm-slim"
command = "apt-get"
args = ["update", "--no-cache"]
description = "Update Debian package index"

# Install build tools and essential dependencies
[[build.plan]]
step = "run"
using = "debian-bookworm-slim"
command = "apt-get"
args = ["install", "-y", "git", "curl", "build-essential", "libpq-dev", # For PostgreSQL client
        "libssl-dev", "libreadline-dev", "zlib1g-dev", "libyaml-dev", "libffi-dev",
        "libgdbm-dev", "libncurses5-dev", "libxml2-dev", "libxslt1-dev",
        "libcurl4-openssl-dev", "libmagickwand-dev", # For image processing
        "nginx"] # Install Nginx from Debian repos
description = "Install build tools and core dependencies"

# --- Install rbenv and Ruby 3.3.x ---
[[build.plan]]
step = "run"
command = "git"
args = ["clone", "https://github.com/rbenv/rbenv.git", "/usr/local/rbenv"]
description = "Clone rbenv"

[[build.plan]]
step = "run"
command = "git"
args = ["clone", "https://github.com/rbenv/ruby-build.git", "/usr/local/rbenv/plugins/ruby-build"]
description = "Clone ruby-build"

[[build.plan]]
step = "run"
command = "sh"
args = ["-c", "echo 'export PATH=\"/usr/local/rbenv/bin:$PATH\"' >> /etc/profile.d/rbenv.sh"]
description = "Add rbenv to PATH"

[[build.plan]]
step = "run"
command = "sh"
args = ["-c", "echo 'eval \"$(rbenv init -)\" ' >> /etc/profile.d/rbenv.sh"]
description = "Initialize rbenv"

[[build.plan]]
step = "run"
command = "sh"
args = ["-c", ". /etc/profile.d/rbenv.sh && rbenv install 3.3.0 && rbenv global 3.3.0"]
description = "Install Ruby 3.3.0 and set as global"

# --- Install Node.js and Yarn ---
[[build.plan]]
step = "run"
command = "curl"
args = ["-fsSL", "https://deb.nodesource.com/setup_lts.x", "|", "bash", "-"]
description = "Add NodeSource LTS repository"

[[build.plan]]
step = "run"
command = "apt-get"
args = ["install", "-y", "nodejs"]
description = "Install Node.js"

[[build.plan]]
step = "run"
command = "npm"
args = ["install", "--global", "yarn"]
description = "Install Yarn globally"


# --- Clone Discourse ---
[[build.plan]]
step = "run"
command = "git"
args = ["clone", "https://github.com/discourse/discourse.git", "/var/www/discourse"]
description = "Clone Discourse repository"

[[build.plan]]
step = "run"
command = "sh"
args = ["-c", "cd /var/www/discourse && git checkout b3efdbbdc5b1b508318bfec1a20ecd409511071b"]
description = "Checkout specific Discourse commit"

[[build.plan]]
step = "run"
command = "chown"
args = ["-R", "www-data:www-data", "/var/www/discourse"]
description = "Set ownership for Discourse files"

# --- Discourse Setup ---
[[build.plan]]
step = "run"
command = "sh"
args = ["-c", "cd /var/www/discourse && . /etc/profile.d/rbenv.sh && bundle config set --local path vendor/bundle && bundle install --without development test --jobs $(nproc)"]
description = "Install Ruby gems for Discourse"

[[build.plan]]
step = "run"
command = "sh"
args = ["-c", "cd /var/www/discourse && . /etc/profile.d/rbenv.sh && RAILS_ENV=production bundle exec rake assets:precompile"]
description = "Precompile Discourse assets"

# --- Nginx Configuration ---
[[build.plan]]
step = "copy"
from = "${SRC}/conf/discourse_nginx.conf"
to = "/etc/nginx/sites-available/discourse.conf"
description = "Copy Nginx configuration for Discourse"

[[build.plan]]
step = "run"
command = "ln"
args = ["-sf", "/etc/nginx/sites-available/discourse.conf", "/etc/nginx/sites-enabled/default"]
description = "Enable Nginx Discourse configuration"

[[build.plan]]
step = "run"
command = "rm"
args = ["-f", "/etc/nginx/sites-enabled/default"] # Remove default nginx config
description = "Remove default Nginx site"

# --- Puma Configuration ---
[[build.plan]]
step = "copy"
from = "${SRC}/conf/puma.rb"
to = "/var/www/discourse/config/puma.rb"
description = "Copy Puma configuration"

# --- Startup Script ---
[[build.plan]]
step = "copy"
from = "${SRC}/discourse-start.sh"
to = "/usr/local/bin/discourse-start.sh"
mode = "0755"
description = "Copy Discourse startup script and make executable"

# --- Cleanup ---
[[build.plan]]
step = "run"
command = "apt-get"
args = ["remove", "-y", "git", "curl", "build-essential", "libpq-dev",
        "libssl-dev", "libreadline-dev", "zlib1g-dev", "libyaml-dev", "libffi-dev",
        "libgdbm-dev", "libncurses5-dev", "libxml2-dev", "libxslt1-dev",
        "libcurl4-openssl-dev", "libmagickwand-dev", "nodejs"] # Remove build dependencies
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
args = ["-rf", "/var/lib/apt/lists/*", "/usr/local/rbenv"] # Clean up rbenv build artifacts
description = "Clean up APT cache and rbenv installation"


[[build.plan]]
step = "emit_oci_image"
[build.plan.image]
entrypoint = ["/usr/local/bin/discourse-start.sh"]
expose_ports = ["80", "443"]

[outputs]
primary = "discourse"

[attestations]
require = ["source-signature", "reproducible-build", "sbom-complete"]
recommend = ["security-audit"]
