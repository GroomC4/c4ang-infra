#!/bin/bash
# 외부 데이터 서비스 실행 스크립트
# k3d/EKS에서 ExternalName으로 접근할 DB, Redis, Kafka 서비스 실행
#
# 사용법:
#   ./start.sh              # 전체 서비스 실행
#   ./start.sh --ui         # Kafka UI 포함 실행
#   ./start.sh --db-only    # DB만 실행
#   ./start.sh --reset      # 볼륨 삭제 후 재시작 (스키마 재적용)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

# 사용법 출력
usage() {
    cat << EOF
사용법: $0 [옵션]

옵션:
  (없음)       전체 서비스 실행 (DB, Redis, Kafka, Schema Registry)
  --ui         Kafka UI 포함 실행
  --db-only    PostgreSQL DB만 실행
  --reset      볼륨 삭제 후 재시작 (스키마 재적용)
  --status     서비스 상태 확인
  --logs       서비스 로그 확인
  --help       도움말

서비스 목록:
  PostgreSQL: customer-db(5432), product-db(5433), order-db(5434),
              store-db(5435), saga-db(5436), payment-db(5437), recommendation-db(5438)
  Redis:      cache-redis(6379), session-redis(6380)
  Kafka:      kafka(9092,9094), schema-registry(8081)
  Optional:   kafka-ui(8080) - --ui 옵션 필요

EOF
}

# Docker 확인
check_docker() {
    if ! command -v docker &> /dev/null; then
        log_error "Docker가 설치되어 있지 않습니다."
        exit 1
    fi

    if ! docker info &> /dev/null; then
        log_error "Docker 데몬이 실행 중이지 않습니다."
        exit 1
    fi
}

# 서비스 실행
start_services() {
    local profile=""
    local services=""

    case "${1:-}" in
        --ui)
            profile="--profile ui"
            log_info "Kafka UI 포함 전체 서비스 실행"
            ;;
        --db-only)
            services="customer-db product-db order-db store-db saga-db payment-db recommendation-db"
            log_info "DB 서비스만 실행"
            ;;
        *)
            log_info "전체 서비스 실행"
            ;;
    esac

    log_step "docker-compose up 실행 중..."

    if [ -n "${services}" ]; then
        docker-compose up -d ${services}
    else
        docker-compose ${profile} up -d
    fi

    log_info "서비스 시작 완료"
    echo ""
    show_status
}

# 볼륨 삭제 후 재시작
reset_services() {
    log_warn "모든 데이터가 삭제됩니다!"
    read -p "계속하시겠습니까? (y/N): " -n 1 -r
    echo

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "취소되었습니다."
        exit 0
    fi

    log_step "서비스 중지 중..."
    docker-compose down -v

    log_step "서비스 재시작 중..."
    docker-compose up -d

    log_info "재시작 완료 (스키마 재적용됨)"
    echo ""
    show_status
}

# 상태 확인
show_status() {
    log_info "=== 서비스 상태 ==="
    docker-compose ps
    echo ""

    log_info "=== 포트 매핑 ==="
    echo "PostgreSQL:"
    echo "  - customer-db:       localhost:5432"
    echo "  - product-db:        localhost:5433"
    echo "  - order-db:          localhost:5434"
    echo "  - store-db:          localhost:5435"
    echo "  - saga-db:           localhost:5436"
    echo "  - payment-db:        localhost:5437"
    echo "  - recommendation-db: localhost:5438"
    echo ""
    echo "Redis:"
    echo "  - cache-redis:       localhost:6379"
    echo "  - session-redis:     localhost:6380"
    echo ""
    echo "Kafka:"
    echo "  - kafka:             localhost:9094 (외부), localhost:9092 (내부)"
    echo "  - schema-registry:   localhost:8081"
    echo "  - kafka-ui:          localhost:8080 (--ui 옵션 필요)"
}

# 로그 확인
show_logs() {
    local service="${2:-}"

    if [ -n "${service}" ]; then
        docker-compose logs -f "${service}"
    else
        docker-compose logs -f
    fi
}

# 메인
main() {
    check_docker

    case "${1:-}" in
        --help|-h)
            usage
            ;;
        --status)
            show_status
            ;;
        --logs)
            show_logs "$@"
            ;;
        --reset)
            reset_services
            ;;
        *)
            start_services "${1:-}"
            ;;
    esac
}

main "$@"
