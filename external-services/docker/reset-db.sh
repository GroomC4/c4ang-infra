#!/bin/bash
# =============================================================================
# DB 스키마 재초기화 스크립트
# 기존 볼륨을 삭제하고 init-scripts로 스키마를 재적용합니다.
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=== DB 스키마 재초기화 ===${NC}"
echo ""

# 특정 DB만 재초기화할 수 있는 옵션
TARGET_DB="${1:-all}"

DATABASES=("customer-db" "product-db" "order-db" "store-db" "saga-db" "payment-db")

reset_database() {
    local db_name=$1
    local volume_name="${db_name//-/_}-data"  # customer-db -> customer_db-data 형식으로 변환

    # docker-compose volume naming: directory_volumename
    local full_volume_name="docker_${volume_name}"

    echo -e "${YELLOW}Resetting ${db_name}...${NC}"

    # 컨테이너 중지
    docker-compose stop "$db_name" 2>/dev/null || true

    # 컨테이너 삭제
    docker-compose rm -f "$db_name" 2>/dev/null || true

    # 볼륨 삭제 (여러 이름 형식 시도)
    docker volume rm "${full_volume_name}" 2>/dev/null || \
    docker volume rm "docker_${db_name}-data" 2>/dev/null || \
    docker volume rm "${db_name}-data" 2>/dev/null || true

    echo -e "${GREEN}✓ ${db_name} volume removed${NC}"
}

if [ "$TARGET_DB" = "all" ]; then
    echo "모든 데이터베이스를 재초기화합니다."
    echo -e "${RED}주의: 기존 데이터가 모두 삭제됩니다!${NC}"
    read -p "계속하시겠습니까? (y/N): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo "취소되었습니다."
        exit 0
    fi

    # 모든 서비스 중지
    echo -e "${YELLOW}모든 서비스 중지 중...${NC}"
    docker-compose down -v 2>/dev/null || true

    echo -e "${GREEN}✓ 모든 볼륨 삭제 완료${NC}"
else
    # 특정 DB만 재초기화
    if [[ ! " ${DATABASES[@]} " =~ " ${TARGET_DB} " ]]; then
        echo -e "${RED}Error: Unknown database '${TARGET_DB}'${NC}"
        echo "Available databases: ${DATABASES[*]}"
        exit 1
    fi

    reset_database "$TARGET_DB"
fi

# 서비스 시작
echo ""
echo -e "${YELLOW}데이터베이스 서비스 시작 중...${NC}"

if [ "$TARGET_DB" = "all" ]; then
    docker-compose up -d customer-db product-db order-db store-db saga-db payment-db
else
    docker-compose up -d "$TARGET_DB"
fi

# 헬스체크 대기
echo ""
echo -e "${YELLOW}데이터베이스 준비 대기 중...${NC}"
sleep 5

# 헬스체크
for db in "${DATABASES[@]}"; do
    if [ "$TARGET_DB" = "all" ] || [ "$TARGET_DB" = "$db" ]; then
        if docker-compose exec -T "$db" pg_isready -U postgres > /dev/null 2>&1; then
            echo -e "${GREEN}✓ ${db} is ready${NC}"
        else
            echo -e "${RED}✗ ${db} is not ready${NC}"
        fi
    fi
done

echo ""
echo -e "${GREEN}=== DB 스키마 재초기화 완료 ===${NC}"
echo ""
echo "테이블 확인:"
echo "  docker-compose exec customer-db psql -U postgres -d customer_db -c '\\dt'"
echo "  docker-compose exec product-db psql -U postgres -d product_db -c '\\dt'"
