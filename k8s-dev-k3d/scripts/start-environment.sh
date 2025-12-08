#!/bin/bash

# E2E 테스트 환경 시작 스크립트
# 인프라 구성요소 (PostgreSQL, Redis) 배포

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K3D_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
KUBECONFIG_FILE="${K3D_DIR}/kubeconfig/config"
NAMESPACE="${NAMESPACE:-msa-quality}"

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# KUBECONFIG 설정
setup_kubeconfig() {
    if [ ! -f "${KUBECONFIG_FILE}" ]; then
        log_error "Kubeconfig 파일을 찾을 수 없습니다: ${KUBECONFIG_FILE}"
        log_info "먼저 install-k3s.sh를 실행하세요."
        exit 1
    fi
    export KUBECONFIG="${KUBECONFIG_FILE}"
    log_info "KUBECONFIG: ${KUBECONFIG_FILE}"
}

# PostgreSQL 배포
deploy_postgresql() {
    log_info "PostgreSQL 배포 중..."

    # Bitnami Helm 레포지토리 추가
    helm repo add bitnami https://charts.bitnami.com/bitnami 2>/dev/null || true
    helm repo update

    # PostgreSQL 배포 (customer-db)
    helm upgrade --install customer-db bitnami/postgresql \
        --namespace "${NAMESPACE}" \
        --create-namespace \
        --set auth.postgresPassword=postgres \
        --set auth.username=customer \
        --set auth.password=customer123 \
        --set auth.database=customer_db \
        --set primary.persistence.enabled=false \
        --wait \
        --timeout 300s

    log_info "PostgreSQL 배포 완료"
}

# Redis 배포
deploy_redis() {
    log_info "Redis 배포 중..."

    helm upgrade --install cache-redis bitnami/redis \
        --namespace "${NAMESPACE}" \
        --set auth.enabled=false \
        --set architecture=standalone \
        --set master.persistence.enabled=false \
        --wait \
        --timeout 300s

    log_info "Redis 배포 완료"
}

# 배포 상태 확인
verify_infrastructure() {
    log_info "인프라 상태 확인 중..."

    echo ""
    echo "=== Pod 상태 ==="
    kubectl get pods -n "${NAMESPACE}"

    echo ""
    echo "=== Service 상태 ==="
    kubectl get svc -n "${NAMESPACE}"

    echo ""
    log_info "인프라가 준비되었습니다!"
}

# 연결 정보 출력
show_connection_info() {
    echo ""
    echo "========================================"
    echo "인프라 연결 정보"
    echo "========================================"
    echo ""
    echo "PostgreSQL:"
    echo "  Host: customer-db-postgresql.${NAMESPACE}.svc.cluster.local"
    echo "  Port: 5432"
    echo "  Database: customer_db"
    echo "  Username: customer"
    echo "  Password: customer123"
    echo ""
    echo "Redis:"
    echo "  Host: cache-redis-master.${NAMESPACE}.svc.cluster.local"
    echo "  Port: 6379"
    echo ""
    echo "========================================"
}

# 메인 함수
main() {
    log_info "=== E2E 테스트 인프라 배포 시작 ==="

    setup_kubeconfig
    deploy_postgresql
    deploy_redis
    verify_infrastructure
    show_connection_info

    log_info "=== E2E 테스트 인프라 배포 완료 ==="
}

main "$@"
