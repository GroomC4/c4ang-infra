#!/bin/bash
set -e

PRIMARY_HOST=${PRIMARY_HOST:-postgres-primary}
PRIMARY_PORT=${PRIMARY_PORT:-5432}
REPL_USER=${REPL_USER:-repl_user}
REPL_PASSWORD=${REPL_PASSWORD:-repl_password}
RAW_APPLICATION_NAME=${APPLICATION_NAME:-postgres_replica}
APPLICATION_NAME=$(echo "$RAW_APPLICATION_NAME" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9_' '_')
TARGET_DB=${POSTGRES_DB:-groom}
APP_DB_USER=${APP_DB_USER:-${POSTGRES_USER:-application}}

echo "Waiting for primary database at ${PRIMARY_HOST}:${PRIMARY_PORT}..."
export PGPASSWORD="$REPL_PASSWORD"
until pg_isready -h "$PRIMARY_HOST" -p "$PRIMARY_PORT" -d "$TARGET_DB" -U "$REPL_USER" >/dev/null 2>&1; do
  sleep 2
done

# Wait for primary to finish initialization and grant permissions
echo "Waiting for primary database to complete initialization (checking table permissions)..."
POSTGRES_PRIMARY_PASSWORD=${POSTGRES_PASSWORD:-application}
export PGPASSWORD="$POSTGRES_PRIMARY_PASSWORD"
MAX_RETRIES=30
RETRY_COUNT=0

until psql -h "$PRIMARY_HOST" -p "$PRIMARY_PORT" -U "$APP_DB_USER" -d "$TARGET_DB" -c "SELECT 1 FROM p_user LIMIT 1;" >/dev/null 2>&1; do
  RETRY_COUNT=$((RETRY_COUNT + 1))
  if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
    echo "ERROR: Primary database initialization timeout. Table permissions not granted after ${MAX_RETRIES} retries."
    exit 1
  fi
  echo "Primary database not ready yet (attempt ${RETRY_COUNT}/${MAX_RETRIES}). Waiting for table permissions..."
  sleep 3
done

echo "Primary database initialization complete. Permissions verified."

if [ -f "$PGDATA/standby.signal" ]; then
  echo "Replica data directory already initialized; skipping base backup."
  exit 0
fi

rm -rf "$PGDATA"/*

# Reset PGPASSWORD for replication user before pg_basebackup
export PGPASSWORD="$REPL_PASSWORD"

pg_basebackup -h "$PRIMARY_HOST" \
              -p "$PRIMARY_PORT" \
              -U "$REPL_USER" \
              -D "$PGDATA" \
              -Fp \
              -Xs \
              -C \
              -S "${APPLICATION_NAME}_slot" \
              --no-password
touch "$PGDATA/standby.signal"

cat >> "$PGDATA/postgresql.auto.conf" <<EOF
primary_conninfo = 'host=${PRIMARY_HOST} port=${PRIMARY_PORT} user=${REPL_USER} password=${REPL_PASSWORD} application_name=${APPLICATION_NAME}'
primary_slot_name = '${APPLICATION_NAME}_slot'
EOF
chmod 600 "$PGDATA/standby.signal"
touch "$PGDATA/.replica_initialized"
