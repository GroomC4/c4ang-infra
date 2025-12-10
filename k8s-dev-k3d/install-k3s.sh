#!/bin/bash

# K3d 클러스터 설치 스크립트 (E2E 테스트용)
# GitHub Actions 및 로컬 개발 환경에서 사용

set -euo pipefail

# 설정 변수
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTER_NAME="${CLUSTER_NAME:-msa-quality-cluster}"
K3D_REGISTRY_NAME="k3d-registry.localhost"
K3D_REGISTRY_PORT="${K3D_REGISTRY_PORT:-5050}"
KUBECONFIG_DIR="${SCRIPT_DIR}/kubeconfig"
KUBECONFIG_FILE="${KUBECONFIG_DIR}/config"
# 메모리 설정 (Blue-Green 배포를 위해 10GB 필요)
SERVER_MEMORY="${SERVER_MEMORY:-10g}"

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# k3d 설치 여부 확인
check_k3d() {
    if ! command -v k3d &> /dev/null; then
        log_error "k3d가 설치되어 있지 않습니다."
        log_info "k3d 설치: https://k3d.io/#installation"
        exit 1
    fi
    log_info "k3d 버전: $(k3d version | head -1)"
}

# kubectl 설치 여부 확인
check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl이 설치되어 있지 않습니다."
        exit 1
    fi
    log_info "kubectl 버전: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"
}

# helm 설치 여부 확인
check_helm() {
    if ! command -v helm &> /dev/null; then
        log_error "helm이 설치되어 있지 않습니다."
        exit 1
    fi
    log_info "helm 버전: $(helm version --short)"
}

# 기존 클러스터 삭제
cleanup_cluster() {
    if k3d cluster list | grep -q "${CLUSTER_NAME}"; then
        log_warn "기존 클러스터 '${CLUSTER_NAME}' 삭제 중..."
        k3d cluster delete "${CLUSTER_NAME}"
    fi
}

# K3d 클러스터 생성
create_cluster() {
    log_info "K3d 클러스터 '${CLUSTER_NAME}' 생성 중..."

    # kubeconfig 디렉토리 생성
    mkdir -p "${KUBECONFIG_DIR}"

    # K3d 클러스터 생성
    # 메모리: Blue-Green 배포 시 기존+신규 Pod 동시 실행 필요
    k3d cluster create "${CLUSTER_NAME}" \
        --servers 1 \
        --agents 0 \
        --servers-memory "${SERVER_MEMORY}" \
        --port "80:80@loadbalancer" \
        --port "443:443@loadbalancer" \
        --port "6443:6443@loadbalancer" \
        --port "30000-30100:30000-30100@server:0" \
        --k3s-arg "--disable=traefik@server:0" \
        --wait

    # kubeconfig 내보내기
    k3d kubeconfig get "${CLUSTER_NAME}" > "${KUBECONFIG_FILE}"
    chmod 600 "${KUBECONFIG_FILE}"

    log_info "Kubeconfig 저장됨: ${KUBECONFIG_FILE}"
}

# 클러스터 상태 확인
verify_cluster() {
    log_info "클러스터 상태 확인 중..."
    export KUBECONFIG="${KUBECONFIG_FILE}"

    # 노드 상태 확인
    echo ""
    echo "=== 노드 상태 ==="
    kubectl get nodes

    echo ""
    echo "=== 시스템 Pod 상태 ==="
    kubectl get pods -n kube-system

    echo ""
    log_info "클러스터가 준비되었습니다!"
}

# 기본 네임스페이스 생성
setup_namespaces() {
    log_info "네임스페이스 설정 중..."
    export KUBECONFIG="${KUBECONFIG_FILE}"

    # E2E 테스트용 네임스페이스
    kubectl create namespace msa-quality --dry-run=client -o yaml | kubectl apply -f -

    log_info "네임스페이스 생성 완료"
}

# 메인 함수
main() {
    log_info "=== K3d 클러스터 설치 시작 ==="

    check_k3d
    check_kubectl
    check_helm
    cleanup_cluster
    create_cluster
    verify_cluster
    setup_namespaces

    log_info "=== K3d 클러스터 설치 완료 ==="
    echo ""
    echo "사용 방법:"
    echo "  export KUBECONFIG=${KUBECONFIG_FILE}"
    echo "  kubectl get nodes"
    echo ""
}

main "$@"
