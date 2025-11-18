#!/bin/bash

# Kubernetes Gateway API CRD 설치 스크립트

set -euo pipefail

# 색상 정의
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
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

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

GATEWAY_API_VERSION="${GATEWAY_API_VERSION:-v1.0.0}"

main() {
    log_step "=== Kubernetes Gateway API CRD 설치 ==="
    echo ""
    
    # kubectl 연결 확인
    if ! kubectl cluster-info &>/dev/null; then
        log_error "Kubernetes 클러스터에 연결할 수 없습니다."
        exit 1
    fi
    
    log_info "Gateway API 버전: $GATEWAY_API_VERSION"
    echo ""
    
    # 기존 CRD 확인
    log_step "기존 Gateway API CRD 확인..."
    if kubectl get crd gateways.gateway.networking.k8s.io &>/dev/null; then
        log_warn "Gateway API가 이미 설치되어 있습니다."
        read -p "재설치하시겠습니까? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "설치를 건너뜁니다."
            exit 0
        fi
    fi
    
    # Gateway API CRD 설치
    log_step "Gateway API CRD 설치 중..."
    if kubectl apply -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml"; then
        log_info "Gateway API CRD 설치 성공"
    else
        log_error "Gateway API CRD 설치 실패"
        exit 1
    fi
    
    echo ""
    sleep 3
    
    # 설치 확인
    log_step "설치 확인 중..."
    if kubectl get crd gateways.gateway.networking.k8s.io &>/dev/null; then
        log_info "✓ Gateway CRD 확인됨"
    else
        log_error "Gateway CRD를 찾을 수 없습니다."
        exit 1
    fi
    
    if kubectl get crd httproutes.gateway.networking.k8s.io &>/dev/null; then
        log_info "✓ HTTPRoute CRD 확인됨"
    else
        log_error "HTTPRoute CRD를 찾을 수 없습니다."
        exit 1
    fi
    
    echo ""
    log_step "=== 설치 완료 ==="
    log_info ""
    log_info "설치된 Gateway API CRD:"
    kubectl get crd | grep "gateway.networking.k8s.io"
    echo ""
    log_info ""
    log_info "이제 HTTPRoute 리소스를 사용할 수 있습니다."
    log_info "서비스를 재배포하여 HTTPRoute를 생성하세요:"
    log_info "  cd /Users/kim/Documents/GitHub/c4ang-infra/helm/services"
    log_info "  ./deploy-with-sidecar-injection.sh"
}

main "$@"


