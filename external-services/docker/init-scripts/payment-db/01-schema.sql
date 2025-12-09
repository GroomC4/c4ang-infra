-- PostgreSQL dialect

CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- Core user tables
CREATE TABLE IF NOT EXISTS p_user (
    id                UUID PRIMARY KEY,
    username          VARCHAR(10) NOT NULL,
    email             TEXT NOT NULL,
    password_hash     TEXT NOT NULL,
    role              TEXT NOT NULL CHECK (role IN ('CUSTOMER', 'OWNER', 'MANAGER', 'MASTER')),
    is_active         BOOLEAN NOT NULL DEFAULT TRUE,
    last_login_at     TIMESTAMPTZ,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at        TIMESTAMPTZ,
    UNIQUE (email, role),
    CHECK (char_length(username) BETWEEN 2 AND 10)
);

COMMENT ON TABLE p_user IS '인증, 권한, 라이프사이클을 관리하는 사용자 계정 테이블.';
COMMENT ON COLUMN p_user.id IS 'UUID 기본 키.';
COMMENT ON COLUMN p_user.username IS '4~10자 영문 소문자와 숫자로 구성된 로그인 아이디.';
COMMENT ON COLUMN p_user.email IS '알림과 로그인에 사용하는 고유 이메일 주소.';
COMMENT ON COLUMN p_user.password_hash IS 'BCrypt로 암호화된 비밀번호 해시.';
COMMENT ON COLUMN p_user.role IS 'CUSTOMER/OWNER/MANAGER/MASTER 등 사용자 권한 역할.';
COMMENT ON COLUMN p_user.is_active IS '계정 삭제 없이 로그인을 비활성화할 때 사용하는 플래그.';
COMMENT ON COLUMN p_user.last_login_at IS '마지막 로그인 성공 시각.';
COMMENT ON COLUMN p_user.created_at IS '사용자 레코드 생성 시각.';
COMMENT ON COLUMN p_user.updated_at IS '사용자 레코드 마지막 수정 시각.';
COMMENT ON COLUMN p_user.deleted_at IS '소프트 삭제 시각(NULL이면 사용 중).';

CREATE TABLE IF NOT EXISTS p_user_refresh_token (
    id              UUID PRIMARY KEY,
    user_id         UUID NOT NULL,
    token           TEXT NULL,
    client_ip       TEXT,
    expires_at      TIMESTAMPTZ NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- 단일 디바이스 로그인 제약 (향후 제거 가능)
    UNIQUE (user_id)
);

CREATE INDEX idx_refresh_token_user_id ON p_user_refresh_token(user_id);
CREATE INDEX idx_refresh_token_token ON p_user_refresh_token(token);
CREATE INDEX idx_refresh_token_expires_at ON p_user_refresh_token(expires_at);

COMMENT ON TABLE p_user_refresh_token IS 'JWT Refresh Token 저장 테이블. 단일/멀티 디바이스 로그인 관리.';
COMMENT ON COLUMN p_user_refresh_token.id IS 'UUID 기본 키.';
COMMENT ON COLUMN p_user_refresh_token.user_id IS 'p_user.id를 논리적으로 참조하는 사용자 ID.';
COMMENT ON COLUMN p_user_refresh_token.token IS 'JWT Refresh Token 문자열.';
COMMENT ON COLUMN p_user_refresh_token.client_ip IS '토큰 발급 시 클라이언트 IP 주소.';
COMMENT ON COLUMN p_user_refresh_token.expires_at IS 'Refresh Token 만료 시각.';
COMMENT ON COLUMN p_user_refresh_token.created_at IS '토큰 최초 생성 시각.';
COMMENT ON COLUMN p_user_refresh_token.updated_at IS '토큰 갱신 시각 (로그인 시 덮어쓰기).';

CREATE TABLE IF NOT EXISTS p_user_profile (
    id                UUID PRIMARY KEY,
    user_id           UUID NOT NULL,
    full_name         TEXT NOT NULL,
    phone_number      TEXT NOT NULL,
    contact_email     TEXT,
    default_address   TEXT,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at        TIMESTAMPTZ,
    UNIQUE (user_id)
);

COMMENT ON TABLE p_user_profile IS 'p_user와 1:1로 매핑되는 확장 프로필 정보 테이블.';
COMMENT ON COLUMN p_user_profile.id IS '프로필 레코드의 UUID 기본 키.';
COMMENT ON COLUMN p_user_profile.user_id IS 'FK 없이 논리적으로 연결하는 사용자 식별자.';
COMMENT ON COLUMN p_user_profile.full_name IS '주문 및 커뮤니케이션에 노출되는 실명.';
COMMENT ON COLUMN p_user_profile.phone_number IS '대표 연락처 전화번호.';
COMMENT ON COLUMN p_user_profile.contact_email IS '선택 입력 가능한 보조 이메일.';
COMMENT ON COLUMN p_user_profile.default_address IS '기본 배송지 스냅샷 문자열.';
COMMENT ON COLUMN p_user_profile.created_at IS '프로필 생성 시각.';
COMMENT ON COLUMN p_user_profile.updated_at IS '프로필 최종 수정 시각.';
COMMENT ON COLUMN p_user_profile.deleted_at IS '소프트 삭제 시각.';

CREATE TABLE IF NOT EXISTS p_user_address (
    id                UUID PRIMARY KEY,
    user_id           UUID NOT NULL,
    label             TEXT NOT NULL,
    recipient_name    TEXT NOT NULL,
    phone_number      TEXT NOT NULL,
    postal_code       TEXT NOT NULL,
    address_line1     TEXT NOT NULL,
    address_line2     TEXT,
    is_default        BOOLEAN NOT NULL DEFAULT FALSE,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at        TIMESTAMPTZ,
    UNIQUE (user_id, label)
);

COMMENT ON TABLE p_user_address IS '사용자별 배송/결제 주소 목록을 관리하는 테이블.';
COMMENT ON COLUMN p_user_address.id IS '주소 레코드의 UUID 기본 키.';
COMMENT ON COLUMN p_user_address.user_id IS '주소를 소유한 사용자 식별자.';
COMMENT ON COLUMN p_user_address.label IS '사용자가 부여한 주소 별칭(예: 집, 회사).';
COMMENT ON COLUMN p_user_address.recipient_name IS '배송 수취인 이름.';
COMMENT ON COLUMN p_user_address.phone_number IS '수취인 연락처 전화번호.';
COMMENT ON COLUMN p_user_address.postal_code IS '주소의 우편번호.';
COMMENT ON COLUMN p_user_address.address_line1 IS '기본 도로명 또는 지번 주소.';
COMMENT ON COLUMN p_user_address.address_line2 IS '동/호 등 추가 상세 주소.';
COMMENT ON COLUMN p_user_address.is_default IS '기본 배송지 여부 플래그.';
COMMENT ON COLUMN p_user_address.created_at IS '주소 생성 시각.';
COMMENT ON COLUMN p_user_address.updated_at IS '주소 최종 수정 시각.';
COMMENT ON COLUMN p_user_address.deleted_at IS '소프트 삭제 시각.';

CREATE TABLE IF NOT EXISTS p_user_audit (
    id                UUID PRIMARY KEY,
    user_id           UUID NOT NULL,
    event_type        TEXT NOT NULL CHECK (event_type IN ('USER_REGISTERED', 'PROFILE_UPDATED')),
    change_summary    TEXT,
    recorded_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    metadata          JSONB
);

COMMENT ON TABLE p_user_audit IS '사용자 계정의 주요 변경 이력을 남기는 감사 로그.';
COMMENT ON COLUMN p_user_audit.id IS '감사 레코드의 UUID 기본 키.';
COMMENT ON COLUMN p_user_audit.user_id IS '감사 이벤트의 대상 사용자 식별자.';
COMMENT ON COLUMN p_user_audit.event_type IS '회원가입, 프로필 변경 등 이벤트 유형.';
COMMENT ON COLUMN p_user_audit.change_summary IS '변경 내용을 요약한 설명.';
COMMENT ON COLUMN p_user_audit.recorded_at IS '감사 이벤트가 기록된 시각.';
COMMENT ON COLUMN p_user_audit.metadata IS '추가 메타 정보를 담는 JSON 데이터.';

-- Helpful indexes for query patterns (no foreign keys per requirements)
CREATE INDEX IF NOT EXISTS idx_p_user_role ON p_user (role);
CREATE INDEX IF NOT EXISTS idx_p_user_deleted_at ON p_user (deleted_at);
CREATE UNIQUE INDEX IF NOT EXISTS idx_p_user_address_default ON p_user_address (user_id) WHERE is_default;
