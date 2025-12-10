#!/bin/bash
# Istio 서비스 메시 설치/제거 스크립트
#
# 사용법:
#   ./istio.sh                    # 설치 (sidecar 모드)
#   ./istio.sh --ambient          # 설치 (ambient 모드)
#   ./istio.sh --uninstall        # 제거
#   ./istio.sh --status           # 상태 확인
#   ./istio.sh --migrate-ambient  # sidecar → ambient 마이그레이션

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
ISTIO_NS="istio-system"
ISTIO_VERSION="${ISTIO_VERSION:-1.24.0}"  # Ambient 지원 버전
GATEWAY_API_VERSION="${GATEWAY_API_VERSION:-v1.2.0}"
ISTIO_MODE="${ISTIO_MODE:-sidecar}"  # sidecar 또는 ambient

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

# istioctl 설치 확인 및 설치
ensure_istioctl() {
    if command -v istioctl &> /dev/null; then
        log_info "istioctl 버전: $(istioctl version --short 2>/dev/null || echo 'unknown')"
        return 0
    fi

    log_info "istioctl 설치 중..."

    case "$(uname -s)" in
        Darwin)
            if command -v brew &> /dev/null; then
                brew install istioctl
            else
                curl -L https://istio.io/downloadIstio | ISTIO_VERSION=$ISTIO_VERSION sh -
                export PATH="$PWD/istio-$ISTIO_VERSION/bin:$PATH"
            fi
            ;;
        Linux)
            curl -L https://istio.io/downloadIstio | ISTIO_VERSION=$ISTIO_VERSION sh -
            export PATH="$PWD/istio-$ISTIO_VERSION/bin:$PATH"
            ;;
        *)
            log_error "지원하지 않는 OS입니다."
            exit 1
            ;;
    esac

    log_success "istioctl 설치 완료"
}

# Gateway API CRD 설치
install_gateway_api() {
    log_info "Gateway API CRD 설치 중... (버전: ${GATEWAY_API_VERSION})"

    # Gateway CRD 존재 확인
    if kubectl get crd gateways.gateway.networking.k8s.io &>/dev/null; then
        log_info "Gateway API CRDs가 이미 설치되어 있습니다."
        return 0
    fi

    # CRD 설치
    kubectl apply -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml"

    # CRD가 등록될 때까지 대기
    log_info "Gateway CRD 등록 대기 중..."
    kubectl wait --for=condition=established crd/gateways.gateway.networking.k8s.io --timeout=60s
    kubectl wait --for=condition=established crd/httproutes.gateway.networking.k8s.io --timeout=60s
    kubectl wait --for=condition=established crd/gatewayclasses.gateway.networking.k8s.io --timeout=60s

    log_success "Gateway API CRD 설치 완료"
}

# ecommerce 네임스페이스에 Istio sidecar injection 라벨 추가
setup_namespace_injection() {
    local namespace="${1:-ecommerce}"
    local mode="${2:-sidecar}"

    log_info "네임스페이스 '$namespace' 설정 중... (모드: $mode)"

    # 네임스페이스가 없으면 생성
    kubectl create namespace "$namespace" 2>/dev/null || true

    if [ "$mode" = "ambient" ]; then
        # Ambient 모드: sidecar injection 제거, ambient 레이블 추가
        kubectl label namespace "$namespace" istio-injection- --overwrite 2>/dev/null || true
        kubectl label namespace "$namespace" istio.io/dataplane-mode=ambient --overwrite
        log_success "네임스페이스 '$namespace' Ambient 모드 활성화됨"
    else
        # Sidecar 모드: 기존 방식
        kubectl label namespace "$namespace" istio.io/dataplane-mode- --overwrite 2>/dev/null || true
        kubectl label namespace "$namespace" istio-injection=enabled --overwrite
        log_success "네임스페이스 '$namespace' Sidecar injection 활성화됨"
    fi
}

# ztunnel 상태 확인
check_ztunnel() {
    log_info "ztunnel 상태 확인 중..."

    local ztunnel_pods
    ztunnel_pods=$(kubectl get pods -n "$ISTIO_NS" -l app=ztunnel --no-headers 2>/dev/null | wc -l | tr -d ' ')

    if [ "$ztunnel_pods" -gt 0 ]; then
        log_success "ztunnel DaemonSet 실행 중 ($ztunnel_pods pods)"
        kubectl get pods -n "$ISTIO_NS" -l app=ztunnel
        return 0
    else
        log_warn "ztunnel이 실행되지 않음"
        return 1
    fi
}

# Waypoint proxy 배포
deploy_waypoint() {
    local namespace="${1:-ecommerce}"
    local waypoint_name="${2:-ecommerce-waypoint}"

    log_info "Waypoint proxy 배포 중... (namespace: $namespace, name: $waypoint_name)"

    # istioctl을 사용하여 waypoint 생성
    if command -v istioctl &> /dev/null; then
        istioctl waypoint apply -n "$namespace" --name "$waypoint_name" --enroll-namespace
        log_success "Waypoint '$waypoint_name' 배포 완료"
    else
        log_error "istioctl이 필요합니다. waypoint 배포를 건너뜁니다."
        return 1
    fi
}

# Waypoint 삭제
delete_waypoint() {
    local namespace="${1:-ecommerce}"
    local waypoint_name="${2:-ecommerce-waypoint}"

    log_info "Waypoint proxy 삭제 중... (namespace: $namespace)"

    if command -v istioctl &> /dev/null; then
        istioctl waypoint delete -n "$namespace" --name "$waypoint_name" 2>/dev/null || true
        log_success "Waypoint '$waypoint_name' 삭제 완료"
    fi
}

# Istio CRD 설치 확인
verify_istio_crds() {
    log_info "Istio CRD 설치 확인 중..."

    local required_crds=(
        "virtualservices.networking.istio.io"
        "destinationrules.networking.istio.io"
        "authorizationpolicies.security.istio.io"
        "requestauthentications.security.istio.io"
        "peerauthentications.security.istio.io"
        "envoyfilters.networking.istio.io"
        "telemetries.telemetry.istio.io"
    )

    local missing_crds=()
    for crd in "${required_crds[@]}"; do
        if ! kubectl get crd "$crd" &>/dev/null; then
            missing_crds+=("$crd")
        fi
    done

    if [ ${#missing_crds[@]} -gt 0 ]; then
        log_error "누락된 Istio CRD: ${missing_crds[*]}"
        return 1
    fi

    log_success "모든 Istio CRD 설치 확인됨"
    return 0
}

# Istio 설치 (Sidecar 모드)
install_istio_sidecar() {
    log_info "=== Istio 설치 시작 (Sidecar 모드) ==="

    check_prerequisites
    ensure_istioctl

    # Gateway API CRD 먼저 설치
    install_gateway_api

    # 네임스페이스 생성
    kubectl create namespace "$ISTIO_NS" 2>/dev/null || true

    # Istio 설치 (minimal 프로필 사용)
    # - minimal: istiod + CRD만 설치
    # - Gateway는 Kubernetes Gateway API 사용 (ArgoCD Helm 차트가 관리)
    # - ingressgateway/egressgateway 설치 안함 (리소스 절약)
    log_info "Istio Control Plane 설치 중... (profile: minimal)"
    istioctl install --set profile=minimal -y

    # 설치 확인
    log_info "Istio Control Plane 배포 대기 중..."
    kubectl wait --for=condition=available --timeout=300s deployment/istiod -n "$ISTIO_NS"

    # Istio CRD 설치 확인
    verify_istio_crds

    # ecommerce 네임스페이스 sidecar injection 설정
    setup_namespace_injection "ecommerce" "sidecar"

    log_success "=== Istio Control Plane 설치 완료 (Sidecar 모드) ==="
    echo ""
    log_info "설치된 컴포넌트:"
    echo "  - istiod (Control Plane)"
    echo "  - Istio CRD (VirtualService, DestinationRule, AuthorizationPolicy 등)"
    echo "  - Gateway API CRD (Gateway, HTTPRoute)"
    echo ""
    log_info "ArgoCD가 관리하는 리소스:"
    echo "  - Gateway (Kubernetes Gateway API)"
    echo "  - HTTPRoute"
    echo "  - AuthorizationPolicy, RequestAuthentication"
    echo "  - VirtualService, DestinationRule (서비스별)"

    show_status
}

# Istio 설치 (Ambient 모드)
install_istio_ambient() {
    log_info "=== Istio 설치 시작 (Ambient 모드) ==="

    check_prerequisites
    ensure_istioctl

    # Gateway API CRD 먼저 설치
    install_gateway_api

    # 네임스페이스 생성
    kubectl create namespace "$ISTIO_NS" 2>/dev/null || true

    # Istio Ambient 모드 설치
    # - ambient: istiod + ztunnel (DaemonSet) + CNI
    # - Sidecar 없이 L4 mTLS 제공
    # - L7 기능 필요시 waypoint proxy 별도 배포
    log_info "Istio Control Plane 설치 중... (profile: ambient)"
    istioctl install --set profile=ambient -y

    # 설치 확인
    log_info "Istio Control Plane 배포 대기 중..."
    kubectl wait --for=condition=available --timeout=300s deployment/istiod -n "$ISTIO_NS"

    # ztunnel DaemonSet 대기
    log_info "ztunnel DaemonSet 배포 대기 중..."
    kubectl rollout status daemonset/ztunnel -n "$ISTIO_NS" --timeout=300s

    # Istio CRD 설치 확인
    verify_istio_crds

    # ecommerce 네임스페이스 ambient 모드 설정
    setup_namespace_injection "ecommerce" "ambient"

    # ztunnel 상태 확인
    check_ztunnel

    log_success "=== Istio Control Plane 설치 완료 (Ambient 모드) ==="
    echo ""
    log_info "설치된 컴포넌트:"
    echo "  - istiod (Control Plane)"
    echo "  - ztunnel (L4 proxy, DaemonSet)"
    echo "  - istio-cni (CNI plugin)"
    echo "  - Istio CRD (VirtualService, DestinationRule, AuthorizationPolicy 등)"
    echo "  - Gateway API CRD (Gateway, HTTPRoute)"
    echo ""
    log_info "리소스 절감 효과:"
    echo "  - Sidecar 없음 → Pod당 ~100MB 메모리 절약"
    echo "  - ztunnel: 노드당 ~50MB (공유)"
    echo ""
    log_info "L7 기능 사용 시:"
    echo "  - Waypoint proxy 배포: ./istio.sh --waypoint"
    echo ""
    log_info "ArgoCD가 관리하는 리소스:"
    echo "  - Gateway (Kubernetes Gateway API)"
    echo "  - HTTPRoute"
    echo "  - AuthorizationPolicy, RequestAuthentication"

    show_status
}

# Sidecar → Ambient 마이그레이션
migrate_to_ambient() {
    log_info "=== Sidecar → Ambient 마이그레이션 시작 ==="

    check_prerequisites
    ensure_istioctl

    # 현재 모드 확인
    local current_mode
    if kubectl get daemonset ztunnel -n "$ISTIO_NS" &>/dev/null; then
        log_info "이미 Ambient 모드가 설치되어 있습니다."
        current_mode="ambient"
    else
        current_mode="sidecar"
    fi

    if [ "$current_mode" = "ambient" ]; then
        log_warn "이미 Ambient 모드입니다. 네임스페이스 레이블만 확인합니다."
        setup_namespace_injection "ecommerce" "ambient"
        show_status
        return 0
    fi

    log_warn "주의: 이 작업은 서비스 재시작을 유발합니다."
    log_warn "서비스 중단 없이 마이그레이션하려면 각 서비스를 순차적으로 재시작하세요."
    echo ""
    read -p "계속하시겠습니까? (y/N) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "마이그레이션 취소됨"
        return 1
    fi

    # Istio를 Ambient 프로필로 업그레이드
    log_info "Istio를 Ambient 모드로 업그레이드 중..."
    istioctl install --set profile=ambient -y

    # ztunnel 대기
    log_info "ztunnel DaemonSet 배포 대기 중..."
    kubectl rollout status daemonset/ztunnel -n "$ISTIO_NS" --timeout=300s

    # 네임스페이스 레이블 변경
    setup_namespace_injection "ecommerce" "ambient"

    log_info "서비스 재시작 중... (Sidecar 제거를 위해)"
    kubectl rollout restart deployment -n ecommerce 2>/dev/null || true
    kubectl rollout restart rollout -n ecommerce 2>/dev/null || true

    log_success "=== 마이그레이션 완료 ==="
    log_info "각 서비스의 Pod에서 Sidecar가 제거되었는지 확인하세요:"
    echo "  kubectl get pods -n ecommerce"
    echo ""
    log_info "mTLS 연결 확인:"
    echo "  istioctl proxy-status"

    show_status
}

# Waypoint 배포 (L7 기능 필요시)
install_waypoint() {
    log_info "=== Waypoint Proxy 배포 ==="

    # Ambient 모드 확인
    if ! kubectl get daemonset ztunnel -n "$ISTIO_NS" &>/dev/null; then
        log_error "Ambient 모드가 설치되어 있지 않습니다."
        log_info "먼저 ./istio.sh --ambient 로 설치하세요."
        return 1
    fi

    deploy_waypoint "ecommerce" "ecommerce-waypoint"

    log_success "=== Waypoint 배포 완료 ==="
    log_info "Waypoint는 L7 기능을 제공합니다:"
    echo "  - JWT 인증 (서비스 내부)"
    echo "  - L7 AuthorizationPolicy"
    echo "  - Retry/Timeout"
    echo "  - Circuit Breaker"
}

# 기존 함수 (하위 호환성)
install_istio() {
    if [ "$ISTIO_MODE" = "ambient" ]; then
        install_istio_ambient
    else
        install_istio_sidecar
    fi
}

# Istio 제거
uninstall_istio() {
    log_info "=== Istio 제거 시작 ==="

    # Helm 릴리스 제거
    if helm list -n "$ISTIO_NS" 2>/dev/null | grep -q "istio-resources"; then
        log_info "Istio Helm 릴리스 제거 중..."
        helm uninstall istio-resources -n "$ISTIO_NS" || true
    fi

    # istioctl로 제거
    if command -v istioctl &> /dev/null; then
        log_info "Istio Control Plane 제거 중..."
        istioctl uninstall --purge -y || true
    fi

    # 네임스페이스 제거
    log_info "네임스페이스 제거 중..."
    kubectl delete namespace "$ISTIO_NS" --ignore-not-found=true

    log_success "=== Istio 제거 완료 ==="
}

# 상태 확인
show_status() {
    echo ""
    log_info "=== Istio 상태 ==="
    echo ""

    # 모드 확인
    echo "Istio Mode:"
    if kubectl get daemonset ztunnel -n "$ISTIO_NS" &>/dev/null; then
        echo "  🌐 Ambient Mode (Sidecar-less)"
    else
        echo "  📦 Sidecar Mode"
    fi
    echo ""

    echo "Istio Pods:"
    local pods
    pods=$(kubectl get pods -n "$ISTIO_NS" --no-headers 2>/dev/null) || true
    if [ -n "$pods" ]; then
        kubectl get pods -n "$ISTIO_NS" 2>/dev/null
    else
        echo "  없음"
    fi
    echo ""

    # Ambient 모드일 때 ztunnel 상태 표시
    if kubectl get daemonset ztunnel -n "$ISTIO_NS" &>/dev/null; then
        echo "ztunnel Status:"
        kubectl get daemonset ztunnel -n "$ISTIO_NS" 2>/dev/null
        echo ""

        echo "Waypoint Proxies:"
        local waypoints
        waypoints=$(kubectl get gateway -A -l istio.io/waypoint-for --no-headers 2>/dev/null) || true
        if [ -n "$waypoints" ]; then
            kubectl get gateway -A -l istio.io/waypoint-for 2>/dev/null
        else
            echo "  없음 (L7 기능 필요시 --waypoint 옵션으로 배포)"
        fi
        echo ""
    fi

    echo "Istio Services:"
    local svcs
    svcs=$(kubectl get svc -n "$ISTIO_NS" --no-headers 2>/dev/null) || true
    if [ -n "$svcs" ]; then
        kubectl get svc -n "$ISTIO_NS" 2>/dev/null
    else
        echo "  없음"
    fi
    echo ""

    echo "Istio CRDs:"
    local istio_crds
    istio_crds=$(kubectl get crd 2>/dev/null | grep -E "istio\.io" | wc -l | tr -d ' ')
    local gateway_crds
    gateway_crds=$(kubectl get crd 2>/dev/null | grep -E "gateway\.networking\.k8s\.io" | wc -l | tr -d ' ')
    echo "  Istio CRDs: ${istio_crds}개"
    echo "  Gateway API CRDs: ${gateway_crds}개"
    echo ""

    echo "Namespace Labels:"
    for ns in ecommerce monitoring; do
        local sidecar_label ambient_label
        sidecar_label=$(kubectl get namespace "$ns" -o jsonpath='{.metadata.labels.istio-injection}' 2>/dev/null) || sidecar_label=""
        ambient_label=$(kubectl get namespace "$ns" -o jsonpath='{.metadata.labels.istio\.io/dataplane-mode}' 2>/dev/null) || ambient_label=""

        if [ -n "$ambient_label" ]; then
            echo "  $ns: 🌐 ambient"
        elif [ "$sidecar_label" = "enabled" ]; then
            echo "  $ns: 📦 sidecar-injection"
        else
            echo "  $ns: ❌ disabled (or namespace not found)"
        fi
    done
    echo ""

    echo "Gateway API Resources:"
    local gateways
    gateways=$(kubectl get gateways.gateway.networking.k8s.io -A --no-headers 2>/dev/null) || true
    if [ -n "$gateways" ]; then
        kubectl get gateways.gateway.networking.k8s.io -A 2>/dev/null
    else
        echo "  없음"
    fi
    echo ""

    if command -v istioctl &> /dev/null; then
        echo "Istio Version:"
        istioctl version 2>/dev/null || echo "  확인 불가"
    fi
}

# 사용법
usage() {
    cat << EOF
사용법: $0 [옵션]

옵션:
  (없음)           Istio 설치 (Sidecar 모드)
  --ambient        Istio 설치 (Ambient 모드) - 리소스 절약
  --migrate-ambient  Sidecar → Ambient 마이그레이션
  --waypoint       Waypoint proxy 배포 (L7 기능용, Ambient 모드 전용)
  --uninstall      Istio 제거
  --status         상태 확인만
  --help           도움말

예시:
  $0                    # Istio Sidecar 모드 설치
  $0 --ambient          # Istio Ambient 모드 설치 (권장)
  $0 --migrate-ambient  # 기존 Sidecar에서 Ambient로 전환
  $0 --waypoint         # L7 기능용 Waypoint 배포
  $0 --uninstall        # Istio 제거
  $0 --status           # 상태 확인

환경 변수:
  ISTIO_VERSION         Istio 버전 (기본: 1.24.0)
  GATEWAY_API_VERSION   Gateway API 버전 (기본: v1.2.0)
  ISTIO_MODE            설치 모드 (sidecar 또는 ambient)

Ambient 모드 장점:
  - Pod당 ~100MB 메모리 절약 (Sidecar 없음)
  - Pod 시작 시간 단축
  - 운영 단순화

EOF
}

# 메인
main() {
    local action="install"

    while [[ $# -gt 0 ]]; do
        case $1 in
            --ambient) action="ambient"; shift ;;
            --migrate-ambient) action="migrate"; shift ;;
            --waypoint) action="waypoint"; shift ;;
            --uninstall) action="uninstall"; shift ;;
            --status) action="status"; shift ;;
            --help|-h) usage; exit 0 ;;
            *) log_error "알 수 없는 옵션: $1"; usage; exit 1 ;;
        esac
    done

    case $action in
        install) install_istio_sidecar ;;
        ambient) install_istio_ambient ;;
        migrate) migrate_to_ambient ;;
        waypoint) install_waypoint ;;
        uninstall) uninstall_istio ;;
        status) show_status ;;
    esac
}

main "$@"
