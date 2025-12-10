-- Payment Service DDL
-- PostgreSQL dialect

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Payment domain tables (matching Payment.kt entity with user_id)
CREATE TABLE IF NOT EXISTS p_payment (
    id                    UUID PRIMARY KEY,
    version               BIGINT NOT NULL DEFAULT 0,
    order_id              UUID NOT NULL,
    user_id               UUID NOT NULL,
    total_amount          NUMERIC(12, 2),
    payment_amount        NUMERIC(12, 2),
    discount_amount       NUMERIC(12, 2),
    delivery_fee          NUMERIC(12, 2),
    method                TEXT CHECK (method IN ('CARD', 'TOSS_PAY')),
    status                TEXT NOT NULL DEFAULT 'PAYMENT_WAIT' CHECK (status IN ('PAYMENT_WAIT', 'PAYMENT_REQUEST', 'PAYMENT_COMPLETED', 'PAYMENT_FAILED', 'PAYMENT_CANCELLED', 'REFUND_REQUESTED', 'REFUND_COMPLETED')),
    requested_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at          TIMESTAMPTZ,
    cancelled_at          TIMESTAMPTZ,
    refunded_at           TIMESTAMPTZ,
    pg_transaction_id     TEXT,
    pg_approval_number    TEXT,
    refund_transaction_id TEXT,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE p_payment IS '주문 결제 내역을 저장하는 테이블.';
COMMENT ON COLUMN p_payment.id IS '결제 레코드의 UUID 기본 키.';
COMMENT ON COLUMN p_payment.version IS 'Optimistic locking을 위한 버전 필드.';
COMMENT ON COLUMN p_payment.order_id IS '결제와 연결된 주문 ID.';
COMMENT ON COLUMN p_payment.user_id IS '결제를 요청한 사용자 ID.';
COMMENT ON COLUMN p_payment.total_amount IS '총 주문금액';
COMMENT ON COLUMN p_payment.payment_amount IS '실제 결제된 금액.';
COMMENT ON COLUMN p_payment.discount_amount IS '할인 및 쿠폰 적용 금액.';
COMMENT ON COLUMN p_payment.delivery_fee IS '배송비 금액.';
COMMENT ON COLUMN p_payment.status IS 'PAYMENT_WAIT, PAYMENT_COMPLETED 등 현재 결제 상태.';
COMMENT ON COLUMN p_payment.method IS 'CARD, TOSS_PAY 등 결제 수단.';
COMMENT ON COLUMN p_payment.requested_at IS '결제 요청 시각.';
COMMENT ON COLUMN p_payment.completed_at IS '결제 완료 시각.';
COMMENT ON COLUMN p_payment.cancelled_at IS '결제 취소 시각.';
COMMENT ON COLUMN p_payment.refunded_at IS '환불 완료 시각.';
COMMENT ON COLUMN p_payment.pg_transaction_id IS 'PG사 거래 ID.';
COMMENT ON COLUMN p_payment.pg_approval_number IS 'PG사 승인 번호.';
COMMENT ON COLUMN p_payment.refund_transaction_id IS '환불 거래 ID.';
COMMENT ON COLUMN p_payment.created_at IS '결제 레코드 생성 시각.';
COMMENT ON COLUMN p_payment.updated_at IS '결제 레코드 최종 수정 시각.';

CREATE TABLE IF NOT EXISTS p_payment_history (
    id                UUID PRIMARY KEY,
    payment_id        UUID NOT NULL,
    event_type        TEXT NOT NULL CHECK (event_type IN (
        'PAYMENT_REQUESTED',
        'PAYMENT_COMPLETED',
        'PAYMENT_FAILED',
        'PAYMENT_CANCELLED',
        'REFUND_REQUESTED',
        'REFUND_COMPLETED'
    )),
    change_summary    TEXT,
    recorded_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE p_payment_history IS '결제 및 환불 처리 이력을 기록하는 감사 로그.';
COMMENT ON COLUMN p_payment_history.id IS '결제 이력 레코드의 UUID 기본 키.';
COMMENT ON COLUMN p_payment_history.payment_id IS '이벤트가 속한 결제 ID.';
COMMENT ON COLUMN p_payment_history.event_type IS '결제 이벤트 유형.';
COMMENT ON COLUMN p_payment_history.change_summary IS '처리 내역 요약 설명.';
COMMENT ON COLUMN p_payment_history.recorded_at IS '이력이 기록된 시각.';

CREATE TABLE IF NOT EXISTS p_payment_gateway_log (
    id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    payment_id            UUID NOT NULL,
    pg_code               TEXT NOT NULL,
    status                TEXT NOT NULL CHECK (status IN ('REQUEST', 'APPROVED', 'FAILED')),
    external_payment_data TEXT NOT NULL,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at            TIMESTAMPTZ
);

COMMENT ON TABLE p_payment_gateway_log IS '외부 PG사와 통신한 이력을 저장하는 테이블.';
COMMENT ON COLUMN p_payment_gateway_log.id IS '외부 결제 통신 이력 UUID.';
COMMENT ON COLUMN p_payment_gateway_log.payment_id IS '연결된 결제(p_payment) ID.';
COMMENT ON COLUMN p_payment_gateway_log.pg_code IS 'PG사 식별 코드.';
COMMENT ON COLUMN p_payment_gateway_log.status IS '결제요청, 승인, 실패 상태 값.';
COMMENT ON COLUMN p_payment_gateway_log.external_payment_data IS '요청/응답 전문 원문을 저장한 텍스트.';
COMMENT ON COLUMN p_payment_gateway_log.created_at IS '레코드 생성 시각.';
COMMENT ON COLUMN p_payment_gateway_log.updated_at IS '레코드 최종 수정 시각.';
COMMENT ON COLUMN p_payment_gateway_log.deleted_at IS '소프트 삭제 시각.';

-- Indexes
CREATE INDEX IF NOT EXISTS idx_p_payment_order ON p_payment (order_id);
CREATE INDEX IF NOT EXISTS idx_p_payment_user ON p_payment (user_id);
CREATE INDEX IF NOT EXISTS idx_p_payment_method ON p_payment (method);
CREATE INDEX IF NOT EXISTS idx_p_payment_status ON p_payment (status);
CREATE INDEX IF NOT EXISTS idx_p_payment_history_payment ON p_payment_history (payment_id);
CREATE INDEX IF NOT EXISTS idx_p_payment_gateway_log_payment ON p_payment_gateway_log (payment_id);
