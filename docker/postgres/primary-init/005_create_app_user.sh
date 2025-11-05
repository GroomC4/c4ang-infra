#!/bin/bash
set -euo pipefail

APP_DB_USER=${APP_DB_USER:-${POSTGRES_USER:-application}}
APP_DB_PASSWORD=${APP_DB_PASSWORD:-${POSTGRES_PASSWORD:-application}}
TARGET_DB=${APP_DB_DATABASE:-${POSTGRES_DB:-groom}}

escape_literal() {
  printf "%s" "$1" | sed "s/'/''/g"
}

APP_DB_USER_LITERAL=$(escape_literal "$APP_DB_USER")
APP_DB_PASSWORD_LITERAL=$(escape_literal "$APP_DB_PASSWORD")
TARGET_DB_LITERAL=$(escape_literal "$TARGET_DB")

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$TARGET_DB" <<-EOSQL
    DO \$\$
    DECLARE
        v_role text := '${APP_DB_USER_LITERAL}';
        v_password text := '${APP_DB_PASSWORD_LITERAL}';
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = v_role) THEN
            EXECUTE format('CREATE ROLE %I WITH LOGIN PASSWORD %L', v_role, v_password);
        ELSE
            EXECUTE format('ALTER ROLE %I WITH LOGIN PASSWORD %L', v_role, v_password);
        END IF;
        EXECUTE format('ALTER ROLE %I WITH CREATEDB', v_role);
    END
    \$\$;
EOSQL

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$TARGET_DB" <<-EOSQL
    DO \$\$
    DECLARE
        v_role text := '${APP_DB_USER_LITERAL}';
        v_db text := '${TARGET_DB_LITERAL}';
    BEGIN
        EXECUTE format('GRANT ALL PRIVILEGES ON DATABASE %I TO %I', v_db, v_role);
        EXECUTE format('ALTER DATABASE %I OWNER TO %I', v_db, v_role);
    END
    \$\$;
EOSQL
