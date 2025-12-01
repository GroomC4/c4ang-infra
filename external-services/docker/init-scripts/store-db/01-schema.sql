-- Marketplace platform DDL generated from database_design_requirent.md requirements
-- PostgreSQL dialect

CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- Store domain
CREATE TABLE IF NOT EXISTS p_store (
    id                UUID PRIMARY KEY,
    owner_user_id     UUID NOT NULL,
    name              TEXT NOT NULL,
    description       TEXT,
    status            TEXT NOT NULL DEFAULT 'REGISTERED' CHECK (status IN ('REGISTERED', 'SUSPENDED', 'DELETED')),
    hidden_at         TIMESTAMPTZ,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at        TIMESTAMPTZ,
    UNIQUE (owner_user_id),
    CHECK (hidden_at IS NULL OR hidden_at >= created_at)
);

COMMENT ON TABLE p_store IS '판매자가 운영하는 스토어 기본 정보를 담는 테이블.';
COMMENT ON COLUMN p_store.id IS '스토어의 UUID 기본 키.';
COMMENT ON COLUMN p_store.owner_user_id IS '스토어를 소유한 판매자 사용자 UUID.';
COMMENT ON COLUMN p_store.name IS '스토어 표시 이름.';
COMMENT ON COLUMN p_store.description IS '스토어 소개 및 설명.';
COMMENT ON COLUMN p_store.status IS 'REGISTERED, SUSPENDED 등 스토어 상태 값.';
COMMENT ON COLUMN p_store.hidden_at IS '스토어가 노출 중단된 시각.';
COMMENT ON COLUMN p_store.created_at IS '스토어 생성 시각.';
COMMENT ON COLUMN p_store.updated_at IS '스토어 최종 수정 시각.';
COMMENT ON COLUMN p_store.deleted_at IS '소프트 삭제 시각.';

CREATE TABLE IF NOT EXISTS p_store_rating (
    id                UUID PRIMARY KEY,
    store_id          UUID NOT NULL,
    average_rating    NUMERIC(3, 2) NOT NULL DEFAULT 0,
    review_count      INTEGER NOT NULL DEFAULT 0,
    launched_at       TIMESTAMPTZ NOT NULL,
    hidden_at         TIMESTAMPTZ,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at        TIMESTAMPTZ,
    UNIQUE (store_id),
    CHECK (average_rating BETWEEN 0 AND 5),
    CHECK (review_count >= 0)
);

COMMENT ON TABLE p_store_rating IS '스토어의 평점과 리뷰 집계 데이터를 저장하는 테이블.';
COMMENT ON COLUMN p_store_rating.id IS '스토어 평점 레코드의 UUID 기본 키.';
COMMENT ON COLUMN p_store_rating.store_id IS '평점이 속한 스토어 ID.';
COMMENT ON COLUMN p_store_rating.average_rating IS '5점 만점 기준 평균 평점.';
COMMENT ON COLUMN p_store_rating.review_count IS '평균에 반영된 노출 리뷰 수.';
COMMENT ON COLUMN p_store_rating.launched_at IS '스토어 오픈(런칭) 시각.';
COMMENT ON COLUMN p_store_rating.hidden_at IS '평점 노출이 중단된 시각.';
COMMENT ON COLUMN p_store_rating.created_at IS '평점 레코드 생성 시각.';
COMMENT ON COLUMN p_store_rating.updated_at IS '평점 레코드 최종 수정 시각.';
COMMENT ON COLUMN p_store_rating.deleted_at IS '소프트 삭제 시각.';

CREATE TABLE IF NOT EXISTS p_store_audit (
    id                UUID PRIMARY KEY,
    store_id          UUID NOT NULL,
    event_type        TEXT NOT NULL CHECK (event_type IN ('REGISTERED', 'INFO_UPDATED', 'SUSPENDED', 'DELETED')),
    status_snapshot   TEXT CHECK (status_snapshot IN ('REGISTERED', 'SUSPENDED', 'DELETED')),
    change_summary    TEXT,
    actor_user_id     UUID,
    recorded_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    metadata          JSONB
);

COMMENT ON TABLE p_store_audit IS '스토어 등록/정지/삭제 등 상태 변화를 기록하는 감사 로그.';
COMMENT ON COLUMN p_store_audit.id IS '스토어 감사 레코드의 UUID 기본 키.';
COMMENT ON COLUMN p_store_audit.store_id IS '이벤트가 발생한 스토어 ID.';
COMMENT ON COLUMN p_store_audit.event_type IS 'REGISTERED, SUSPENDED 등 이벤트 유형.';
COMMENT ON COLUMN p_store_audit.status_snapshot IS '이벤트 시점의 스토어 상태 스냅샷.';
COMMENT ON COLUMN p_store_audit.change_summary IS '변경 사항 요약 설명.';
COMMENT ON COLUMN p_store_audit.actor_user_id IS '변경을 수행한 사용자 UUID(있는 경우).';
COMMENT ON COLUMN p_store_audit.recorded_at IS '감사 이벤트 기록 시각.';
COMMENT ON COLUMN p_store_audit.metadata IS '추가 메타 정보를 담은 JSON.';

CREATE INDEX IF NOT EXISTS idx_p_store_owner ON p_store (owner_user_id);
CREATE INDEX IF NOT EXISTS idx_p_store_hidden ON p_store (hidden_at);
