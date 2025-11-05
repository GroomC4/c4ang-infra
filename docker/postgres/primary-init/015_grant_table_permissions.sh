#!/bin/bash
set -euo pipefail

APP_DB_USER=${APP_DB_USER:-${POSTGRES_USER:-application}}
TARGET_DB=${APP_DB_DATABASE:-${POSTGRES_DB:-groom}}

escape_literal() {
  printf "%s" "$1" | sed "s/'/''/g"
}

APP_DB_USER_LITERAL=$(escape_literal "$APP_DB_USER")
TARGET_DB_LITERAL=$(escape_literal "$TARGET_DB")

echo "Granting table permissions to ${APP_DB_USER} on ${TARGET_DB}..."

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$TARGET_DB" <<-EOSQL
    DO \$\$
    DECLARE
        v_role text := '${APP_DB_USER_LITERAL}';
    BEGIN
        -- 기존 테이블/시퀀스/함수에 대한 권한 부여
        EXECUTE format('GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO %I', v_role);
        EXECUTE format('GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO %I', v_role);
        EXECUTE format('GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO %I', v_role);

        -- public 스키마 사용 권한
        EXECUTE format('GRANT USAGE, CREATE ON SCHEMA public TO %I', v_role);

        -- 미래에 생성될 테이블/시퀀스/함수에 대한 기본 권한 설정
        EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON TABLES TO %I', v_role);
        EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON SEQUENCES TO %I', v_role);
        EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON FUNCTIONS TO %I', v_role);

        RAISE NOTICE 'Successfully granted all permissions to role: %', v_role;
    END
    \$\$;
EOSQL

echo "Table permissions granted successfully to ${APP_DB_USER}."
