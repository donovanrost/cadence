#!/usr/bin/env bash
# CI test databases are throwaway: trade durability for speed on the Postgres service container.
# Service containers can't take `command:` args, so set these through ALTER SYSTEM + reload.
set -euo pipefail

export PGPASSWORD=${PGPASSWORD:-postgres}
psql_args=(-h "${PGHOST:-localhost}" -U "${PGUSER:-postgres}" -v ON_ERROR_STOP=1 -q)

psql "${psql_args[@]}" \
  -c "ALTER SYSTEM SET fsync = off" \
  -c "ALTER SYSTEM SET synchronous_commit = off" \
  -c "ALTER SYSTEM SET full_page_writes = off" \
  -c "SELECT pg_reload_conf()" > /dev/null

psql "${psql_args[@]}" -At -c "SELECT name || '=' || setting FROM pg_settings WHERE name IN ('fsync', 'synchronous_commit', 'full_page_writes', 'max_connections') ORDER BY name"
