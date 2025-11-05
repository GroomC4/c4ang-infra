#!/bin/bash
set -euo pipefail

DB_NAME=${POSTGRES_DB:-groom}
REPL_USER=${REPL_USER:-repl_user}
REPL_PASSWORD=${REPL_PASSWORD:-repl_password}

escape_literal() {
  printf "%s" "$1" | sed "s/'/''/g"
}

REPL_USER_LITERAL=$(escape_literal "$REPL_USER")
REPL_PASSWORD_LITERAL=$(escape_literal "$REPL_PASSWORD")

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$DB_NAME" <<-EOSQL
    DO \$\$
    DECLARE
        v_role text := '${REPL_USER_LITERAL}';
        v_password text := '${REPL_PASSWORD_LITERAL}';
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = v_role) THEN
            EXECUTE format('CREATE ROLE %I WITH REPLICATION LOGIN PASSWORD %L', v_role, v_password);
        END IF;
    END
    \$\$;
EOSQL

append_if_missing() {
  local file="$1"
  local pattern="$2"
  local block="$3"
  if ! grep -q "$pattern" "$file"; then
    printf '\n%s\n' "$block" >> "$file"
  fi
}

append_if_missing "$PGDATA/postgresql.conf" "wal_level = replica" "wal_level = replica"
append_if_missing "$PGDATA/postgresql.conf" "max_wal_senders = 10" "max_wal_senders = 10"
append_if_missing "$PGDATA/postgresql.conf" "max_replication_slots = 10" "max_replication_slots = 10"
append_if_missing "$PGDATA/postgresql.conf" "hot_standby = on" "hot_standby = on"
append_if_missing "$PGDATA/postgresql.conf" "wal_keep_size = '256MB'" "wal_keep_size = '256MB'"
append_if_missing "$PGDATA/postgresql.conf" "listen_addresses = '*'" "listen_addresses = '*'"

if ! grep -q "host replication ${REPL_USER}" "$PGDATA/pg_hba.conf"; then
    cat >> "$PGDATA/pg_hba.conf" <<EOF
host replication ${REPL_USER} 0.0.0.0/0 md5
EOF
fi
