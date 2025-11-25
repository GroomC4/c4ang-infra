#!/bin/bash

# Argo Rollouts 모니터링 스택 배포 스크립트 (k3d 로컬 환경)
#
# 이 스크립트는 다음을 수행합니다:
# 1. Argo Rollouts 메트릭 서비스 배포
# 2. Monitoring 스택 배포 (Prometheus, Grafana, Loki, Tempo)
# 3. 배포 상태 확인
# 4. 접속 정보 출력

set -euo pipefail

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 스크립트 디렉토리 및 프로젝트 루트
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_LOCAL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd "${ENV_LOCAL_DIR}/../.." && pwd)"
# 환경별 설정 경로
CONFIG_DIR="${PROJECT_ROOT}/config/local"
KUBECONFIG_FILE="${ENV_LOCAL_DIR}/kubeconfig/config"
# Helm 차트 경로
CHARTS_DIR="${PROJECT_ROOT}/charts"

# 로그 함수
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# kubeconfig 설정 확인
check_kubeconfig() {
    if [[ ! -f "${KUBECONFIG_FILE}" ]]; then
        log_error "kubeconfig 파일을 찾을 수 없습니다: ${KUBECONFIG_FILE}"
        log_error "먼저 k3d 클러스터를 생성하세요: ./install-k3s.sh"
        exit 1
    fi

    export KUBECONFIG="${KUBECONFIG_FILE}"
    log_info "KUBECONFIG 설정: ${KUBECONFIG}"
}

# kubectl 연결 확인
check_connection() {
    log_step "k3d 클러스터 연결 확인 중..."

    if ! kubectl cluster-info &> /dev/null; then
        log_error "k3d 클러스터에 연결할 수 없습니다."
        log_error "클러스터가 실행 중인지 확인하세요: k3d cluster list"
        exit 1
    fi

    local cluster_name
    cluster_name=$(kubectl config current-context 2>/dev/null || echo "unknown")
    log_success "클러스터 연결 성공: ${cluster_name}"
}

# Argo Rollouts 확인
check_argo_rollouts() {
    log_step "Argo Rollouts 설치 확인 중..."

    if ! kubectl get deployment -n argo-rollouts argo-rollouts &> /dev/null; then
        log_warn "Argo Rollouts가 설치되어 있지 않습니다."
        log_warn "메트릭을 수집하려면 Argo Rollouts를 먼저 설치해야 합니다."
        log_info "설치 명령어: helm install argo-rollouts argo/argo-rollouts --namespace argo-rollouts --create-namespace"

        read -p "계속 진행하시겠습니까? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "배포를 취소합니다."
            exit 0
        fi
    else
        log_success "Argo Rollouts 설치 확인됨"
    fi
}

# Argo Rollouts 메트릭 서비스 배포
deploy_argo_rollouts_monitoring() {
    log_step "Argo Rollouts 메트릭 서비스 배포 중..."

    helm upgrade --install argo-rollouts-monitoring \
        "${CHARTS_DIR}/argo-rollouts" \
        --namespace argo-rollouts \
        --create-namespace \
        --wait \
        --timeout 5m

    log_success "Argo Rollouts 메트릭 서비스 배포 완료"
}

# Monitoring 스택 배포
deploy_monitoring_stack() {
    log_step "Monitoring 스택 배포 중 (Prometheus, Grafana, Loki, Tempo)..."

    local values_file="${CONFIG_DIR}/monitoring.yaml"
    if [[ ! -f "${values_file}" ]]; then
        log_error "monitoring.yaml 파일을 찾을 수 없습니다: ${values_file}"
        exit 1
    fi
    log_info "설정 파일: ${values_file}"

    helm upgrade --install monitoring \
        "${CHARTS_DIR}/monitoring" \
        --namespace monitoring \
        --create-namespace \
        -f "${values_file}" \
        --wait \
        --timeout 10m

    log_success "Monitoring 스택 배포 완료"
}

# 배포 상태 확인
check_deployment_status() {
    log_step "배포 상태 확인 중..."

    echo ""
    echo -e "${CYAN}=== Argo Rollouts Namespace ===${NC}"
    kubectl get pods -n argo-rollouts

    echo ""
    echo -e "${CYAN}=== Monitoring Namespace ===${NC}"
    kubectl get pods -n monitoring

    echo ""
    echo -e "${CYAN}=== Services ===${NC}"
    kubectl get svc -n argo-rollouts
    kubectl get svc -n monitoring
}

# 접속 정보 출력
print_access_info() {
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  Argo Rollouts 모니터링 배포 완료!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "${CYAN}📊 Grafana 접속 방법:${NC}"
    echo -e "  1. Port-forward 실행:"
    echo -e "     ${YELLOW}kubectl port-forward -n monitoring svc/grafana 3000:3000${NC}"
    echo ""
    echo -e "  2. 브라우저에서 접속:"
    echo -e "     ${YELLOW}http://localhost:3000${NC}"
    echo ""
    echo -e "  3. 로그인 정보:"
    echo -e "     Username: ${YELLOW}admin${NC}"
    echo -e "     Password: ${YELLOW}admin${NC}"
    echo ""
    echo -e "  4. 대시보드 확인:"
    echo -e "     Dashboards > ${YELLOW}Argo Rollouts Monitoring${NC}"
    echo ""
    echo -e "${CYAN}📈 Prometheus 접속 방법:${NC}"
    echo -e "  1. Port-forward 실행:"
    echo -e "     ${YELLOW}kubectl port-forward -n monitoring svc/prometheus 9090:9090${NC}"
    echo ""
    echo -e "  2. 브라우저에서 접속:"
    echo -e "     ${YELLOW}http://localhost:9090${NC}"
    echo ""
    echo -e "  3. Target 확인:"
    echo -e "     Status > Targets > ${YELLOW}argo-rollouts${NC} job"
    echo ""
    echo -e "${CYAN}🔍 유용한 명령어:${NC}"
    echo -e "  # Pod 로그 확인"
    echo -e "  ${YELLOW}kubectl logs -n monitoring deployment/grafana${NC}"
    echo -e "  ${YELLOW}kubectl logs -n monitoring deployment/prometheus${NC}"
    echo ""
    echo -e "  # Pod 상태 모니터링"
    echo -e "  ${YELLOW}kubectl get pods -n monitoring -w${NC}"
    echo ""
    echo -e "  # 메트릭 엔드포인트 직접 확인"
    echo -e "  ${YELLOW}kubectl port-forward -n argo-rollouts deployment/argo-rollouts 8090:8090${NC}"
    echo -e "  ${YELLOW}curl http://localhost:8090/metrics${NC}"
    echo ""
}

# 메인 실행
main() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  Argo Rollouts 모니터링 배포 스크립트${NC}"
    echo -e "${BLUE}  k3d 로컬 환경용${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""

    check_kubeconfig
    check_connection
    check_argo_rollouts

    echo ""
    deploy_argo_rollouts_monitoring

    echo ""
    deploy_monitoring_stack

    echo ""
    check_deployment_status

    echo ""
    print_access_info
}

# 스크립트 실행
main "$@"
