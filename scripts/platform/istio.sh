#!/bin/bash
# Istio 서비스 메시 설치/제거 스크립트
#
# 사용법:
#   ./istio.sh                    # 설치 (Ambient 모드, 기본)
#   ./istio.sh --sidecar          # 설치 (Sidecar 모드)
#   ./istio.sh --uninstall        # 제거
#   ./istio.sh --status           # 상태 확인

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
ISTIO_VERSION="${ISTIO_VERSION:-1.28.0}"
GATEWAY_API_VERSION="${GATEWAY_API_VERSION:-v1.2.0}"
ISTIO_MODE="${ISTIO_MODE:-ambient}"  # ambient 또는 sidecar

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

# ecommerce 네임스페이스에 Istio 라벨 추가 (모드에 따라 다름)
setup_namespace_injection() {
    local namespace="${1:-ecommerce}"
    local mode="${2:-$ISTIO_MODE}"

    log_info "네임스페이스 '$namespace'에 Istio $mode 모드 라벨 추가 중..."

    # 네임스페이스가 없으면 생성
    kubectl create namespace "$namespace" 2>/dev/null || true

    if [ "$mode" = "ambient" ]; then
        # Ambient 모드: ztunnel(L4)이 mTLS 자동 처리, sidecar 없음
        kubectl label namespace "$namespace" istio-injection- 2>/dev/null || true
        kubectl label namespace "$namespace" istio.io/dataplane-mode=ambient --overwrite
        log_success "네임스페이스 '$namespace' Ambient 모드 활성화됨"
    else
        # Sidecar 모드: 각 Pod에 Envoy sidecar 주입
        kubectl label namespace "$namespace" istio.io/dataplane-mode- 2>/dev/null || true
        kubectl label namespace "$namespace" istio-injection=enabled --overwrite
        log_success "네임스페이스 '$namespace' Sidecar injection 활성화됨"
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

# Istio 설치
install_istio() {
    log_info "=== Istio 설치 시작 (모드: $ISTIO_MODE) ==="

    check_prerequisites
    ensure_istioctl

    # Gateway API CRD 먼저 설치
    install_gateway_api

    # 네임스페이스 생성
    kubectl create namespace "$ISTIO_NS" 2>/dev/null || true

    if [ "$ISTIO_MODE" = "ambient" ]; then
        # Ambient 프로필: istiod + ztunnel + istio-cni
        # - Sidecar 없이 L4 mTLS 자동 처리
        # - Gateway는 Kubernetes Gateway API 사용 (ArgoCD Helm 차트가 관리)
        log_info "Istio Control Plane 설치 중... (profile: ambient)"
        istioctl install --set profile=ambient -y

        # 설치 확인
        log_info "Istio Ambient 컴포넌트 배포 대기 중..."
        kubectl wait --for=condition=available --timeout=300s deployment/istiod -n "$ISTIO_NS" || true
        kubectl rollout status daemonset/ztunnel -n "$ISTIO_NS" --timeout=300s || true
        kubectl rollout status daemonset/istio-cni-node -n "$ISTIO_NS" --timeout=300s || true
    else
        # Minimal 프로필: istiod + CRD만 설치
        # - Sidecar injection 사용
        # - Gateway는 Kubernetes Gateway API 사용 (ArgoCD Helm 차트가 관리)
        log_info "Istio Control Plane 설치 중... (profile: minimal)"
        istioctl install --set profile=minimal -y

        # 설치 확인
        log_info "Istio Control Plane 배포 대기 중..."
        kubectl wait --for=condition=available --timeout=300s deployment/istiod -n "$ISTIO_NS"
    fi

    # Istio CRD 설치 확인
    verify_istio_crds

    # ecommerce 네임스페이스 설정
    setup_namespace_injection "ecommerce" "$ISTIO_MODE"

    log_success "=== Istio 설치 완료 (모드: $ISTIO_MODE) ==="
    echo ""
    if [ "$ISTIO_MODE" = "ambient" ]; then
        log_info "설치된 컴포넌트:"
        echo "  - istiod (Control Plane)"
        echo "  - ztunnel (L4 mTLS, DaemonSet)"
        echo "  - istio-cni (CNI Plugin, DaemonSet)"
        echo "  - Istio CRD"
        echo "  - Gateway API CRD (Gateway, HTTPRoute)"
        echo ""
        log_info "Ambient 모드 특징:"
        echo "  - Sidecar 없음 (Pod당 ~128MB 메모리 절감)"
        echo "  - ztunnel이 L4 mTLS 자동 처리"
        echo "  - Gateway 레벨에서 L7 정책 처리 (HTTPRoute)"
    else
        log_info "설치된 컴포넌트:"
        echo "  - istiod (Control Plane)"
        echo "  - Istio CRD (VirtualService, DestinationRule, AuthorizationPolicy 등)"
        echo "  - Gateway API CRD (Gateway, HTTPRoute)"
        echo ""
        log_info "Sidecar 모드 특징:"
        echo "  - Pod별 Envoy sidecar 주입"
        echo "  - L7 정책 처리 (VirtualService, DestinationRule)"
    fi
    echo ""
    log_info "ArgoCD가 관리하는 리소스:"
    echo "  - Gateway (Kubernetes Gateway API)"
    echo "  - HTTPRoute"
    echo "  - AuthorizationPolicy, RequestAuthentication"

    show_status
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

    echo "Istio Pods:"
    local pods
    pods=$(kubectl get pods -n "$ISTIO_NS" --no-headers 2>/dev/null) || true
    if [ -n "$pods" ]; then
        kubectl get pods -n "$ISTIO_NS" 2>/dev/null
    else
        echo "  없음"
    fi
    echo ""

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

    echo "Namespace Istio Labels:"
    for ns in ecommerce monitoring; do
        local sidecar_label ambient_label mode_info
        sidecar_label=$(kubectl get namespace "$ns" -o jsonpath='{.metadata.labels.istio-injection}' 2>/dev/null) || sidecar_label=""
        ambient_label=$(kubectl get namespace "$ns" -o jsonpath='{.metadata.labels.istio\.io/dataplane-mode}' 2>/dev/null) || ambient_label=""

        if [ -n "$ambient_label" ]; then
            mode_info="ambient ($ambient_label)"
        elif [ -n "$sidecar_label" ]; then
            mode_info="sidecar ($sidecar_label)"
        else
            mode_info="disabled"
        fi
        echo "  $ns: $mode_info"
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
  (없음)         Istio 설치 (Ambient 모드, 기본)
  --sidecar      Istio 설치 (Sidecar 모드)
  --ambient      Istio 설치 (Ambient 모드, 명시적)
  --uninstall    Istio 제거
  --status       상태 확인만
  --help         도움말

예시:
  $0                    # Istio Ambient 모드 설치 (기본)
  $0 --sidecar          # Istio Sidecar 모드 설치
  $0 --uninstall        # Istio 제거
  $0 --status           # 상태 확인

환경 변수:
  ISTIO_VERSION         Istio 버전 (기본: 1.28.0)
  GATEWAY_API_VERSION   Gateway API 버전 (기본: v1.2.0)
  ISTIO_MODE            설치 모드 (기본: ambient, 옵션: sidecar)

Ambient vs Sidecar:
  Ambient:  ztunnel(L4 mTLS) + istio-cni, Sidecar 없음, 리소스 효율적
  Sidecar:  Pod별 Envoy sidecar 주입, L7 정책 처리

EOF
}

# 메인
main() {
    local action="install"

    while [[ $# -gt 0 ]]; do
        case $1 in
            --uninstall) action="uninstall"; shift ;;
            --status) action="status"; shift ;;
            --sidecar) ISTIO_MODE="sidecar"; shift ;;
            --ambient) ISTIO_MODE="ambient"; shift ;;
            --help|-h) usage; exit 0 ;;
            *) log_error "알 수 없는 옵션: $1"; usage; exit 1 ;;
        esac
    done

    case $action in
        install) install_istio ;;
        uninstall) uninstall_istio ;;
        status) show_status ;;
    esac
}

main "$@"
