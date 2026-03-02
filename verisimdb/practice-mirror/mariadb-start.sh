#!/bin/sh
# mariadb-start.sh
# Entrypoint script for MariaDB container

set -e

# Check if data directory is empty and initialize if needed
if [ ! -d "/var/lib/mysql/mysql" ]; then
    echo "Initializing MariaDB data directory..."
    mysql_install_db --user=mysql --basedir=/usr --datadir=/var/lib/mysql
    echo "MariaDB data directory initialized."

    # Start MariaDB temporarily for initial setup
    echo "Starting MariaDB temporarily for initial setup..."
    /usr/bin/mysqld_safe --user=mysql --datadir=/var/lib/mysql &
    PID=$!

    # Wait for MariaDB to start
    for i in $(seq 30); do
        if mysql -uroot -e "SELECT 1" &>/dev/null; then
            echo "MariaDB started."
            break
        fi
        echo "Waiting for MariaDB to start... ($i/30)"
        sleep 1
    done

    if ! mysql -uroot -e "SELECT 1" &>/dev/null; then
        echo "MariaDB did not start in time. Exiting."
        exit 1
    fi

    # Set root password and create WordPress database/user
    # NOTE: These should ideally be passed as environment variables in svalinn-compose.yaml
    # For now, using placeholders.
    echo "Setting up MariaDB users and database..."
    mysql -uroot -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';"
    mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "CREATE DATABASE IF NOT EXISTS \"${WORDPRESS_DB_NAME}\" CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"
    mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "CREATE USER IF NOT EXISTS '${WORDPRESS_DB_USER}'@'%' IDENTIFIED BY '${WORDPRESS_DB_PASSWORD}';"
    mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "GRANT ALL PRIVILEGES ON \"${WORDPRESS_DB_NAME}\".* TO '${WORDPRESS_DB_USER}'@'%';"
    mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "FLUSH PRIVILEGES;"
    echo "MariaDB setup complete."

    # Shut down temporary MariaDB
    echo "Shutting down temporary MariaDB..."
    kill $PID
    wait $PID
    echo "Temporary MariaDB stopped."
else
    echo "MariaDB data directory already exists. Skipping initialization."
fi

echo "Starting MariaDB server..."
exec /usr/bin/mysqld_safe --user=mysql --datadir=/var/lib/mysql
