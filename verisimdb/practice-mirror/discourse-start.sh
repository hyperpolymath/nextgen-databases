#!/bin/sh
# discourse-start.sh
# Entrypoint script for Discourse container

set -e

# --- Configuration ---
DISCOURSE_ROOT="/var/www/discourse"
DISCOURSE_SOCKET="/var/www/discourse/tmp/sockets/puma.sock"

# --- Start PostgreSQL ---
# Discourse needs PostgreSQL to be ready. This script does not wait for it.
# svalinn-compose will handle service dependencies, but if issues, need to add wait logic.

# --- Prepare Discourse (if needed on first run or on volume changes) ---
if [ ! -f "${DISCOURSE_ROOT}/db/schema.rb" ]; then
    echo "Performing Discourse database setup..."
    cd "${DISCOURSE_ROOT}"

    # Install Rbenv and Ruby (if not already in base image, handled by cerro-torre)
    # Ensure bundle is installed
    bundle install --without development test --jobs $(nproc) --deployment

    # Migrate database
    RAILS_ENV=production bundle exec rake db:migrate

    # Precompile assets
    RAILS_ENV=production bundle exec rake assets:precompile

    echo "Discourse database and assets setup complete."
fi

# --- Start Nginx ---
echo "Starting Nginx..."
nginx -g "daemon off;" &
NGINX_PID=$!
echo "Nginx PID: $NGINX_PID"

# --- Start Discourse Puma Server ---
echo "Starting Discourse Puma server..."
cd "${DISCOURSE_ROOT}"
# Ensure the tmp/sockets directory exists for puma.sock
mkdir -p "${DISCOURSE_ROOT}/tmp/sockets"
exec bundle exec puma -C "${DISCOURSE_ROOT}/config/puma.rb" &
PUMA_PID=$!
echo "Puma PID: $PUMA_PID"

# --- Keep container alive ---
# Use wait to keep the script running until Nginx or Puma exits
wait $NGINX_PID $PUMA_PID

echo "Discourse services stopped."
exit 0
