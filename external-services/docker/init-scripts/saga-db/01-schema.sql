-- Saga Tracker DB Schema
-- Combined from Flyway migrations V1-V4

-- V1: Saga 인스턴스 메인 테이블 생성
CREATE TABLE saga_instance (
    saga_id         VARCHAR(100)    PRIMARY KEY,
    saga_type       VARCHAR(50)     NOT NULL,
    order_id        VARCHAR(100)    NOT NULL,
    current_status  VARCHAR(20)     NOT NULL DEFAULT 'STARTED',
    last_step       VARCHAR(100)    NULL,
    last_trace_id   VARCHAR(100)    NULL,
    started_at      TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_at      TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT chk_saga_instance_status CHECK (
        current_status IN ('STARTED', 'IN_PROGRESS', 'COMPLETED', 'FAILED', 'COMPENSATED')
    ),
    CONSTRAINT chk_saga_instance_type CHECK (
        saga_type IN ('ORDER_CREATION', 'PAYMENT_COMPLETION')
    )
);

COMMENT ON TABLE saga_instance IS 'Saga 인스턴스 메인 테이블';
COMMENT ON COLUMN saga_instance.saga_id IS 'Saga 고유 식별자';
COMMENT ON COLUMN saga_instance.saga_type IS 'Saga 유형 (ORDER_CREATION, PAYMENT_COMPLETION)';
COMMENT ON COLUMN saga_instance.order_id IS '연관된 주문 ID';
COMMENT ON COLUMN saga_instance.current_status IS '현재 Saga 상태';
COMMENT ON COLUMN saga_instance.last_step IS '마지막으로 처리된 단계';
COMMENT ON COLUMN saga_instance.last_trace_id IS '마지막 단계의 트레이스 ID';

-- V2: Saga 단계별 이력 테이블 생성
CREATE TABLE saga_steps (
    id               BIGSERIAL       PRIMARY KEY,
    saga_id          VARCHAR(100)    NOT NULL,
    event_id         VARCHAR(100)    NOT NULL UNIQUE,
    step             VARCHAR(100)    NOT NULL,
    status           VARCHAR(20)     NOT NULL,
    producer_service VARCHAR(50)     NULL,
    trace_id         VARCHAR(100)    NULL,
    metadata         JSONB           NULL,
    recorded_at      TIMESTAMP       NOT NULL,
    created_at       TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_saga_steps_saga_id
        FOREIGN KEY (saga_id) REFERENCES saga_instance(saga_id) ON DELETE CASCADE,
    CONSTRAINT chk_saga_steps_status CHECK (
        status IN ('STARTED', 'IN_PROGRESS', 'COMPLETED', 'FAILED', 'COMPENSATED')
    )
);

COMMENT ON TABLE saga_steps IS 'Saga 단계별 이력 테이블';
COMMENT ON COLUMN saga_steps.event_id IS '이벤트 고유 ID (멱등성 보장)';
COMMENT ON COLUMN saga_steps.step IS 'Saga 단계명 (예: STOCK_RESERVATION, PAYMENT_INITIALIZATION)';
COMMENT ON COLUMN saga_steps.producer_service IS '이벤트 발행 서비스명';
COMMENT ON COLUMN saga_steps.trace_id IS 'OpenTelemetry Trace ID';
COMMENT ON COLUMN saga_steps.metadata IS '추가 메타데이터 (JSON)';

-- V3: 인덱스 추가
-- saga_instance 인덱스
CREATE INDEX idx_saga_instance_order_id ON saga_instance(order_id);
CREATE INDEX idx_saga_instance_status ON saga_instance(current_status);
CREATE INDEX idx_saga_instance_type ON saga_instance(saga_type);
CREATE INDEX idx_saga_instance_started_at ON saga_instance(started_at);
CREATE INDEX idx_saga_instance_updated_at ON saga_instance(updated_at);

-- 복합 인덱스: 일반적인 쿼리 패턴 지원
CREATE INDEX idx_saga_instance_type_status ON saga_instance(saga_type, current_status);
CREATE INDEX idx_saga_instance_started_at_status ON saga_instance(started_at DESC, current_status);

-- saga_steps 인덱스
CREATE INDEX idx_saga_steps_saga_id ON saga_steps(saga_id);
CREATE INDEX idx_saga_steps_step ON saga_steps(step);
CREATE INDEX idx_saga_steps_recorded_at ON saga_steps(recorded_at);
CREATE INDEX idx_saga_steps_status ON saga_steps(status);

-- 복합 인덱스
CREATE INDEX idx_saga_steps_saga_step ON saga_steps(saga_id, step);
CREATE INDEX idx_saga_steps_saga_recorded ON saga_steps(saga_id, recorded_at);

-- V4: JSONB GIN 인덱스 추가 (metadata 검색용)
CREATE INDEX idx_saga_steps_metadata ON saga_steps USING GIN (metadata);
