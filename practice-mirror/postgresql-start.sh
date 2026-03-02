#!/bin/sh
# postgresql-start.sh
# Entrypoint script for PostgreSQL container

set -e

# Check if data directory is empty and initialize if needed
if [ ! -d "/var/lib/postgresql/data/postgresql.conf" ]; then
    echo "Initializing PostgreSQL data directory..."
    initdb --pgdata=/var/lib/postgresql/data --username=postgres --encoding=UTF8 --lc-collate=C --lc-ctype=C
    echo "PostgreSQL data directory initialized."

    # Start PostgreSQL temporarily for initial setup
    echo "Starting PostgreSQL temporarily for initial setup..."
    pg_ctl -D /var/lib/postgresql/data -o "-c listen_addresses=''" -w start
    PID=$!

    # Wait for PostgreSQL to start
    for i in $(seq 30); do
        if pg_isready -h localhost -p 5432 -U postgres &>/dev/null; then
            echo "PostgreSQL started."
            break
        fi
        echo "Waiting for PostgreSQL to start... ($i/30)"
        sleep 1
    done

    if ! pg_isready -h localhost -p 5432 -U postgres &>/dev/null; then
        echo "PostgreSQL did not start in time. Exiting."
        exit 1
    fi

    # Create Discourse user and database
    # NOTE: These should ideally be passed as environment variables in svalinn-compose.yaml
    # For now, using placeholders.
    echo "Creating Discourse database and user..."
    psql -v ON_ERROR_STOP=1 --username postgres <<-EOSQL
        CREATE USER discourse_user WITH PASSWORD '${POSTGRES_PASSWORD}';
        CREATE DATABASE discourse_db OWNER discourse_user;
        GRANT ALL PRIVILEGES ON DATABASE discourse_db TO discourse_user;
    EOSQL
    echo "PostgreSQL setup complete."

    # Shut down temporary PostgreSQL
    echo "Shutting down temporary PostgreSQL..."
    pg_ctl -D /var/lib/postgresql/data -m fast -w stop
    wait $PID
    echo "Temporary PostgreSQL stopped."
else
    echo "PostgreSQL data directory already exists. Skipping initialization."
fi

echo "Starting PostgreSQL server..."
exec postgres -D /var/lib/postgresql/data -c config_file=/etc/postgresql/postgresql.conf
