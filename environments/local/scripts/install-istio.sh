#!/bin/bash

# Istio 설치 스크립트
# 
# 이 스크립트는 다음을 수행합니다:
# 1. Istio Operator 설치
# 2. Istio Control Plane 배포
# 3. Gateway API CRD 설치
# 4. Istio 구성 리소스 배포

set -euo pipefail

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 설정 변수
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_LOCAL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_ROOT="$(cd "$ENV_LOCAL_DIR/../.." && pwd)"
ISTIO_VERSION="${ISTIO_VERSION:-1.22.0}"
NAMESPACE="${NAMESPACE:-ecommerce}"
ISTIO_NAMESPACE="istio-system"
# 환경별 설정 경로
CONFIG_DIR="${PROJECT_ROOT}/config/local"
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
    echo -e "${GREEN}[✓]${NC} $1"
}

# istioctl 찾기 및 PATH에 추가
find_istioctl() {
    # PATH에 이미 있는지 확인
    if command -v istioctl &> /dev/null; then
        return 0
    fi
    
    # 프로젝트 루트 및 상위 디렉토리에서 istio-*/bin 디렉토리 찾기
    local search_dirs=(
        "$PROJECT_ROOT"
        "$(dirname "$PROJECT_ROOT")"
        "$HOME/Documents/GitHub"
    )
    
    for dir in "${search_dirs[@]}"; do
        if [ -d "$dir" ]; then
            # istio-* 디렉토리 찾기
            for istio_dir in "$dir"/**/istio-*/bin/istioctl; do
                if [ -f "$istio_dir" ] && [ -x "$istio_dir" ]; then
                    log_info "istioctl을 찾았습니다: $istio_dir"
                    export PATH="$(dirname "$istio_dir"):$PATH"
                    return 0
                fi
            done
        fi
    done
    
    return 1
}

# 필수 도구 확인
check_prerequisites() {
    log_step "필수 도구 확인 중..."
    
    # kubectl 확인
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl이 설치되어 있지 않습니다."
        exit 1
    fi
    
    # istioctl 확인 및 찾기
    if ! command -v istioctl &> /dev/null; then
        log_warn "istioctl이 PATH에 없습니다. 자동으로 찾는 중..."
        if ! find_istioctl; then
            log_error "istioctl을 찾을 수 없습니다."
            log_info ""
            log_info "istioctl 설치 방법:"
            log_info "  1. curl -L https://istio.io/downloadIstio | sh -"
            log_info "  2. export PATH=\"\$PATH:\$PWD/istio-*/bin\""
            log_info "  3. 또는 Homebrew: brew install istioctl"
            exit 1
        fi
    fi
    
    # istioctl 버전 확인
    local istioctl_version
    istioctl_version=$(istioctl version --remote=false --short 2>/dev/null || echo "unknown")
    log_info "istioctl 버전: $istioctl_version"
    
    # k3d 클러스터 연결 확인
    if ! kubectl cluster-info &> /dev/null; then
        log_error "k3d 클러스터에 연결할 수 없습니다."
        log_info "k3d 클러스터를 확인하세요: k3d cluster list"
        exit 1
    fi
    
    log_info "모든 필수 도구가 설치되어 있습니다."
}

# Istio 설치 확인
check_istio_installed() {
    if kubectl get namespace "$ISTIO_NAMESPACE" &> /dev/null; then
        log_warn "Istio가 이미 설치되어 있습니다."
        read -p "재설치하시겠습니까? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "설치를 건너뜁니다."
            return 1
        fi
        return 0
    fi
    return 0
}

# Istio 설치
install_istio() {
    log_step "Istio ${ISTIO_VERSION} 설치 중..."
    
    # Istio 네임스페이스 생성
    kubectl create namespace "$ISTIO_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    
    # Istio Operator 설치
    istioctl install \
        --set values.defaultRevision=default \
        --set profile=minimal \
        -y
    
    log_info "Istio Control Plane 설치 완료"
    
    # Istio 설치 확인
    log_step "Istio 설치 확인 중..."
    kubectl wait --for=condition=ready pod -l app=istiod -n "$ISTIO_NAMESPACE" --timeout=300s || {
        log_error "Istio Control Plane이 준비되지 않았습니다."
        exit 1
    }
    
    log_info "Istio Control Plane이 준비되었습니다."
}

# Gateway API CRD 설치
install_gateway_api() {
    log_step "Gateway API CRD 설치 확인 중..."
    
    # 이미 설치되어 있는지 확인
    if kubectl get crd gateways.gateway.networking.k8s.io &> /dev/null; then
        log_info "Gateway API CRD가 이미 설치되어 있습니다."
        return 0
    fi
    
    log_step "Gateway API CRD 설치 중..."
    
    # Gateway API 버전 확인 및 설치
    GATEWAY_API_VERSION="v1.0.0"
    
    kubectl apply -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml"
    
    log_info "Gateway API CRD 설치 완료"
    
    # Gateway API 설치 확인
    log_step "Gateway API 설치 확인 중..."
    sleep 5
    if kubectl get crd gateways.gateway.networking.k8s.io &> /dev/null; then
        log_info "Gateway API가 설치되었습니다."
    else
        log_error "Gateway API 설치에 실패했습니다."
        exit 1
    fi
}

# Istio CRD 확인
check_istio_crds() {
    log_step "Istio CRD 확인 중..."
    
    local required_crds=(
        "authorizationpolicies.security.istio.io"
        "peerauthentications.security.istio.io"
        "requestauthentications.security.istio.io"
    )
    
    local missing_crds=()
    
    for crd in "${required_crds[@]}"; do
        if ! kubectl get crd "$crd" &> /dev/null; then
            missing_crds+=("$crd")
        fi
    done
    
    if [ ${#missing_crds[@]} -ne 0 ]; then
        log_error "Istio CRD가 설치되어 있지 않습니다: ${missing_crds[*]}"
        log_info "Istio Control Plane을 설치하면 CRD가 자동으로 설치됩니다."
        log_info "istioctl install --set profile=minimal -y"
        exit 1
    fi
    
    log_info "필수 Istio CRD가 설치되어 있습니다."
}

# Istio Gateway Class 설치
install_istio_gateway_class() {
    log_step "Istio Gateway Class 확인 중..."
    
    # 이미 존재하는지 확인
    if kubectl get gatewayclass istio &> /dev/null; then
        log_info "Istio Gateway Class가 이미 존재합니다."
        return 0
    fi
    
    log_step "Istio Gateway Class 설치 중..."
    
    kubectl apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: istio
spec:
  controllerName: istio.io/gateway-controller
EOF
    
    log_info "Istio Gateway Class 설치 완료"
}

# E-commerce 네임스페이스 생성 및 라벨링
setup_namespace() {
    log_step "E-commerce 네임스페이스 설정 중..."
    
    # 네임스페이스 생성
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    
    # Istio 자동 주입 활성화
    kubectl label namespace "$NAMESPACE" istio-injection=enabled --overwrite || true
    
    log_info "네임스페이스 '$NAMESPACE' 설정 완료"
}

# Istio 구성 리소스 배포
deploy_istio_resources() {
    log_step "Istio 구성 리소스 배포 중..."
    
    local resources_dir="${PROJECT_ROOT}/../k8s-eks/istio/resources"
    
    if [ ! -d "$resources_dir" ]; then
        log_error "리소스 디렉토리를 찾을 수 없습니다: $resources_dir"
        log_info "레거시 YAML 방식은 EKS 리소스 디렉토리를 사용합니다."
        log_info "Helm 차트 방식을 권장합니다: ./install-istio.sh (기본값)"
        exit 1
    fi
    
    # 리소스 배포 순서
    local deploy_order=(
        "00-gateway-class.yaml"
        "01-peer-authentication.yaml"
        "02-gateway-main.yaml"
        "03-gateway-webhook.yaml"
        "04-httproute-*.yaml"
        "05-request-authentication.yaml"
        "05-virtual-service-retry-timeout.yaml"
        "06-authorization-policy.yaml"
        "07-destination-rule-*.yaml"
        "08-envoy-filter-*.yaml"
    )
    
    for pattern in "${deploy_order[@]}"; do
        for file in "$resources_dir"/$pattern; do
            if [ -f "$file" ]; then
                log_info "배포 중: $(basename "$file")"
                kubectl apply -f "$file" -n "$NAMESPACE" || {
                    log_warn "배포 실패 (계속 진행): $(basename "$file")"
                }
            fi
        done
    done
    
    log_info "Istio 구성 리소스 배포 완료"
}

# Helm 차트 설치 옵션
install_with_helm() {
    log_step "=== Helm 차트로 Istio 설정 설치 ==="

    local helm_chart_path="${CHARTS_DIR}/istio"
    local values_file=""

    if [ -f "${CONFIG_DIR}/istio.yaml" ]; then
        values_file="${CONFIG_DIR}/istio.yaml"
    fi

    if [ ! -d "$helm_chart_path" ]; then
        log_error "Helm 차트를 찾을 수 없습니다: $helm_chart_path"
        return 1
    fi

    log_info "Helm 차트로 Istio 설정을 설치합니다."
    log_info "Helm 차트: $helm_chart_path"
    if [ -n "$values_file" ] && [ -f "$values_file" ]; then
        log_info "Values 파일: $values_file"
    fi
    
    # Helm 설치 확인
    if ! command -v helm &> /dev/null; then
        log_error "Helm이 설치되어 있지 않습니다."
        log_info "Helm 설치: brew install helm (macOS)"
        return 1
    fi
    
    # CRD 확인
    check_istio_crds
    install_gateway_api
    
    # 네임스페이스 생성 (이미 있으면 무시)
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    kubectl label namespace "$NAMESPACE" istio-injection=enabled --overwrite || true
    
    # GatewayClass가 없으면 생성
    if ! kubectl get gatewayclass istio &> /dev/null; then
        install_istio_gateway_class
    fi
    
    # Helm 차트 설치/업데이트 (values 파일이 있으면 사용)
    log_info "Helm 차트 설치/업데이트 중..."
    
    # 기존 release 확인
    local helm_cmd
    if helm list -n "$NAMESPACE" 2>/dev/null | grep -q istio-config; then
        log_info "기존 Helm release 발견. 업데이트합니다..."
        helm_cmd="helm upgrade istio-config $helm_chart_path --namespace $NAMESPACE --set namespace.create=false --set gatewayAPI.enabled=false"
    else
        log_info "새로운 Helm release를 설치합니다..."
        helm_cmd="helm install istio-config $helm_chart_path --namespace $NAMESPACE --set namespace.create=false --set gatewayAPI.enabled=false"
    fi
    
    if [ -n "$values_file" ] && [ -f "$values_file" ]; then
        helm_cmd="$helm_cmd -f $values_file"
    fi

    eval "$helm_cmd --wait" || {
        log_error "Helm 차트 설치/업데이트 실패"
        log_info "기존 release를 제거한 후 다시 시도하세요:"
        log_info "  helm uninstall istio-config -n $NAMESPACE"
        return 1
    }

    log_success "Helm 차트 설치/업데이트 완료"
    log_info ""
    if [ -n "$values_file" ]; then
        log_info "업데이트: helm upgrade istio-config $helm_chart_path -n $NAMESPACE -f $values_file"
    else
        log_info "업데이트: helm upgrade istio-config $helm_chart_path -n $NAMESPACE"
    fi
    log_info "제거: helm uninstall istio-config -n $NAMESPACE"
}

# 메인 함수
main() {
    # 설치 방법 선택 (기본값: helm)
    local install_method="${INSTALL_METHOD:-helm}"  # helm (권장) 또는 yaml (레거시)
    
    if [ "$install_method" = "helm" ]; then
        check_prerequisites
        if check_istio_installed; then
            install_istio
        fi
        check_istio_crds
        install_with_helm
        return 0
    fi
    
    # 레거시 YAML 방식 (resources/ 디렉토리 필요)
    log_warn "YAML 방식은 레거시입니다. Helm 차트 방식을 권장합니다."
    
    local resources_dir="${SCRIPT_DIR}/resources"
    if [ ! -d "$resources_dir" ]; then
        log_error "resources 디렉토리를 찾을 수 없습니다: $resources_dir"
        log_info ""
        log_info "Helm 차트 방식으로 설치하세요:"
        log_info "  ./install-istio.sh  # 또는 INSTALL_METHOD=helm ./install-istio.sh"
        log_info ""
        log_info "YAML 방식을 사용하려면 resources 디렉토리가 필요합니다."
        log_info "이는 레거시 방식이며, Helm 차트 사용을 권장합니다."
        exit 1
    fi
    
    log_step "=== Istio 설치 시작 (YAML 방식 - 레거시) ==="
    
    check_prerequisites
    
    if check_istio_installed; then
        install_istio
    fi
    
    check_istio_crds
    install_gateway_api
    install_istio_gateway_class
    setup_namespace
    deploy_istio_resources
    
    log_step "=== Istio 설치 완료 ==="
    log_info ""
    log_info "다음 명령어로 Istio 상태를 확인하세요:"
    log_info "  kubectl get pods -n $ISTIO_NAMESPACE"
    log_info "  istioctl verify-install"
    log_info "  kubectl get gateway -n $NAMESPACE"
    log_info ""
    log_warn "YAML 방식은 레거시입니다. Helm 차트 방식 사용을 권장합니다:"
    log_info "  helm upgrade istio-config ../../helm/management-base/istio -n $NAMESPACE"
}

# 스크립트 실행
main "$@"

