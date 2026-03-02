#!/bin/sh

# ols-start.sh
# Entrypoint script for WordPress with OpenLiteSpeed and Varnish

# --- Start Varnish ---
echo "Starting Varnish Cache..."
/usr/bin/varnishd -a :80 -b 127.0.0.1:8080 -f /etc/varnish/default.vcl -s malloc,256m &
VARNISH_PID=$!
echo "Varnish PID: $VARNISH_PID"

# --- Start PHP-FPM ---
echo "Starting PHP-FPM 8.4..."
/usr/sbin/php-fpm84 --nodaemonize &
PHP_FPM_PID=$!
echo "PHP-FPM PID: $PHP_FPM_PID"

# --- Start OpenLiteSpeed ---
echo "Starting OpenLiteSpeed..."
/usr/local/lsws/bin/lsws &
LSWS_PID=$!
echo "OpenLiteSpeed PID: $LSWS_PID"

# --- Wait for processes to exit ---
wait $VARNISH_PID $PHP_FPM_PID $LSWS_PID

echo "All services stopped."
exit 0
