-- Marketplace platform DDL generated from database_design_requirent.md requirements
-- PostgreSQL dialect

CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- Product domain
CREATE TABLE IF NOT EXISTS p_product_category (
                                                  id                UUID PRIMARY KEY,
                                                  name              TEXT NOT NULL,
                                                  parent_category_id UUID,
                                                  depth             INTEGER NOT NULL DEFAULT 0,
                                                  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at        TIMESTAMPTZ,
    UNIQUE (name, parent_category_id),
    CHECK (depth >= 0)
    );

COMMENT ON TABLE p_product_category IS '상품 카테고리의 계층 구조를 관리하는 테이블.';
COMMENT ON COLUMN p_product_category.id IS '카테고리 노드의 UUID 기본 키.';
COMMENT ON COLUMN p_product_category.name IS '카테고리 표시 이름.';
COMMENT ON COLUMN p_product_category.parent_category_id IS '상위 카테고리 ID(NULL이면 루트).';
COMMENT ON COLUMN p_product_category.depth IS '루트 0부터 시작하는 계층 깊이.';
COMMENT ON COLUMN p_product_category.created_at IS '카테고리 생성 시각.';
COMMENT ON COLUMN p_product_category.updated_at IS '카테고리 최종 수정 시각.';
COMMENT ON COLUMN p_product_category.deleted_at IS '소프트 삭제 시각.';

CREATE TABLE IF NOT EXISTS p_product (
                                         id                UUID PRIMARY KEY,
                                         store_id          UUID NOT NULL,
                                         store_name        TEXT NOT NULL,
                                         category_id       UUID NOT NULL,
                                         product_name      TEXT NOT NULL,
                                         status            TEXT NOT NULL DEFAULT 'ON_SALE' CHECK (status IN ('ON_SALE', 'OFF_SHELF')),
    price             NUMERIC(12, 2) NOT NULL,
    stock_quantity    INTEGER NOT NULL DEFAULT 0,
    thumbnail_url     TEXT,
    description       TEXT,
    hidden_at         TIMESTAMPTZ,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at        TIMESTAMPTZ,
    CHECK (price >= 0),
    CHECK (stock_quantity >= 0)
    );

COMMENT ON TABLE p_product IS '판매 가능한 상품 정보를 저장하는 테이블.';
COMMENT ON COLUMN p_product.id IS '상품의 UUID 기본 키.';
COMMENT ON COLUMN p_product.store_id IS '상품을 판매하는 스토어 ID.';
COMMENT ON COLUMN p_product.store_name IS '스토어 이름 (비정규화, 읽기 최적화용).';
COMMENT ON COLUMN p_product.category_id IS '주요 카테고리 식별자.';
COMMENT ON COLUMN p_product.product_name IS '상품명.';
COMMENT ON COLUMN p_product.status IS '판매 상태(ON_SALE/OFF_SHELF).';
COMMENT ON COLUMN p_product.price IS '현재 판매 가격.';
COMMENT ON COLUMN p_product.stock_quantity IS '잔여 재고 수량.';
COMMENT ON COLUMN p_product.thumbnail_url IS '대표 이미지 URL.';
COMMENT ON COLUMN p_product.description IS '상품 상세 설명.';
COMMENT ON COLUMN p_product.hidden_at IS '상품이 숨김 처리된 시각.';
COMMENT ON COLUMN p_product.created_at IS '상품 등록 시각.';
COMMENT ON COLUMN p_product.updated_at IS '상품 정보 최종 수정 시각.';
COMMENT ON COLUMN p_product.deleted_at IS '소프트 삭제 시각.';

CREATE TABLE IF NOT EXISTS p_product_image (
                                               id                UUID PRIMARY KEY,
                                               product_id        UUID NOT NULL,
                                               image_type        TEXT NOT NULL CHECK (image_type IN ('PRIMARY', 'DETAIL')),
    image_url         TEXT NOT NULL,
    display_order     INTEGER NOT NULL DEFAULT 0,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at        TIMESTAMPTZ,
    UNIQUE (product_id, image_type, display_order)
    );

COMMENT ON TABLE p_product_image IS '상품의 상세/대표 이미지를 관리하는 테이블.';
COMMENT ON COLUMN p_product_image.id IS '상품 이미지의 UUID 기본 키.';
COMMENT ON COLUMN p_product_image.product_id IS '이미지가 연결된 상품 ID.';
COMMENT ON COLUMN p_product_image.image_type IS 'PRIMARY/DETAIL 등 이미지 용도.';
COMMENT ON COLUMN p_product_image.image_url IS '이미지 파일 URL.';
COMMENT ON COLUMN p_product_image.display_order IS '0부터 시작하는 노출 순서.';
COMMENT ON COLUMN p_product_image.created_at IS '이미지 레코드 생성 시각.';
COMMENT ON COLUMN p_product_image.updated_at IS '이미지 레코드 최종 수정 시각.';
COMMENT ON COLUMN p_product_image.deleted_at IS '소프트 삭제 시각.';

CREATE TABLE IF NOT EXISTS p_product_audit (
                                               id                UUID PRIMARY KEY,
                                               product_id        UUID NOT NULL,
                                               actor_user_id     UUID,
                                               event_type        TEXT NOT NULL CHECK (event_type IN ('PRODUCT_REGISTERED', 'PRODUCT_HIDDEN', 'PRODUCT_DELETED', 'PRODUCT_UPDATED')),
    status_snapshot   TEXT CHECK (status_snapshot IN ('ON_SALE', 'OFF_SHELF')),
    hidden_at_snapshot TIMESTAMPTZ,
    change_summary    TEXT,
    recorded_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    metadata          JSONB
    );

-- Processed Events (이벤트 멱등성 보장)
CREATE TABLE IF NOT EXISTS p_processed_event (
    event_id          TEXT PRIMARY KEY,
    event_type        TEXT NOT NULL,
    processed_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE p_processed_event IS 'Kafka 이벤트 중복 처리 방지를 위한 테이블';
COMMENT ON COLUMN p_processed_event.event_id IS '처리된 이벤트의 고유 ID';
COMMENT ON COLUMN p_processed_event.event_type IS '이벤트 타입 (예: order.created, store.info.updated)';
COMMENT ON COLUMN p_processed_event.processed_at IS '이벤트 처리 시각';

CREATE INDEX IF NOT EXISTS idx_processed_event_type ON p_processed_event(event_type);
CREATE INDEX IF NOT EXISTS idx_processed_event_processed_at ON p_processed_event(processed_at);

-- Stock Reservation Log (Redis 재고 예약 백업)
CREATE TABLE IF NOT EXISTS p_stock_reservation_log (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reservation_id    TEXT NOT NULL UNIQUE,
    order_id          UUID NOT NULL,
    store_id          UUID NOT NULL,
    products          JSONB NOT NULL,
    status            TEXT NOT NULL CHECK (status IN ('RESERVED', 'CONFIRMED', 'RELEASED', 'EXPIRED')),
    reserved_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at        TIMESTAMPTZ NOT NULL,
    confirmed_at      TIMESTAMPTZ,
    released_at       TIMESTAMPTZ,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
    );

CREATE INDEX IF NOT EXISTS idx_stock_reservation_order ON p_stock_reservation_log(order_id);
CREATE INDEX IF NOT EXISTS idx_stock_reservation_expires ON p_stock_reservation_log(expires_at) WHERE status = 'RESERVED';
CREATE INDEX IF NOT EXISTS idx_stock_reservation_status ON p_stock_reservation_log(status);

COMMENT ON TABLE p_stock_reservation_log IS 'Redis 재고 예약 내역을 DB에 백업 (모니터링 및 복구용)';
COMMENT ON COLUMN p_stock_reservation_log.reservation_id IS 'Redis에서 사용하는 예약 ID';
COMMENT ON COLUMN p_stock_reservation_log.order_id IS '연결된 주문 ID';
COMMENT ON COLUMN p_stock_reservation_log.store_id IS '스토어 ID';
COMMENT ON COLUMN p_stock_reservation_log.products IS '예약된 상품 목록 [{productId, quantity}]';
COMMENT ON COLUMN p_stock_reservation_log.status IS 'RESERVED(예약), CONFIRMED(확정), RELEASED(해제), EXPIRED(만료)';
COMMENT ON COLUMN p_stock_reservation_log.reserved_at IS '예약 시각';
COMMENT ON COLUMN p_stock_reservation_log.expires_at IS '예약 만료 시각';
COMMENT ON COLUMN p_stock_reservation_log.confirmed_at IS '예약 확정 시각 (결제 완료)';
COMMENT ON COLUMN p_stock_reservation_log.released_at IS '예약 해제 시각 (취소 또는 만료)';


COMMENT ON TABLE p_product_audit IS '상품 등록/숨김/삭제 등 변동 내역을 기록하는 감사 로그.';
COMMENT ON COLUMN p_product_audit.id IS '상품 감사 레코드의 UUID 기본 키.';
COMMENT ON COLUMN p_product_audit.product_id IS '이벤트 대상 상품 ID.';
COMMENT ON COLUMN p_product_audit.actor_user_id IS '변경 수행자 사용자 UUID.';
COMMENT ON COLUMN p_product_audit.event_type IS 'PRODUCT_REGISTERED 등 이벤트 유형.';
COMMENT ON COLUMN p_product_audit.status_snapshot IS '이벤트 시점의 상품 상태 스냅샷.';
COMMENT ON COLUMN p_product_audit.hidden_at_snapshot IS '이벤트 기록 당시 hidden_at 값.';
COMMENT ON COLUMN p_product_audit.change_summary IS '변경 사항 요약 설명.';
COMMENT ON COLUMN p_product_audit.recorded_at IS '감사 이벤트 기록 시각.';
COMMENT ON COLUMN p_product_audit.metadata IS '추가 정보를 담은 JSON 메타데이터.';

CREATE TABLE IF NOT EXISTS p_ai_prompt_audit (
    id                UUID PRIMARY KEY,
    user_id           UUID,
    prompt            TEXT NOT NULL,
    response          TEXT,
    model             TEXT,
    success           BOOLEAN NOT NULL DEFAULT false,
    error_message     TEXT,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    metadata          JSONB
);

COMMENT ON TABLE p_ai_prompt_audit IS 'AI API 요청 질문과 응답을 모두 저장하는 감사 로그.';
COMMENT ON COLUMN p_ai_prompt_audit.id IS 'AI 프롬프트 감사 레코드의 UUID 기본 키.';
COMMENT ON COLUMN p_ai_prompt_audit.user_id IS '요청한 사용자 UUID (nullable).';
COMMENT ON COLUMN p_ai_prompt_audit.prompt IS 'AI에게 전송한 프롬프트 내용.';
COMMENT ON COLUMN p_ai_prompt_audit.response IS 'AI로부터 받은 응답 내용.';
COMMENT ON COLUMN p_ai_prompt_audit.model IS '사용된 AI 모델명 (예: gemini-pro).';
COMMENT ON COLUMN p_ai_prompt_audit.success IS 'API 호출 성공 여부.';
COMMENT ON COLUMN p_ai_prompt_audit.error_message IS '실패 시 에러 메시지.';
COMMENT ON COLUMN p_ai_prompt_audit.created_at IS '프롬프트 요청 시각.';
COMMENT ON COLUMN p_ai_prompt_audit.metadata IS '추가 정보를 담은 JSON 메타데이터.';

CREATE INDEX IF NOT EXISTS idx_p_product_category_parent ON p_product_category (parent_category_id);
CREATE INDEX IF NOT EXISTS idx_p_product_store ON p_product (store_id);
CREATE INDEX IF NOT EXISTS idx_p_product_category ON p_product (category_id);
CREATE INDEX IF NOT EXISTS idx_p_product_status ON p_product (status);
CREATE INDEX IF NOT EXISTS idx_p_product_hidden ON p_product (hidden_at);
CREATE INDEX IF NOT EXISTS idx_p_product_name_trgm ON p_product USING GIN (product_name gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_p_product_store_name_trgm ON p_product USING GIN (store_name gin_trgm_ops);

-- =====================================================
-- Perfume Domain (향수 특화 정보)
-- =====================================================

-- 향수 특화 정보 테이블
-- p_product와 1:1 관계 (논리적 FK, 물리적 제약 없음)
CREATE TABLE IF NOT EXISTS p_perfume (
    id                UUID PRIMARY KEY,
    product_id        UUID NOT NULL,
    brand             TEXT NOT NULL,
    name              TEXT NOT NULL,
    concentration     TEXT,
    main_accords      JSONB,
    top_notes         JSONB,
    middle_notes      JSONB,
    base_notes        JSONB,
    notes_score       JSONB,
    season_score      JSONB,
    day_night_score   JSONB,
    gender            TEXT CHECK (gender IN ('Male', 'Female', 'Unisex')),
    sizes             JSONB,
    detail_url        TEXT,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at        TIMESTAMPTZ,
    UNIQUE (brand, name)
);

COMMENT ON TABLE p_perfume IS '향수 특화 정보를 저장하는 테이블. p_product와 1:1 관계.';
COMMENT ON COLUMN p_perfume.id IS '향수 정보의 UUID 기본 키.';
COMMENT ON COLUMN p_perfume.product_id IS '연결된 p_product ID (논리적 FK).';
COMMENT ON COLUMN p_perfume.brand IS '브랜드명.';
COMMENT ON COLUMN p_perfume.name IS '향수명.';
COMMENT ON COLUMN p_perfume.concentration IS '농도 (오 드 퍼퓸, 오 드 뚜왈렛 등).';
COMMENT ON COLUMN p_perfume.main_accords IS '주요 향조 배열 (JSONB).';
COMMENT ON COLUMN p_perfume.top_notes IS '탑노트 배열 (JSONB).';
COMMENT ON COLUMN p_perfume.middle_notes IS '미들노트 배열 (JSONB).';
COMMENT ON COLUMN p_perfume.base_notes IS '베이스노트 배열 (JSONB).';
COMMENT ON COLUMN p_perfume.notes_score IS '노트별 점수 (JSONB).';
COMMENT ON COLUMN p_perfume.season_score IS '계절 점수 (JSONB). 예: {"spring": 24.1, "summer": 3.8, "fall": 95.5, "winter": 14.2}';
COMMENT ON COLUMN p_perfume.day_night_score IS '주야간 점수 (JSONB). 예: {"day": 47.1, "night": 25.9}';
COMMENT ON COLUMN p_perfume.gender IS '성별 타겟 (Male/Female/Unisex).';
COMMENT ON COLUMN p_perfume.sizes IS '용량별 가격 정보 (JSONB). 예: [{"size_ml": 30, "price": 120000}, {"size_ml": 50, "price": 180000}]';
COMMENT ON COLUMN p_perfume.detail_url IS '원본 상세 페이지 URL.';
COMMENT ON COLUMN p_perfume.created_at IS '레코드 생성 시각.';
COMMENT ON COLUMN p_perfume.updated_at IS '레코드 최종 수정 시각.';
COMMENT ON COLUMN p_perfume.deleted_at IS '소프트 삭제 시각.';

CREATE INDEX IF NOT EXISTS idx_p_perfume_product ON p_perfume (product_id);
CREATE INDEX IF NOT EXISTS idx_p_perfume_brand ON p_perfume (brand);
CREATE INDEX IF NOT EXISTS idx_p_perfume_gender ON p_perfume (gender);
CREATE INDEX IF NOT EXISTS idx_p_perfume_brand_trgm ON p_perfume USING GIN (brand gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_p_perfume_name_trgm ON p_perfume USING GIN (name gin_trgm_ops);

-- 노트 이미지 참조 테이블
-- 향수 노트(재료)의 이미지 URL을 관리하는 마스터 데이터
CREATE TABLE IF NOT EXISTS p_note_image (
    id                UUID PRIMARY KEY,
    category          TEXT NOT NULL,
    note_name         TEXT NOT NULL,
    image_url         TEXT NOT NULL,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (category, note_name)
);

COMMENT ON TABLE p_note_image IS '향수 노트(재료) 이미지를 관리하는 참조 테이블.';
COMMENT ON COLUMN p_note_image.id IS '노트 이미지의 UUID 기본 키.';
COMMENT ON COLUMN p_note_image.category IS '노트 카테고리 (예: Citrus Smells, Floral).';
COMMENT ON COLUMN p_note_image.note_name IS '노트 이름 (예: Bergamot, Rose).';
COMMENT ON COLUMN p_note_image.image_url IS '노트 이미지 URL.';
COMMENT ON COLUMN p_note_image.created_at IS '레코드 생성 시각.';
COMMENT ON COLUMN p_note_image.updated_at IS '레코드 최종 수정 시각.';

CREATE INDEX IF NOT EXISTS idx_p_note_image_category ON p_note_image (category);
CREATE INDEX IF NOT EXISTS idx_p_note_image_note_name ON p_note_image (note_name);
CREATE INDEX IF NOT EXISTS idx_p_note_image_note_name_trgm ON p_note_image USING GIN (note_name gin_trgm_ops);

-- =====================================================
-- Seed Data for Product Service (고정 UUID)
-- RAG 서비스의 벡터DB에서 product_id를 논리적 FK로 참조
--
-- UUID 패턴 설계 (테스트 데이터와 충돌 방지):
-- - 카테고리: f1000000-0000-0000-0000-00000000000X
-- - 스토어:   f2000000-0000-0000-0000-00000000000X
-- - 제품:     f3000000-0000-0000-0000-00000000000X (RAG 벡터DB 참조용)
-- - 향수:     f4000000-0000-0000-0000-00000000000X
-- - 노트이미지: f5000000-0000-0000-0000-00000000000X
-- =====================================================

-- =====================================================
-- 1. 카테고리 데이터
-- =====================================================
INSERT INTO p_product_category (id, name, parent_category_id, depth) VALUES
    ('f1000000-0000-0000-0000-000000000001', '향수', NULL, 0),
    ('f1000000-0000-0000-0000-000000000002', '여성 향수', 'f1000000-0000-0000-0000-000000000001', 1),
    ('f1000000-0000-0000-0000-000000000003', '남성 향수', 'f1000000-0000-0000-0000-000000000001', 1),
    ('f1000000-0000-0000-0000-000000000004', '유니섹스 향수', 'f1000000-0000-0000-0000-000000000001', 1)
ON CONFLICT (name, parent_category_id) DO NOTHING;

-- =====================================================
-- 2. 스토어 데이터 (가상 스토어)
-- =====================================================
-- 스토어 ID (다른 서비스에서 관리, 여기서는 참조용)
-- store_id: f2000000-0000-0000-0000-000000000001 (C4ANG 향수 전문점)

-- =====================================================
-- 3. 제품(Product) 데이터 - 10개 샘플
-- 이 ID가 RAG 벡터DB에서 참조됨
-- =====================================================
INSERT INTO p_product (id, store_id, store_name, category_id, product_name, status, price, stock_quantity, description) VALUES
    -- 여성 향수
    ('f3000000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-000000000001', 'C4ANG 향수 전문점', 'f1000000-0000-0000-0000-000000000002', '크리드 어벤투스 포 허 오 드 퍼퓸', 'ON_SALE', 255000.00, 50, '여성을 위한 과일향과 플로랄이 조화된 럭셔리 향수'),
    ('f3000000-0000-0000-0000-000000000002', 'f2000000-0000-0000-0000-000000000001', 'C4ANG 향수 전문점', 'f1000000-0000-0000-0000-000000000002', '디올 미스 디올 오 드 퍼퓸', 'ON_SALE', 180000.00, 100, '우아한 플로랄 향수로 로맨틱한 분위기를 연출'),
    ('f3000000-0000-0000-0000-000000000003', 'f2000000-0000-0000-0000-000000000001', 'C4ANG 향수 전문점', 'f1000000-0000-0000-0000-000000000002', '샤넬 코코 마드모아젤 오 드 퍼퓸', 'ON_SALE', 220000.00, 80, '시트러스와 플로랄의 조화로운 여성 향수'),
    ('f3000000-0000-0000-0000-000000000004', 'f2000000-0000-0000-0000-000000000001', 'C4ANG 향수 전문점', 'f1000000-0000-0000-0000-000000000002', '겔랑 랭스땅 드 겔랑 오 드 퍼퓸', 'ON_SALE', 195000.00, 40, '강렬한 매혹의 플로랄 허니 향기'),
    -- 남성 향수
    ('f3000000-0000-0000-0000-000000000005', 'f2000000-0000-0000-0000-000000000001', 'C4ANG 향수 전문점', 'f1000000-0000-0000-0000-000000000003', '크리드 어벤투스 오 드 퍼퓸', 'ON_SALE', 399000.00, 30, '용기와 힘, 비전, 그리고 성공을 기원하는 고급진 향'),
    ('f3000000-0000-0000-0000-000000000006', 'f2000000-0000-0000-0000-000000000001', 'C4ANG 향수 전문점', 'f1000000-0000-0000-0000-000000000003', '톰 포드 오드 우드 오 드 퍼퓸', 'ON_SALE', 249000.00, 45, '청량한 소나무 계열의 향과 부드러운 우디 향수'),
    ('f3000000-0000-0000-0000-000000000007', 'f2000000-0000-0000-0000-000000000001', 'C4ANG 향수 전문점', 'f1000000-0000-0000-0000-000000000003', '블루 드 샤넬 오 드 퍼퓸', 'ON_SALE', 185000.00, 90, '자유로운 남성을 위한 우디 아로마틱 향수'),
    -- 유니섹스 향수
    ('f3000000-0000-0000-0000-000000000008', 'f2000000-0000-0000-0000-000000000001', 'C4ANG 향수 전문점', 'f1000000-0000-0000-0000-000000000004', '조말론 라임 바질 앤 만다린', 'ON_SALE', 195000.00, 120, '상쾌한 시트러스 향이 특징인 여름 향수'),
    ('f3000000-0000-0000-0000-000000000009', 'f2000000-0000-0000-0000-000000000001', 'C4ANG 향수 전문점', 'f1000000-0000-0000-0000-000000000004', '이솝 테싯 오 드 퍼퓸', 'ON_SALE', 135000.00, 60, '따뜻하고 생기넘치며 마음을 릴렉싱 시켜주는 향'),
    ('f3000000-0000-0000-0000-000000000010', 'f2000000-0000-0000-0000-000000000001', 'C4ANG 향수 전문점', 'f1000000-0000-0000-0000-000000000004', '르 라보 상탈 33 오 드 퍼퓸', 'ON_SALE', 320000.00, 25, '샌달우드 베이스의 중독적인 유니섹스 향수')
ON CONFLICT (id) DO NOTHING;

-- =====================================================
-- 4. 향수(Perfume) 특화 데이터 - 10개 샘플
-- product_id는 위 p_product의 id를 논리적 FK로 참조
-- 노트 데이터는 영어로 저장 (API 응답에서 NoteTranslator로 한국어 변환)
-- =====================================================
INSERT INTO p_perfume (id, product_id, brand, name, concentration, main_accords, top_notes, middle_notes, base_notes, notes_score, season_score, day_night_score, gender, sizes, detail_url) VALUES
    -- 1. 크리드 어벤투스 포 허
    (
        'f4000000-0000-0000-0000-000000000001',
        'f3000000-0000-0000-0000-000000000001',
        'Creed',
        'Aventus for Her',
        'Eau de Parfum',
        '["Floral", "Fruity", "Musky"]',
        '["Green Apple", "Pink Pepper", "Bergamot", "Lemon"]',
        '["Rose", "Peach", "Styrax", "Ylang-Ylang"]',
        '["Musk", "Sandalwood", "Amber"]',
        '{"floral": 85.0, "fruity": 72.0, "musky": 65.0, "fresh": 58.0}',
        '{"spring": 75.0, "summer": 60.0, "fall": 45.0, "winter": 30.0}',
        '{"day": 80.0, "night": 50.0}',
        'Female',
        '[{"sizeMl": 50, "price": 255000}, {"sizeMl": 75, "price": 340000}]',
        'https://www.bysuco.com/product/show/creed-aventus-for-her'
    ),
    -- 2. 디올 미스 디올
    (
        'f4000000-0000-0000-0000-000000000002',
        'f3000000-0000-0000-0000-000000000002',
        'Dior',
        'Miss Dior',
        'Eau de Parfum',
        '["Floral", "Rose", "Powdery"]',
        '["Mandarin Orange", "Bergamot"]',
        '["Rose", "Peony", "Lily of the Valley"]',
        '["Musk", "Sandalwood", "Patchouli"]',
        '{"floral": 95.0, "rose": 88.0, "powdery": 70.0, "fresh": 55.0}',
        '{"spring": 35.0, "summer": 10.0, "fall": 40.0, "winter": 15.0}',
        '{"day": 70.0, "night": 30.0}',
        'Female',
        '[{"sizeMl": 30, "price": 120000}, {"sizeMl": 50, "price": 180000}, {"sizeMl": 100, "price": 280000}]',
        'https://www.bysuco.com/product/show/dior-miss-dior'
    ),
    -- 3. 샤넬 코코 마드모아젤
    (
        'f4000000-0000-0000-0000-000000000003',
        'f3000000-0000-0000-0000-000000000003',
        'Chanel',
        'Coco Mademoiselle',
        'Eau de Parfum',
        '["Floral", "Citrus", "Fresh"]',
        '["Orange", "Bergamot", "Grapefruit"]',
        '["Rose", "Jasmine", "Lychee"]',
        '["Vanilla", "Musk", "Vetiver", "Patchouli"]',
        '{"floral": 80.0, "citrus": 75.0, "fresh": 70.0, "sweet": 55.0}',
        '{"spring": 60.0, "summer": 55.0, "fall": 50.0, "winter": 35.0}',
        '{"day": 75.0, "night": 55.0}',
        'Female',
        '[{"sizeMl": 50, "price": 200000}, {"sizeMl": 100, "price": 320000}]',
        'https://www.bysuco.com/product/show/chanel-coco-mademoiselle'
    ),
    -- 4. 겔랑 랭스땅 드 겔랑
    (
        'f4000000-0000-0000-0000-000000000004',
        'f3000000-0000-0000-0000-000000000004',
        'Guerlain',
        'L''Instant de Guerlain',
        'Eau de Parfum',
        '["Floral", "Honey", "Sweet"]',
        '["Orange", "Honey", "Bergamot", "Mandarin Orange"]',
        '["Ylang-Ylang", "Magnolia", "Jasmine"]',
        '["Amber", "Sandalwood"]',
        '{"floral": 90.0, "honey": 82.0, "sweet": 78.0, "woody": 60.0}',
        '{"spring": 24.1, "summer": 3.8, "fall": 95.5, "winter": 14.2}',
        '{"day": 47.1, "night": 25.9}',
        'Female',
        '[{"sizeMl": 75, "price": 195000}]',
        'https://www.bysuco.com/product/show/22689'
    ),
    -- 5. 크리드 어벤투스 (남성)
    (
        'f4000000-0000-0000-0000-000000000005',
        'f3000000-0000-0000-0000-000000000005',
        'Creed',
        'Aventus',
        'Eau de Parfum',
        '["Fruity", "Sweet", "Leather"]',
        '["Bergamot", "Black Currant", "Apple", "Lemon", "Pink Pepper"]',
        '["Pineapple", "Patchouli", "Jasmine"]',
        '["Birch", "Musk", "Oak Moss", "Ambroxan", "Cedar"]',
        '{"fruity": 88.0, "sweet": 75.0, "leather": 68.0, "woody": 72.0}',
        '{"spring": 65.0, "summer": 70.0, "fall": 55.0, "winter": 40.0}',
        '{"day": 85.0, "night": 60.0}',
        'Male',
        '[{"sizeMl": 50, "price": 255000}, {"sizeMl": 100, "price": 399000}]',
        'https://www.bysuco.com/product/show/9370'
    ),
    -- 6. 톰 포드 오드 우드
    (
        'f4000000-0000-0000-0000-000000000006',
        'f3000000-0000-0000-0000-000000000006',
        'Tom Ford',
        'Oud Wood',
        'Eau de Parfum',
        '["Woody", "Oud", "Warm Spicy"]',
        '["Cardamom", "Sichuan Pepper"]',
        '["Oud", "Sandalwood", "Rosewood"]',
        '["Vetiver", "Tonka Bean", "Amber", "Vanilla"]',
        '{"woody": 95.0, "oud": 88.0, "warm_spicy": 72.0, "smoky": 60.0}',
        '{"spring": 20.0, "summer": 10.0, "fall": 75.0, "winter": 90.0}',
        '{"day": 35.0, "night": 90.0}',
        'Male',
        '[{"sizeMl": 30, "price": 179000}, {"sizeMl": 50, "price": 249000}, {"sizeMl": 100, "price": 399000}]',
        'https://www.bysuco.com/product/show/10716'
    ),
    -- 7. 블루 드 샤넬
    (
        'f4000000-0000-0000-0000-000000000007',
        'f3000000-0000-0000-0000-000000000007',
        'Chanel',
        'Bleu de Chanel',
        'Eau de Parfum',
        '["Woody", "Aromatic", "Fresh Spicy"]',
        '["Lemon", "Mint", "Pink Pepper", "Grapefruit"]',
        '["Ginger", "Nutmeg", "Jasmine", "Iso E Super"]',
        '["Sandalwood", "Cedar", "Vetiver", "Incense"]',
        '{"woody": 85.0, "aromatic": 78.0, "fresh_spicy": 72.0, "citrus": 65.0}',
        '{"spring": 55.0, "summer": 50.0, "fall": 60.0, "winter": 55.0}',
        '{"day": 80.0, "night": 65.0}',
        'Male',
        '[{"sizeMl": 50, "price": 145000}, {"sizeMl": 100, "price": 185000}, {"sizeMl": 150, "price": 225000}]',
        'https://www.bysuco.com/product/show/bleu-de-chanel'
    ),
    -- 8. 조말론 라임 바질 앤 만다린 (유니섹스)
    (
        'f4000000-0000-0000-0000-000000000008',
        'f3000000-0000-0000-0000-000000000008',
        'Jo Malone',
        'Lime Basil & Mandarin',
        'Eau de Cologne',
        '["Citrus", "Aromatic", "Green"]',
        '["Lime", "Mandarin Orange", "Bergamot"]',
        '["Basil", "Thyme", "Lilac"]',
        '["Vetiver", "Ambergris"]',
        '{"citrus": 92.0, "aromatic": 80.0, "green": 75.0, "fresh": 88.0}',
        '{"spring": 70.0, "summer": 90.0, "fall": 40.0, "winter": 25.0}',
        '{"day": 95.0, "night": 35.0}',
        'Unisex',
        '[{"sizeMl": 30, "price": 95000}, {"sizeMl": 100, "price": 195000}]',
        'https://www.bysuco.com/product/show/jo-malone-lime-basil'
    ),
    -- 9. 이솝 테싯
    (
        'f4000000-0000-0000-0000-000000000009',
        'f3000000-0000-0000-0000-000000000009',
        'Aesop',
        'Tacit',
        'Eau de Parfum',
        '["Citrus", "Aromatic", "Fresh Spicy"]',
        '["Yuzu", "Citrus"]',
        '["Basil"]',
        '["Vetiver", "Clove"]',
        '{"citrus": 85.0, "aromatic": 78.0, "fresh_spicy": 70.0, "green": 65.0}',
        '{"spring": 60.0, "summer": 75.0, "fall": 50.0, "winter": 35.0}',
        '{"day": 85.0, "night": 40.0}',
        'Unisex',
        '[{"sizeMl": 50, "price": 135000}]',
        'https://www.bysuco.com/product/show/9970'
    ),
    -- 10. 르 라보 상탈 33
    (
        'f4000000-0000-0000-0000-000000000010',
        'f3000000-0000-0000-0000-000000000010',
        'Le Labo',
        'Santal 33',
        'Eau de Parfum',
        '["Woody", "Leather", "Aromatic"]',
        '["Cardamom", "Iris", "Violet"]',
        '["Ambrox", "Iso E Super", "Australian Sandalwood"]',
        '["Cedarwood", "Leather", "Musk"]',
        '{"woody": 98.0, "leather": 85.0, "aromatic": 72.0, "smoky": 68.0}',
        '{"spring": 45.0, "summer": 35.0, "fall": 70.0, "winter": 80.0}',
        '{"day": 60.0, "night": 80.0}',
        'Unisex',
        '[{"sizeMl": 50, "price": 270000}, {"sizeMl": 100, "price": 320000}]',
        'https://www.bysuco.com/product/show/le-labo-santal-33'
    )
ON CONFLICT (id) DO NOTHING;

-- =====================================================
-- 5. 노트 이미지 데이터 - 주요 노트 30개 샘플
-- =====================================================
INSERT INTO p_note_image (id, category, note_name, image_url) VALUES
    -- Citrus
    ('f5000000-0000-0000-0000-000000000001', 'Citrus Smells', 'Bergamot', 'https://fimgs.net/mdimg/sastojci/m.75.jpg'),
    ('f5000000-0000-0000-0000-000000000002', 'Citrus Smells', 'Lemon', 'https://fimgs.net/mdimg/sastojci/m.77.jpg'),
    ('f5000000-0000-0000-0000-000000000003', 'Citrus Smells', 'Lime', 'https://fimgs.net/mdimg/sastojci/m.78.jpg'),
    ('f5000000-0000-0000-0000-000000000004', 'Citrus Smells', 'Orange', 'https://fimgs.net/mdimg/sastojci/m.80.jpg'),
    ('f5000000-0000-0000-0000-000000000005', 'Citrus Smells', 'Mandarin Orange', 'https://fimgs.net/mdimg/sastojci/m.82.jpg'),
    ('f5000000-0000-0000-0000-000000000006', 'Citrus Smells', 'Grapefruit', 'https://fimgs.net/mdimg/sastojci/m.76.jpg'),
    ('f5000000-0000-0000-0000-000000000007', 'Citrus Smells', 'Yuzu', 'https://fimgs.net/mdimg/sastojci/m.83.jpg'),
    ('f5000000-0000-0000-0000-000000000008', 'Citrus Smells', 'Neroli', 'https://fimgs.net/mdimg/sastojci/m.17.jpg'),
    -- Flowers
    ('f5000000-0000-0000-0000-000000000009', 'Flowers', 'Rose', 'https://fimgs.net/mdimg/sastojci/m.4.jpg'),
    ('f5000000-0000-0000-0000-000000000010', 'Flowers', 'Jasmine', 'https://fimgs.net/mdimg/sastojci/m.21.jpg'),
    ('f5000000-0000-0000-0000-000000000011', 'Flowers', 'Peony', 'https://fimgs.net/mdimg/sastojci/m.30.jpg'),
    ('f5000000-0000-0000-0000-000000000012', 'Flowers', 'Ylang-Ylang', 'https://fimgs.net/mdimg/sastojci/m.15.jpg'),
    ('f5000000-0000-0000-0000-000000000013', 'Flowers', 'Lily of the Valley', 'https://fimgs.net/mdimg/sastojci/m.28.jpg'),
    ('f5000000-0000-0000-0000-000000000014', 'Flowers', 'Magnolia', 'https://fimgs.net/mdimg/sastojci/m.35.jpg'),
    ('f5000000-0000-0000-0000-000000000015', 'Flowers', 'Iris', 'https://fimgs.net/mdimg/sastojci/m.25.jpg'),
    ('f5000000-0000-0000-0000-000000000016', 'Flowers', 'Violet', 'https://fimgs.net/mdimg/sastojci/m.36.jpg'),
    -- Woods
    ('f5000000-0000-0000-0000-000000000017', 'Woods', 'Sandalwood', 'https://fimgs.net/mdimg/sastojci/m.249.jpg'),
    ('f5000000-0000-0000-0000-000000000018', 'Woods', 'Cedar', 'https://fimgs.net/mdimg/sastojci/m.250.jpg'),
    ('f5000000-0000-0000-0000-000000000019', 'Woods', 'Vetiver', 'https://fimgs.net/mdimg/sastojci/m.262.jpg'),
    ('f5000000-0000-0000-0000-000000000020', 'Woods', 'Oud', 'https://fimgs.net/mdimg/sastojci/m.269.jpg'),
    ('f5000000-0000-0000-0000-000000000021', 'Woods', 'Patchouli', 'https://fimgs.net/mdimg/sastojci/m.259.jpg'),
    ('f5000000-0000-0000-0000-000000000022', 'Woods', 'Birch', 'https://fimgs.net/mdimg/sastojci/m.251.jpg'),
    -- Spices
    ('f5000000-0000-0000-0000-000000000023', 'Spices', 'Cardamom', 'https://fimgs.net/mdimg/sastojci/m.181.jpg'),
    ('f5000000-0000-0000-0000-000000000024', 'Spices', 'Pink Pepper', 'https://fimgs.net/mdimg/sastojci/m.183.jpg'),
    ('f5000000-0000-0000-0000-000000000025', 'Spices', 'Clove', 'https://fimgs.net/mdimg/sastojci/m.186.jpg'),
    ('f5000000-0000-0000-0000-000000000026', 'Spices', 'Ginger', 'https://fimgs.net/mdimg/sastojci/m.189.jpg'),
    -- Musk & Others
    ('f5000000-0000-0000-0000-000000000027', 'Musks', 'Musk', 'https://fimgs.net/mdimg/sastojci/m.91.jpg'),
    ('f5000000-0000-0000-0000-000000000028', 'Musks', 'Amber', 'https://fimgs.net/mdimg/sastojci/m.294.jpg'),
    ('f5000000-0000-0000-0000-000000000029', 'Sweet', 'Vanilla', 'https://fimgs.net/mdimg/sastojci/m.55.jpg'),
    ('f5000000-0000-0000-0000-000000000030', 'Sweet', 'Tonka Bean', 'https://fimgs.net/mdimg/sastojci/m.194.jpg')
ON CONFLICT (category, note_name) DO NOTHING;

-- =====================================================
-- UUID 참조 가이드 (RAG 벡터DB 연동용)
-- =====================================================
--
-- [카테고리 ID] (f1 prefix)
-- f1000000-0000-0000-0000-000000000001 : 향수 (루트)
-- f1000000-0000-0000-0000-000000000002 : 여성 향수
-- f1000000-0000-0000-0000-000000000003 : 남성 향수
-- f1000000-0000-0000-0000-000000000004 : 유니섹스 향수
--
-- [스토어 ID] (f2 prefix)
-- f2000000-0000-0000-0000-000000000001 : C4ANG 향수 전문점
--
-- [제품(Product) ID] (f3 prefix) - 벡터DB에서 참조할 ID
-- f3000000-0000-0000-0000-000000000001 : 크리드 어벤투스 포 허 (Female)
-- f3000000-0000-0000-0000-000000000002 : 디올 미스 디올 (Female)
-- f3000000-0000-0000-0000-000000000003 : 샤넬 코코 마드모아젤 (Female)
-- f3000000-0000-0000-0000-000000000004 : 겔랑 랭스땅 드 겔랑 (Female)
-- f3000000-0000-0000-0000-000000000005 : 크리드 어벤투스 (Male)
-- f3000000-0000-0000-0000-000000000006 : 톰 포드 오드 우드 (Male)
-- f3000000-0000-0000-0000-000000000007 : 블루 드 샤넬 (Male)
-- f3000000-0000-0000-0000-000000000008 : 조말론 라임 바질 앤 만다린 (Unisex)
-- f3000000-0000-0000-0000-000000000009 : 이솝 테싯 (Unisex)
-- f3000000-0000-0000-0000-000000000010 : 르 라보 상탈 33 (Unisex)
--
-- [향수(Perfume) ID] (f4 prefix)
-- f4000000-0000-0000-0000-000000000001 ~ f4000000-0000-0000-0000-000000000010
--
-- [노트 이미지 ID] (f5 prefix)
-- f5000000-0000-0000-0000-000000000001 ~ f5000000-0000-0000-0000-000000000030
-- =====================================================