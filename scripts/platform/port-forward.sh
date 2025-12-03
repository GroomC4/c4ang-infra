#!/bin/bash
# =============================================================================
# 포트포워딩 관리 스크립트
# =============================================================================
# 개발/운영 환경의 주요 서비스에 대한 포트포워딩을 관리합니다.
#
# 사용법:
#   ./port-forward.sh              # 모든 서비스 포트포워딩 시작
#   ./port-forward.sh --start      # 모든 서비스 포트포워딩 시작
#   ./port-forward.sh --stop       # 모든 포트포워딩 중지
#   ./port-forward.sh --status     # 포트포워딩 상태 확인
#   ./port-forward.sh --argocd     # ArgoCD만 포트포워딩
#   ./port-forward.sh --grafana    # Grafana만 포트포워딩
#   ./port-forward.sh --kafka-ui   # Kafka UI만 포트포워딩

set -euo pipefail

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 스크립트 경로
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# PID 파일 저장 디렉토리
PID_DIR="${PROJECT_ROOT}/.port-forward"

# 로그 함수
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# =============================================================================
# 포트포워딩 서비스 정의
# =============================================================================
# 형식: "서비스명:네임스페이스:서비스이름:로컬포트:원격포트"
declare -a SERVICES=(
    "argocd:argocd:argocd-server:8080:443"
    "grafana:monitoring:grafana:3000:3000"
    "prometheus:monitoring:prometheus-server:9090:80"
    "kafka-ui:kafka:kafka-ui:8088:8080"
    "argo-rollouts:argo-rollouts:argo-rollouts-dashboard:3100:3100"
)

# =============================================================================
# 유틸리티 함수
# =============================================================================

# PID 디렉토리 생성
ensure_pid_dir() {
    mkdir -p "$PID_DIR"
}

# 서비스가 존재하는지 확인
check_service_exists() {
    local namespace=$1
    local service=$2
    kubectl get svc "$service" -n "$namespace" &>/dev/null
}

# 포트가 사용 중인지 확인
check_port_in_use() {
    local port=$1
    lsof -i ":$port" &>/dev/null
}

# 단일 서비스 포트포워딩 시작
start_port_forward() {
    local name=$1
    local namespace=$2
    local service=$3
    local local_port=$4
    local remote_port=$5

    # 서비스 존재 확인
    if ! check_service_exists "$namespace" "$service"; then
        log_warn "$name: 서비스를 찾을 수 없음 ($namespace/$service)"
        return 0
    fi

    # 이미 실행 중인지 확인
    local pid_file="${PID_DIR}/${name}.pid"
    if [ -f "$pid_file" ]; then
        local pid
        pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
            log_warn "$name: 이미 실행 중 (PID: $pid, 포트: $local_port)"
            return 0
        else
            rm -f "$pid_file"
        fi
    fi

    # 포트 사용 중 확인
    if check_port_in_use "$local_port"; then
        log_warn "$name: 포트 $local_port 이미 사용 중"
        return 0
    fi

    # 포트포워딩 시작 (백그라운드)
    kubectl port-forward "svc/$service" "$local_port:$remote_port" -n "$namespace" &>/dev/null &
    local pid=$!
    echo "$pid" > "$pid_file"

    # 포트포워딩 시작 확인 (최대 3초 대기)
    local wait_count=0
    while [ $wait_count -lt 6 ]; do
        sleep 0.5
        if check_port_in_use "$local_port"; then
            log_success "$name: localhost:$local_port → $service:$remote_port"
            return 0
        fi
        ((wait_count++))
    done

    log_error "$name: 포트포워딩 시작 실패"
    rm -f "$pid_file"
    return 1
}

# 단일 서비스 포트포워딩 중지
stop_port_forward() {
    local name=$1
    local pid_file="${PID_DIR}/${name}.pid"

    if [ -f "$pid_file" ]; then
        local pid
        pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
            log_success "$name: 중지됨 (PID: $pid)"
        fi
        rm -f "$pid_file"
    fi
}

# =============================================================================
# 메인 기능
# =============================================================================

# 모든 서비스 포트포워딩 시작
start_all() {
    log_info "=== 포트포워딩 시작 ==="
    ensure_pid_dir

    for service_def in "${SERVICES[@]}"; do
        IFS=':' read -r name namespace service local_port remote_port <<< "$service_def"
        start_port_forward "$name" "$namespace" "$service" "$local_port" "$remote_port"
    done

    echo ""
    log_info "=== 접속 정보 ==="
    echo "  ArgoCD:         https://localhost:8080 (admin/admin123)"
    echo "  Grafana:        http://localhost:3000  (admin/admin)"
    echo "  Prometheus:     http://localhost:9090"
    echo "  Kafka UI:       http://localhost:8088"
    echo "  Argo Rollouts:  http://localhost:3100"
    echo ""
    log_info "포트포워딩 중지: $0 --stop"
}

# 모든 포트포워딩 중지
stop_all() {
    log_info "=== 포트포워딩 중지 ==="

    for service_def in "${SERVICES[@]}"; do
        IFS=':' read -r name _ _ _ _ <<< "$service_def"
        stop_port_forward "$name"
    done

    # 남아있는 kubectl port-forward 프로세스 정리
    pkill -f "kubectl port-forward" 2>/dev/null || true

    log_success "모든 포트포워딩 중지됨"
}

# 상태 확인
show_status() {
    log_info "=== 포트포워딩 상태 ==="
    echo ""

    printf "%-15s %-10s %-15s %s\n" "서비스" "상태" "포트" "PID"
    printf "%-15s %-10s %-15s %s\n" "-------" "------" "-------" "---"

    for service_def in "${SERVICES[@]}"; do
        IFS=':' read -r name namespace service local_port remote_port <<< "$service_def"
        local pid_file="${PID_DIR}/${name}.pid"
        local status="중지"
        local pid="-"

        if [ -f "$pid_file" ]; then
            pid=$(cat "$pid_file")
            if kill -0 "$pid" 2>/dev/null; then
                status="${GREEN}실행 중${NC}"
            else
                status="${RED}비정상${NC}"
                pid="-"
            fi
        fi

        printf "%-15s %-10b %-15s %s\n" "$name" "$status" "$local_port" "$pid"
    done

    echo ""
}

# 특정 서비스만 포트포워딩
start_single() {
    local target=$1
    ensure_pid_dir

    for service_def in "${SERVICES[@]}"; do
        IFS=':' read -r name namespace service local_port remote_port <<< "$service_def"
        if [ "$name" = "$target" ]; then
            start_port_forward "$name" "$namespace" "$service" "$local_port" "$remote_port"
            return 0
        fi
    done

    log_error "알 수 없는 서비스: $target"
    echo "사용 가능한 서비스: argocd, grafana, prometheus, kafka-ui, argo-rollouts"
    return 1
}

# 사용법
usage() {
    cat << EOF
사용법: $0 [옵션]

옵션:
  (없음), --start    모든 서비스 포트포워딩 시작
  --stop             모든 포트포워딩 중지
  --status           포트포워딩 상태 확인
  --argocd           ArgoCD만 포트포워딩
  --grafana          Grafana만 포트포워딩
  --prometheus       Prometheus만 포트포워딩
  --kafka-ui         Kafka UI만 포트포워딩
  --argo-rollouts    Argo Rollouts 대시보드만 포트포워딩
  --help             도움말

예시:
  $0                 # 모든 서비스 포트포워딩 시작
  $0 --status        # 상태 확인
  $0 --stop          # 모든 포트포워딩 중지
  $0 --argocd        # ArgoCD만 시작

EOF
}

# =============================================================================
# 메인
# =============================================================================
main() {
    local action="start"

    while [[ $# -gt 0 ]]; do
        case $1 in
            --start) action="start"; shift ;;
            --stop) action="stop"; shift ;;
            --status) action="status"; shift ;;
            --argocd) action="single"; target="argocd"; shift ;;
            --grafana) action="single"; target="grafana"; shift ;;
            --prometheus) action="single"; target="prometheus"; shift ;;
            --kafka-ui) action="single"; target="kafka-ui"; shift ;;
            --argo-rollouts) action="single"; target="argo-rollouts"; shift ;;
            --help|-h) usage; exit 0 ;;
            *) log_error "알 수 없는 옵션: $1"; usage; exit 1 ;;
        esac
    done

    case $action in
        start) start_all ;;
        stop) stop_all ;;
        status) show_status ;;
        single) start_single "$target" ;;
    esac
}

main "$@"
