#!/bin/bash

# Istio Sidecar 수동 주입 및 서비스 배포 스크립트
# Istio webhook이 작동하지 않을 때 사용

set -euo pipefail

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 설정
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="ecommerce"
ISTIOCTL_PATH="${ISTIOCTL_PATH:-/Users/kim/Documents/GitHub/c4ang-infra/k8s-eks/istio/istio-1.28.0/bin/istioctl}"

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

# istioctl 경로 설정
if [ -f "$ISTIOCTL_PATH" ]; then
    export PATH="$(dirname "$ISTIOCTL_PATH"):$PATH"
else
    log_error "istioctl을 찾을 수 없습니다: $ISTIOCTL_PATH"
    exit 1
fi

# 서비스 목록
SERVICES=(
    "customer-service"
    "order-service"
    "product-service"
    "payment-service"
    "recommendation-service"
    "saga-tracker"
)

# Gateway API CRD 설치 확인
check_gateway_api() {
    log_step "Gateway API CRD 확인 중..."
    
    if ! kubectl get crd gateways.gateway.networking.k8s.io &>/dev/null; then
        log_warn "Gateway API CRD가 설치되어 있지 않습니다."
        log_info "다음 명령어로 설치하세요:"
        log_info "  kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.0.0/standard-install.yaml"
        return 1
    fi
    
    log_info "Gateway API CRD가 설치되어 있습니다."
    return 0
}

# 단일 서비스 배포
deploy_service() {
    local service=$1
    local service_dir="$SCRIPT_DIR/$service"
    
    log_step "📦 $service 배포 중..."
    
    # 1. Helm template 생성
    log_info "  Helm template 생성 중..."
    helm template "$service" "$service_dir" \
        -n "$NAMESPACE" \
        -f "$service_dir/values-eks-test.yaml" \
        > "/tmp/${service}-deployment.yaml"
    
    # 2. Sidecar 주입
    log_info "  Istio sidecar 주입 중..."
    istioctl kube-inject -f "/tmp/${service}-deployment.yaml" \
        > "/tmp/${service}-injected.yaml"
    
    # 3. 배포
    log_info "  Kubernetes에 배포 중..."
    if kubectl apply -f "/tmp/${service}-injected.yaml" -n "$NAMESPACE" 2>&1 | grep -v "Warning: resource"; then
        log_info "✅ $service 배포 완료"
        return 0
    else
        log_error "❌ $service 배포 실패"
        return 1
    fi
}

# 모든 서비스 배포
deploy_all_services() {
    log_step "=== 모든 서비스에 Sidecar 수동 주입 및 배포 시작 ==="
    echo ""
    
    local success_count=0
    local fail_count=0
    
    for service in "${SERVICES[@]}"; do
        if deploy_service "$service"; then
            ((success_count++))
        else
            ((fail_count++))
        fi
        echo ""
    done
    
    log_step "=== 배포 완료 ==="
    log_info "성공: $success_count개 서비스"
    [ $fail_count -gt 0 ] && log_warn "실패: $fail_count개 서비스"
    
    return $fail_count
}

# 배포 상태 확인
check_deployment_status() {
    log_step "=== 배포 상태 확인 ==="
    echo ""
    
    log_info "전체 Pod 상태:"
    kubectl get pods -n "$NAMESPACE"
    echo ""
    
    log_info "Sidecar 주입된 Pod (2/2 Ready):"
    kubectl get pods -n "$NAMESPACE" | grep "2/2" | wc -l | xargs echo "  개수:"
    echo ""
    
    log_info "Istio 리소스:"
    kubectl get virtualservice,destinationrule,httproute -n "$NAMESPACE" 2>/dev/null || true
    echo ""
}

# 메인 함수
main() {
    log_step "=== Istio Sidecar 수동 주입 배포 스크립트 ==="
    echo ""
    
    # 사전 확인
    log_info "kubectl 연결 확인..."
    if ! kubectl cluster-info &>/dev/null; then
        log_error "Kubernetes 클러스터에 연결할 수 없습니다."
        exit 1
    fi
    log_info "✅ 클러스터 연결 정상"
    echo ""
    
    log_info "istioctl 버전 확인..."
    istioctl version --remote=false --short
    echo ""
    
    # Gateway API 확인 (경고만 표시)
    check_gateway_api || log_warn "Gateway API를 사용하는 HTTPRoute는 배포되지 않을 수 있습니다."
    echo ""
    
    # 서비스 배포
    if deploy_all_services; then
        log_info "모든 서비스가 성공적으로 배포되었습니다."
    else
        log_warn "일부 서비스 배포에 실패했습니다."
    fi
    echo ""
    
    # 상태 확인
    log_info "30초 후 배포 상태를 확인합니다..."
    sleep 30
    check_deployment_status
    
    log_step "=== 완료 ==="
}

# 스크립트 실행
main "$@"


