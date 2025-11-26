#!/bin/bash
# 모니터링 스택 배포 스크립트
# Prometheus, Grafana, Loki, Tempo 및 관련 대시보드 배포
#
# 사용법:
#   ./monitoring.sh                    # 전체 배포
#   ./monitoring.sh --status           # 상태 확인
#   ./monitoring.sh --port-forward     # 포트 포워딩 시작

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
CHARTS_DIR="${PROJECT_ROOT}/charts"
CONFIG_DIR="${PROJECT_ROOT}/config"

# 설정
MONITORING_NS="monitoring"

# 로그 함수
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 사전 체크
check_prerequisites() {
    log_info "사전 요구사항 확인 중..."

    command -v kubectl &> /dev/null || { log_error "kubectl이 필요합니다."; exit 1; }
    command -v helm &> /dev/null || { log_error "helm이 필요합니다."; exit 1; }
    kubectl cluster-info &> /dev/null || { log_error "클러스터에 연결할 수 없습니다."; exit 1; }

    log_success "사전 요구사항 확인 완료"
}

# 네임스페이스 생성
ensure_namespace() {
    if ! kubectl get namespace "$MONITORING_NS" &> /dev/null; then
        log_info "네임스페이스 생성: $MONITORING_NS"
        kubectl create namespace "$MONITORING_NS"
    fi
}

# Pod 대기 (kubectl wait 사용 - 더 효율적)
wait_for_pods() {
    local namespace=$1
    local selector=$2
    local timeout=${3:-120}  # 기본 120초

    log_info "Pod 준비 대기 중... (selector: $selector, timeout: ${timeout}s)"

    if kubectl wait --for=condition=ready pod -l "$selector" -n "$namespace" --timeout="${timeout}s" 2>/dev/null; then
        log_success "Pod 준비 완료"
        return 0
    else
        # Pod가 없거나 타임아웃
        local pod_count
        pod_count=$(kubectl get pods -n "$namespace" -l "$selector" --no-headers 2>/dev/null | wc -l | tr -d ' ') || true
        if [ "${pod_count:-0}" -eq 0 ]; then
            log_warn "해당 selector의 Pod가 없습니다: $selector"
        else
            log_warn "Pod 준비 타임아웃 (${timeout}s)"
        fi
        return 1
    fi
}

# 환경 감지
detect_environment() {
    if kubectl get nodes -o jsonpath='{.items[0].spec.providerID}' 2>/dev/null | grep -q "aws"; then
        echo "prod"
    else
        echo "local"
    fi
}

# 모니터링 스택 배포
deploy_monitoring() {
    log_info "=== 모니터링 스택 배포 ==="

    check_prerequisites
    ensure_namespace

    local env=$(detect_environment)
    local values_file="${CONFIG_DIR}/${env}/monitoring.yaml"

    if [ ! -d "${CHARTS_DIR}/monitoring" ]; then
        log_error "monitoring 차트를 찾을 수 없습니다: ${CHARTS_DIR}/monitoring"
        exit 1
    fi

    log_info "환경: $env"

    # Helm 배포
    local helm_args="--install monitoring ${CHARTS_DIR}/monitoring -n $MONITORING_NS --wait --timeout 10m"

    if [ -f "$values_file" ]; then
        log_info "Values 파일 사용: $values_file"
        helm_args="$helm_args -f $values_file"
    fi

    log_info "모니터링 스택 배포 중..."
    helm upgrade $helm_args

    # 컴포넌트 확인
    log_info "컴포넌트 상태 확인 중..."

    wait_for_pods "$MONITORING_NS" "app.kubernetes.io/component=prometheus" 120 || true
    wait_for_pods "$MONITORING_NS" "app.kubernetes.io/component=grafana" 120 || true

    log_success "=== 모니터링 스택 배포 완료 ==="
}

# Argo Rollouts 메트릭 서비스 배포
deploy_argo_rollouts_metrics() {
    log_info "=== Argo Rollouts 메트릭 서비스 배포 ==="

    # Argo Rollouts 설치 확인
    if ! kubectl get deployment -n argo-rollouts argo-rollouts &> /dev/null; then
        log_warn "Argo Rollouts가 설치되어 있지 않습니다. 건너뜁니다."
        return 0
    fi

    # 메트릭 서비스 생성
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: argo-rollouts-metrics
  namespace: argo-rollouts
  labels:
    app: argo-rollouts
spec:
  ports:
    - name: metrics
      port: 8090
      targetPort: 8090
      protocol: TCP
  selector:
    app.kubernetes.io/name: argo-rollouts
EOF

    log_success "Argo Rollouts 메트릭 서비스 배포 완료"
}

# 상태 확인
show_status() {
    echo ""
    log_info "=== 모니터링 상태 ==="
    echo ""

    echo "Monitoring Pods:"
    local pods
    pods=$(kubectl get pods -n "$MONITORING_NS" --no-headers 2>/dev/null) || true
    if [ -n "$pods" ]; then
        kubectl get pods -n "$MONITORING_NS" 2>/dev/null
    else
        echo "  없음"
    fi
    echo ""

    echo "Monitoring Services:"
    local svcs
    svcs=$(kubectl get svc -n "$MONITORING_NS" --no-headers 2>/dev/null) || true
    if [ -n "$svcs" ]; then
        kubectl get svc -n "$MONITORING_NS" 2>/dev/null
    else
        echo "  없음"
    fi
    echo ""

    echo "PVCs:"
    local pvcs
    pvcs=$(kubectl get pvc -n "$MONITORING_NS" --no-headers 2>/dev/null) || true
    if [ -n "$pvcs" ]; then
        kubectl get pvc -n "$MONITORING_NS" 2>/dev/null
    else
        echo "  없음"
    fi
}

# 포트 포워딩
start_port_forward() {
    log_info "=== 포트 포워딩 시작 ==="

    echo ""
    echo "다음 명령어로 각 서비스에 접근할 수 있습니다:"
    echo ""
    echo "  # Grafana (admin/admin)"
    echo "  kubectl port-forward -n $MONITORING_NS svc/grafana 3000:3000"
    echo ""
    echo "  # Prometheus"
    echo "  kubectl port-forward -n $MONITORING_NS svc/prometheus 9090:9090"
    echo ""

    read -p "Grafana 포트 포워딩을 시작할까요? (y/N): " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "Grafana 포트 포워딩 시작 (http://localhost:3000)"
        kubectl port-forward -n "$MONITORING_NS" svc/grafana 3000:3000
    fi
}

# 사용법
usage() {
    cat << EOF
사용법: $0 [옵션]

옵션:
  (없음)           모니터링 스택 배포
  --status         상태 확인만
  --port-forward   포트 포워딩 시작
  --help           도움말

예시:
  $0                    # 모니터링 스택 배포
  $0 --status           # 상태 확인
  $0 --port-forward     # 포트 포워딩

접속 정보:
  Grafana:    http://localhost:3000 (admin/admin)
  Prometheus: http://localhost:9090

EOF
}

# 메인
main() {
    local action="deploy"

    while [[ $# -gt 0 ]]; do
        case $1 in
            --status) action="status"; shift ;;
            --port-forward) action="port-forward"; shift ;;
            --help|-h) usage; exit 0 ;;
            *) log_error "알 수 없는 옵션: $1"; usage; exit 1 ;;
        esac
    done

    case $action in
        deploy)
            deploy_monitoring
            deploy_argo_rollouts_metrics
            show_status
            ;;
        status) show_status ;;
        port-forward) start_port_forward ;;
    esac
}

main "$@"
