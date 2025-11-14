#!/bin/bash

# Istio 제거 스크립트
# 
# 이 스크립트는 다음을 수행합니다:
# 1. Istio 구성 리소스 삭제
# 2. Istio Control Plane 제거 (선택적)

set -euo pipefail

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 설정 변수
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
NAMESPACE="${NAMESPACE:-ecommerce}"
ISTIO_NAMESPACE="istio-system"
REMOVE_CONTROL_PLANE="${REMOVE_CONTROL_PLANE:-false}"

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

# Istio 구성 리소스 삭제
remove_istio_resources() {
    log_step "Istio 구성 리소스 삭제 중..."
    
    # Helm 차트로 설치된 경우
    if helm list -n "$NAMESPACE" 2>/dev/null | grep -q istio-config; then
        log_info "Helm 차트로 설치된 Istio 설정 제거 중..."
        helm uninstall istio-config -n "$NAMESPACE" || {
            log_warn "Helm release 제거 실패"
        }
        log_info "Helm 차트 제거 완료"
        return 0
    fi
    
    # YAML 방식으로 설치된 경우 (레거시)
    log_info "YAML 방식으로 설치된 Istio 설정 제거 중..."
    
    # 직접 리소스 삭제
    kubectl delete gateway -n "$NAMESPACE" --all --ignore-not-found=true
    kubectl delete httproute -n "$NAMESPACE" --all --ignore-not-found=true
    kubectl delete peerauthentication -n "$NAMESPACE" --all --ignore-not-found=true
    kubectl delete requestauthentication -n "$NAMESPACE" --all --ignore-not-found=true
    kubectl delete authorizationpolicy -n "$NAMESPACE" --all --ignore-not-found=true
    kubectl delete virtualservice -n "$NAMESPACE" --all --ignore-not-found=true
    kubectl delete destinationrule -n "$NAMESPACE" --all --ignore-not-found=true
    kubectl delete envoyfilter -n "$NAMESPACE" --all --ignore-not-found=true
    kubectl delete gatewayclass istio --ignore-not-found=true
    
    log_info "Istio 구성 리소스 삭제 완료"
}

# Istio Control Plane 제거
remove_istio_control_plane() {
    if [ "$REMOVE_CONTROL_PLANE" != "true" ]; then
        log_info "Istio Control Plane 제거를 건너뜁니다. (REMOVE_CONTROL_PLANE=true로 설정하여 제거 가능)"
        return
    fi
    
    log_step "Istio Control Plane 제거 중..."
    
    read -p "Istio Control Plane을 제거하시겠습니까? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Istio Control Plane 제거를 취소했습니다."
        return
    fi
    
    istioctl uninstall --purge -y || {
        log_error "Istio Control Plane 제거에 실패했습니다."
        exit 1
    }
    
    # Istio 네임스페이스 삭제
    kubectl delete namespace "$ISTIO_NAMESPACE" --ignore-not-found=true
    
    log_info "Istio Control Plane 제거 완료"
}

# 메인 함수
main() {
    log_step "=== Istio 제거 시작 ==="
    
    remove_istio_resources
    
    if [ "$REMOVE_CONTROL_PLANE" = "true" ]; then
        remove_istio_control_plane
    fi
    
    log_step "=== Istio 제거 완료 ==="
    log_info ""
    log_info "Istio Control Plane을 제거하려면:"
    log_info "  REMOVE_CONTROL_PLANE=true ./uninstall-istio.sh"
}

# 스크립트 실행
main "$@"


