# frozen_string_literal: true

max_threads_count = ENV.fetch("RAILS_MAX_THREADS") { 5 }
min_threads_count = ENV.fetch("RAILS_MIN_THREADS") { max_threads_count }
threads min_threads_count, max_threads_count

# Binds all interfaces so the showcase is reachable from another machine, not
# just this one. Development-only app with no data behind it; set BIND=127.0.0.1
# to restrict it to loopback.
port ENV.fetch("PORT") { 3561 }, ENV.fetch("BIND") { "0.0.0.0" }

environment ENV.fetch("RAILS_ENV") { "development" }

pidfile ENV.fetch("PIDFILE") { "tmp/pids/server.pid" }

workers ENV.fetch("WEB_CONCURRENCY") { 0 }

plugin :tmp_restart
