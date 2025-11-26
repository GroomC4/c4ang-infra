#!/bin/bash
# =============================================================================
# 로컬 개발 환경 전체 초기화 스크립트
# =============================================================================
#
# 전체 플로우:
#   1. External Services 시작 (Docker Compose)
#   2. K3D 클러스터 생성/시작
#   3. ArgoCD Bootstrap (App of Apps)
#
# 사용법:
#   ./local.sh              # 전체 환경 초기화
#   ./local.sh --up         # 환경 시작 (이미 초기화된 경우)
#   ./local.sh --down       # 환경 중지
#   ./local.sh --destroy    # 환경 완전 삭제
#   ./local.sh --status     # 상태 확인
#   ./local.sh --help       # 도움말

set -euo pipefail

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 스크립트 경로
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# 설정
CLUSTER_NAME="${CLUSTER_NAME:-msa-quality-cluster}"
KUBECONFIG_DIR="${PROJECT_ROOT}/k8s-dev-k3d/kubeconfig"
KUBECONFIG_FILE="${KUBECONFIG_DIR}/config"
EXTERNAL_SERVICES_DIR="${PROJECT_ROOT}/external-services/local"
NAMESPACE="ecommerce"

# 로그 함수
log_header() { echo -e "\n${CYAN}========================================${NC}"; echo -e "${CYAN}  $1${NC}"; echo -e "${CYAN}========================================${NC}\n"; }
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "\n${GREEN}▶${NC} $1"; }

# =============================================================================
# Phase 1: External Services (Docker Compose)
# =============================================================================

start_external_services() {
    log_step "Phase 1: External Services 시작 (PostgreSQL, Redis, Kafka)"

    if [ ! -d "${EXTERNAL_SERVICES_DIR}" ]; then
        log_error "External services 디렉토리를 찾을 수 없습니다: ${EXTERNAL_SERVICES_DIR}"
        exit 1
    fi

    cd "${EXTERNAL_SERVICES_DIR}"

    # .env 파일 확인
    if [ ! -f ".env" ] && [ -f ".env.example" ]; then
        log_info ".env 파일 생성 중..."
        cp .env.example .env
    fi

    # Docker Compose 실행
    log_info "Docker Compose 서비스 시작 중..."
    docker-compose up -d

    # 헬스체크 대기
    log_info "서비스 헬스체크 대기 중..."
    local max_wait=60
    local waited=0

    while [ $waited -lt $max_wait ]; do
        local healthy_count
        healthy_count=$(docker-compose ps --format json 2>/dev/null | grep -c '"Health":"healthy"' || echo "0")
        local total_count
        total_count=$(docker-compose ps -q 2>/dev/null | wc -l | tr -d ' ')

        # 최소 5개 서비스가 healthy이면 통과 (PostgreSQL 5개)
        if [ "$healthy_count" -ge 5 ]; then
            log_success "External Services 준비 완료 (${healthy_count}/${total_count} healthy)"
            break
        fi

        sleep 5
        waited=$((waited + 5))
        log_info "대기 중... (${waited}s/${max_wait}s, ${healthy_count}/${total_count} healthy)"
    done

    if [ $waited -ge $max_wait ]; then
        log_warn "일부 서비스가 아직 시작 중일 수 있습니다."
        docker-compose ps
    fi

    cd "${PROJECT_ROOT}"
}

stop_external_services() {
    log_step "External Services 중지"

    if [ -d "${EXTERNAL_SERVICES_DIR}" ]; then
        cd "${EXTERNAL_SERVICES_DIR}"
        docker-compose down
        cd "${PROJECT_ROOT}"
        log_success "External Services 중지됨"
    fi
}

destroy_external_services() {
    log_step "External Services 삭제 (볼륨 포함)"

    if [ -d "${EXTERNAL_SERVICES_DIR}" ]; then
        cd "${EXTERNAL_SERVICES_DIR}"
        docker-compose down -v
        cd "${PROJECT_ROOT}"
        log_success "External Services 삭제됨"
    fi
}

# =============================================================================
# Phase 2: K3D Cluster
# =============================================================================

start_cluster() {
    log_step "Phase 2: K3D 클러스터 시작"

    # kubeconfig 디렉토리 생성
    mkdir -p "${KUBECONFIG_DIR}"

    # 클러스터 존재 확인
    if ! k3d cluster list 2>/dev/null | grep -q "^${CLUSTER_NAME}"; then
        log_info "클러스터가 존재하지 않습니다. 생성합니다..."
        create_cluster
    else
        # 클러스터 시작
        log_info "기존 클러스터 시작 중..."
        k3d cluster start "${CLUSTER_NAME}" 2>/dev/null || true

        # kubeconfig 업데이트
        k3d kubeconfig write "${CLUSTER_NAME}" --output "${KUBECONFIG_FILE}"
    fi

    export KUBECONFIG="${KUBECONFIG_FILE}"

    # 클러스터 연결 확인
    local retry=0
    while [ $retry -lt 10 ]; do
        if kubectl cluster-info &>/dev/null; then
            log_success "클러스터 연결 성공"
            break
        fi
        retry=$((retry + 1))
        sleep 2
    done

    if [ $retry -ge 10 ]; then
        log_error "클러스터에 연결할 수 없습니다."
        exit 1
    fi

    # 네임스페이스 생성
    kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
    log_success "네임스페이스 준비 완료: ${NAMESPACE}"
}

create_cluster() {
    log_info "K3D 클러스터 생성 중..."

    k3d cluster create "${CLUSTER_NAME}" \
        --api-port 6443 \
        --port "80:80@loadbalancer" \
        --port "443:443@loadbalancer" \
        --port "30000-30100:30000-30100@server:0" \
        --k3s-arg "--disable=traefik@server:0" \
        --wait \
        --timeout 300s

    # kubeconfig 저장
    k3d kubeconfig write "${CLUSTER_NAME}" --output "${KUBECONFIG_FILE}"
    log_success "클러스터 생성 완료"
}

stop_cluster() {
    log_step "K3D 클러스터 중지"

    if k3d cluster list 2>/dev/null | grep -q "^${CLUSTER_NAME}"; then
        k3d cluster stop "${CLUSTER_NAME}"
        log_success "클러스터 중지됨"
    else
        log_info "클러스터가 존재하지 않습니다."
    fi
}

destroy_cluster() {
    log_step "K3D 클러스터 삭제"

    if k3d cluster list 2>/dev/null | grep -q "^${CLUSTER_NAME}"; then
        k3d cluster delete "${CLUSTER_NAME}"
        log_success "클러스터 삭제됨"
    else
        log_info "클러스터가 존재하지 않습니다."
    fi

    # kubeconfig 정리
    rm -f "${KUBECONFIG_FILE}"
}

# =============================================================================
# Phase 3: ArgoCD Bootstrap
# =============================================================================

bootstrap_argocd() {
    log_step "Phase 3: ArgoCD Bootstrap (App of Apps)"

    export KUBECONFIG="${KUBECONFIG_FILE}"

    # ArgoCD 스크립트 실행
    local argocd_script="${PROJECT_ROOT}/scripts/platform/argocd.sh"

    if [ -f "${argocd_script}" ]; then
        bash "${argocd_script}"
    else
        log_error "ArgoCD 스크립트를 찾을 수 없습니다: ${argocd_script}"
        exit 1
    fi

    log_success "ArgoCD Bootstrap 완료"
}

# =============================================================================
# Status
# =============================================================================

show_status() {
    log_header "로컬 환경 상태"

    # External Services
    echo -e "${CYAN}[External Services]${NC}"
    if [ -d "${EXTERNAL_SERVICES_DIR}" ]; then
        cd "${EXTERNAL_SERVICES_DIR}"
        if docker-compose ps -q 2>/dev/null | head -1 | grep -q .; then
            docker-compose ps
        else
            echo "  중지됨"
        fi
        cd "${PROJECT_ROOT}"
    else
        echo "  디렉토리 없음"
    fi
    echo ""

    # K3D Cluster
    echo -e "${CYAN}[K3D Cluster]${NC}"
    if k3d cluster list 2>/dev/null | grep -q "^${CLUSTER_NAME}"; then
        k3d cluster list | grep "^${CLUSTER_NAME}"
    else
        echo "  클러스터 없음"
    fi
    echo ""

    # Kubernetes Resources
    if [ -f "${KUBECONFIG_FILE}" ]; then
        export KUBECONFIG="${KUBECONFIG_FILE}"

        if kubectl cluster-info &>/dev/null; then
            echo -e "${CYAN}[Kubernetes Nodes]${NC}"
            kubectl get nodes 2>/dev/null || echo "  연결 불가"
            echo ""

            echo -e "${CYAN}[ArgoCD]${NC}"
            if kubectl get namespace argocd &>/dev/null; then
                kubectl get pods -n argocd --no-headers 2>/dev/null | head -5 || echo "  Pod 없음"
            else
                echo "  미설치"
            fi
            echo ""

            echo -e "${CYAN}[Applications]${NC}"
            kubectl get applications -n argocd --no-headers 2>/dev/null || echo "  없음"
            echo ""

            echo -e "${CYAN}[ecommerce Namespace]${NC}"
            if kubectl get namespace "${NAMESPACE}" &>/dev/null; then
                kubectl get pods -n "${NAMESPACE}" --no-headers 2>/dev/null | head -10 || echo "  Pod 없음"
            else
                echo "  네임스페이스 없음"
            fi
        else
            echo "  클러스터 연결 불가"
        fi
    else
        echo "  kubeconfig 없음"
    fi
    echo ""

    # 접속 정보
    echo -e "${CYAN}[접속 정보]${NC}"
    echo "  KUBECONFIG: export KUBECONFIG=${KUBECONFIG_FILE}"
    echo ""
    echo "  External Services:"
    echo "    - PostgreSQL: localhost:5432-5436"
    echo "    - Redis: localhost:6379-6380"
    echo "    - Kafka: localhost:9092, 9094"
    echo "    - Kafka UI: http://localhost:8080 (--profile ui)"
    echo ""
    echo "  ArgoCD:"
    echo "    kubectl port-forward svc/argocd-server -n argocd 8080:443"
    echo "    https://localhost:8080"
}

# =============================================================================
# Main Actions
# =============================================================================

full_init() {
    log_header "로컬 개발 환경 전체 초기화"

    # Prerequisites check
    check_prerequisites

    # Phase 1: External Services
    start_external_services

    # Phase 2: K3D Cluster
    start_cluster

    # Phase 3: ArgoCD Bootstrap
    bootstrap_argocd

    log_header "초기화 완료"
    show_status
}

start_all() {
    log_header "로컬 환경 시작"
    check_prerequisites
    start_external_services
    start_cluster
    log_success "환경 시작 완료"
    show_status
}

stop_all() {
    log_header "로컬 환경 중지"
    stop_cluster
    stop_external_services
    log_success "환경 중지 완료"
}

destroy_all() {
    log_header "로컬 환경 완전 삭제"

    read -p "모든 데이터가 삭제됩니다. 계속하시겠습니까? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "취소되었습니다."
        exit 0
    fi

    destroy_cluster
    destroy_external_services
    log_success "환경 삭제 완료"
}

check_prerequisites() {
    log_info "사전 요구사항 확인 중..."

    local missing=()

    command -v docker &>/dev/null || missing+=("docker")
    command -v docker-compose &>/dev/null || missing+=("docker-compose")
    command -v k3d &>/dev/null || missing+=("k3d")
    command -v kubectl &>/dev/null || missing+=("kubectl")
    command -v helm &>/dev/null || missing+=("helm")

    if [ ${#missing[@]} -gt 0 ]; then
        log_error "다음 도구가 필요합니다: ${missing[*]}"
        echo ""
        echo "설치 방법 (macOS):"
        echo "  brew install docker docker-compose k3d kubectl helm"
        exit 1
    fi

    if ! docker info &>/dev/null; then
        log_error "Docker 데몬이 실행 중이지 않습니다."
        exit 1
    fi

    log_success "사전 요구사항 확인 완료"
}

usage() {
    cat << EOF
로컬 개발 환경 관리 스크립트

사용법: $0 [옵션]

옵션:
  (없음)          전체 환경 초기화 (최초 설정)
  --up            환경 시작 (이미 초기화된 경우)
  --down          환경 중지
  --destroy       환경 완전 삭제 (데이터 포함)
  --status        현재 상태 확인
  --help          도움말

전체 플로우:
  1. External Services (Docker Compose)
     - PostgreSQL (5개): customer, product, order, store, saga
     - Redis (2개): cache, session
     - Kafka (KRaft 모드)

  2. K3D Cluster
     - msa-quality-cluster 생성
     - Traefik 비활성화 (Istio 사용)

  3. ArgoCD Bootstrap
     - App of Apps 패턴
     - ApplicationSet으로 환경별 자동 배포

예시:
  $0                 # 처음 환경 구축
  $0 --up            # 환경 재시작
  $0 --status        # 상태 확인
  $0 --down          # 환경 중지 (데이터 유지)
  $0 --destroy       # 완전 삭제

환경 변수:
  CLUSTER_NAME      클러스터 이름 (기본: msa-quality-cluster)

EOF
}

# =============================================================================
# Main
# =============================================================================

main() {
    local action="init"

    while [[ $# -gt 0 ]]; do
        case $1 in
            --up|--start) action="start"; shift ;;
            --down|--stop) action="stop"; shift ;;
            --destroy) action="destroy"; shift ;;
            --status) action="status"; shift ;;
            --help|-h) usage; exit 0 ;;
            *) log_error "알 수 없는 옵션: $1"; usage; exit 1 ;;
        esac
    done

    case $action in
        init) full_init ;;
        start) start_all ;;
        stop) stop_all ;;
        destroy) destroy_all ;;
        status) show_status ;;
    esac
}

main "$@"
