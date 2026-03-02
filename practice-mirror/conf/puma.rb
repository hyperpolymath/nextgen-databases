# conf/puma.rb
# Puma configuration for Discourse

# Min and Max threads per worker
threads_count = Integer(ENV.fetch("RAILS_MAX_THREADS", 5))
threads threads_count, threads_count

# Preload the application
preload_app!

# Daemonize the app
daemonize false

# Bind to a Unix socket
bind "unix:///var/www/discourse/tmp/sockets/puma.sock"

# Set the environment
environment ENV.fetch("RAILS_ENV", "production")

# Number of workers
workers Integer(ENV.fetch("WEB_CONCURRENCY", 2))

# Logging
stdout_redirect "/var/www/discourse/log/puma_access.log", "/var/www/discourse/log/puma_error.log", true

# Set up current working directory for Puma
directory "/var/www/discourse"

on_worker_boot do
  # Worker specific setup for Rails
  ActiveRecord::Base.establish_connection if defined?(ActiveRecord)
end