#!/usr/bin/env bash
# Generate the Guacamole PostgreSQL schema and load it into the system Postgres.
# Run once during setup. Requires: docker, psql, and a .env with POSTGRES_PASSWORD.
set -euo pipefail
cd "$(dirname "$0")/.."

# shellcheck disable=SC1091
set -a; [ -f .env ] && . ./.env; set +a
: "${POSTGRES_PASSWORD:?set POSTGRES_PASSWORD in .env}"

PGHOST="${PGHOST:-localhost}"
PGPORT="${PGPORT:-5432}"
DB="${POSTGRES_DB:-guacamole_db}"
USER="${POSTGRES_USER:-guacamole_user}"

echo "==> Generating schema -> sql/initdb.sql"
mkdir -p sql
docker run --rm guacamole/guacamole:1.6.0 \
  /opt/guacamole/bin/initdb.sh --postgresql > sql/initdb.sql

echo "==> Loading schema into ${DB} on ${PGHOST}:${PGPORT}"
PGPASSWORD="${POSTGRES_PASSWORD}" \
  psql "postgresql://${USER}@${PGHOST}:${PGPORT}/${DB}" -f sql/initdb.sql

echo "==> Done. Schema loaded."
