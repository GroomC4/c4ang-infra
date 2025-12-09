-- Marketplace platform DDL generated from database_design_requirent.md requirements
-- PostgreSQL dialect

CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- Order domain
CREATE TABLE IF NOT EXISTS p_order (
    id                UUID PRIMARY KEY,
    user_id           UUID NOT NULL,
    store_id          UUID NOT NULL,
    order_number      TEXT NOT NULL,
    status            TEXT NOT NULL DEFAULT 'ORDER_CREATED' CHECK (status IN (
    -- 주문 접수 단계
    'ORDER_CREATED',
    'ORDER_CONFIRMED',
    -- 결제 단계
    'PAYMENT_PENDING',
    'PAYMENT_PROCESSING',
    'PAYMENT_COMPLETED',
    -- 배송 단계
    'PREPARING',
    'SHIPPED',
    'DELIVERED',
    -- 취소/실패 단계
    'PAYMENT_TIMEOUT',
    'ORDER_CANCELLED',
    -- 반품/환불 단계
    'RETURN_REQUESTED',
    'RETURN_APPROVED',
    'RETURN_IN_TRANSIT',
    'RETURN_COMPLETED',
    'REFUND_PROCESSING',
    'REFUND_COMPLETED',
    -- 예외 처리
    'FAILED',
    'REQUIRES_MANUAL_INTERVENTION'
)),
    payment_summary   JSON NOT NULL,
    timeline          JSON NOT NULL,
    note              TEXT,
    -- 비동기 플로우 추가 컬럼
    reservation_id    TEXT,
    payment_id        UUID,
    expires_at        TIMESTAMPTZ,
    confirmed_at      TIMESTAMPTZ,
    cancelled_at      TIMESTAMPTZ,
    failure_reason    TEXT,
    refund_id         TEXT,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at        TIMESTAMPTZ,
    UNIQUE (order_number)
    );

COMMENT ON TABLE p_order IS '주문 요약 정보를 담는 테이블.';
COMMENT ON COLUMN p_order.id IS '주문의 UUID 기본 키.';
COMMENT ON COLUMN p_order.user_id IS '주문한 사용자 UUID.';
COMMENT ON COLUMN p_order.store_id IS '주문이 속한 스토어 ID.';
COMMENT ON COLUMN p_order.status IS '주문의 현재 상태(주문중, 결제완료, 배송준비, 배송중, 배송완료, 주문취소, 반품/환불요청, 반품/환불완료)';
COMMENT ON COLUMN p_order.payment_summary IS '결제 금액 등 결제 요약 정보를 담은 JSON 객체.';
COMMENT ON COLUMN p_order.timeline IS '주문 상태 변경 이력을 담은 JSON 배열.';
COMMENT ON COLUMN p_order.order_number IS '고객에게 안내되는 주문 번호. 형식은 ORD-주문연월-6자리난수(예: ORD-20251017-X8Z1Y9)';
COMMENT ON COLUMN p_order.note IS '주문 관련 메모 또는 요청 사항.';
COMMENT ON COLUMN p_order.reservation_id IS '재고 예약 시스템의 예약 ID (Redis key)';
COMMENT ON COLUMN p_order.payment_id IS '연결된 결제 레코드 ID';
COMMENT ON COLUMN p_order.expires_at IS '결제 시간 제한 (주문 생성 후 10분)';
COMMENT ON COLUMN p_order.confirmed_at IS '주문 확정 시각 (결제 완료 시)';
COMMENT ON COLUMN p_order.cancelled_at IS '주문 취소 시각';
COMMENT ON COLUMN p_order.failure_reason IS '실패 또는 취소 사유';
COMMENT ON COLUMN p_order.refund_id IS '환불 거래 ID (PG사 제공)';
COMMENT ON COLUMN p_order.created_at IS '주문 레코드 생성 시각.';
COMMENT ON COLUMN p_order.updated_at IS '주문 레코드 최종 수정 시각.';
COMMENT ON COLUMN p_order.deleted_at IS '소프트 삭제 시각.';

-- 성능 최적화 인덱스
CREATE INDEX IF NOT EXISTS idx_p_order_status_expires
    ON p_order (status, expires_at)
    WHERE status IN ('PAYMENT_PENDING', 'PAYMENT_PROCESSING');

CREATE INDEX IF NOT EXISTS idx_p_order_reservation
    ON p_order (reservation_id)
    WHERE reservation_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_p_order_payment
    ON p_order (payment_id)
    WHERE payment_id IS NOT NULL;

COMMENT ON INDEX idx_p_order_status_expires IS '결제 타임아웃 스케줄러 최적화용';
COMMENT ON INDEX idx_p_order_reservation IS '재고 예약 조회 최적화용';
COMMENT ON INDEX idx_p_order_payment IS '결제 콜백 처리 최적화용';

CREATE TABLE IF NOT EXISTS p_order_item (
         id                UUID PRIMARY KEY,
         order_id          UUID NOT NULL,
         product_id        UUID NOT NULL,
         product_name      TEXT NOT NULL,
         quantity          INTEGER NOT NULL,
         unit_price        NUMERIC(12, 2) NOT NULL,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (quantity > 0),
    CHECK (unit_price >= 0)
    );

COMMENT ON TABLE p_order_item IS '주문에 포함된 개별 상품 라인 아이템 테이블.';
COMMENT ON COLUMN p_order_item.id IS '주문 상품의 UUID 기본 키.';
COMMENT ON COLUMN p_order_item.order_id IS '소속 주문 ID.';
COMMENT ON COLUMN p_order_item.product_id IS '주문된 상품 ID.';
COMMENT ON COLUMN p_order_item.product_name IS '주문된 상품명.';
COMMENT ON COLUMN p_order_item.quantity IS '주문 수량.';
COMMENT ON COLUMN p_order_item.unit_price IS '주문 시점의 단가.';
COMMENT ON COLUMN p_order_item.created_at IS '주문 상품 레코드 생성 시각.';
COMMENT ON COLUMN p_order_item.updated_at IS '주문 상품 레코드 최종 수정 시각.';

CREATE TABLE IF NOT EXISTS p_order_item_shipping (
                  id                UUID PRIMARY KEY,
                  order_id          UUID NOT NULL,
                  order_item_id     UUID NOT NULL,
                  product_id        UUID NOT NULL,
                  tracking_number   TEXT,
                  carrier_code      TEXT,
                  address_line1     TEXT NOT NULL,
                  address_line2     TEXT,
                  recipient_name    TEXT NOT NULL,
                  recipient_phone   TEXT NOT NULL,
                  postal_code       TEXT NOT NULL,
                  status            TEXT NOT NULL DEFAULT 'PREPARING' CHECK (status IN ('PREPARING', 'REQUESTED', 'IN_TRANSIT', 'DELIVERED')),
    shipped_at        TIMESTAMPTZ,
    delivered_at      TIMESTAMPTZ,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at        TIMESTAMPTZ,
    UNIQUE (order_id, order_item_id)
    );

COMMENT ON TABLE p_order_item_shipping IS '주문 상품별 배송 정보를 저장하는 테이블.';
COMMENT ON COLUMN p_order_item_shipping.id IS '배송 레코드의 UUID 기본 키.';
COMMENT ON COLUMN p_order_item_shipping.order_id IS '배송이 속한 주문 ID.';
COMMENT ON COLUMN p_order_item_shipping.order_item_id IS '배송 대상 주문 상품 ID.';
COMMENT ON COLUMN p_order_item_shipping.product_id IS '배송 대상 상품 ID.';
COMMENT ON COLUMN p_order_item_shipping.tracking_number IS '택배사 송장번호.';
COMMENT ON COLUMN p_order_item_shipping.carrier_code IS '애플리케이션에서 관리하는 택배사 코드.';
COMMENT ON COLUMN p_order_item_shipping.address_line1 IS '기본 배송지 주소.';
COMMENT ON COLUMN p_order_item_shipping.address_line2 IS '추가 배송지 상세.';
COMMENT ON COLUMN p_order_item_shipping.recipient_name IS '수취인 이름.';
COMMENT ON COLUMN p_order_item_shipping.recipient_phone IS '수취인 연락처.';
COMMENT ON COLUMN p_order_item_shipping.postal_code IS '배송지 우편번호.';
COMMENT ON COLUMN p_order_item_shipping.status IS 'PREPARING/DELIVERED 등 배송 상태.';
COMMENT ON COLUMN p_order_item_shipping.shipped_at IS '출고 시각.';
COMMENT ON COLUMN p_order_item_shipping.delivered_at IS '배송 완료 시각.';
COMMENT ON COLUMN p_order_item_shipping.created_at IS '배송 레코드 생성 시각.';
COMMENT ON COLUMN p_order_item_shipping.updated_at IS '배송 레코드 최종 수정 시각.';
COMMENT ON COLUMN p_order_item_shipping.deleted_at IS '소프트 삭제 시각.';

CREATE TABLE IF NOT EXISTS p_order_audit (
          id                UUID PRIMARY KEY,
          order_id          UUID NOT NULL,
          order_item_id     UUID,
          event_type        TEXT NOT NULL CHECK (event_type IN (
          'ORDER_CREATED',
          'STOCK_RESERVED',
          'PAYMENT_REQUESTED',
          'PAYMENT_COMPLETED',
          'ORDER_CONFIRMED',
          'ORDER_CANCELLED',
          'ORDER_REFUNDED',
          'ORDER_TIMEOUT'
)),
    change_summary    TEXT,
    actor_user_id     UUID,
    recorded_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    metadata          JSONB
    );

COMMENT ON TABLE p_order_audit IS '주문 및 배송 상태 변화를 추적하는 감사 로그.';
COMMENT ON COLUMN p_order_audit.id IS '주문 감사 레코드의 UUID 기본 키.';
COMMENT ON COLUMN p_order_audit.order_id IS '이벤트가 발생한 주문 ID.';
COMMENT ON COLUMN p_order_audit.order_item_id IS '영향을 받은 주문 상품 ID(없을 수 있음).';
COMMENT ON COLUMN p_order_audit.event_type IS 'ORDERED, SHIPPING_IN_TRANSIT 등 이벤트 유형.';
COMMENT ON COLUMN p_order_audit.change_summary IS '변경 사항 요약 설명.';
COMMENT ON COLUMN p_order_audit.actor_user_id IS '변경을 수행한 사용자 UUID.';
COMMENT ON COLUMN p_order_audit.recorded_at IS '감사 이벤트가 기록된 시각.';
COMMENT ON COLUMN p_order_audit.metadata IS '추가 정보를 담은 JSON 메타데이터.';