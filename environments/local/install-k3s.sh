#!/bin/bash
set -e

# 환경 변수 설정
CLUSTER_NAME="${CLUSTER_NAME:-msa-quality-cluster}"
NAMESPACE="${NAMESPACE:-msa-quality}"
NODEPORT_START="${NODEPORT_START:-30000}"
NODEPORT_END="${NODEPORT_END:-30100}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBECONFIG_DIR="${SCRIPT_DIR}/kubeconfig"
KUBECONFIG_FILE="${KUBECONFIG_DIR}/config"

echo "🚀 k3d 클러스터 설치 및 생성 스크립트"
echo "=================================="
echo "클러스터 이름: ${CLUSTER_NAME}"
echo "네임스페이스: ${NAMESPACE}"
echo "NodePort 범위: ${NODEPORT_START}-${NODEPORT_END}"
echo ""

# k3d 설치 확인 및 설치
if ! command -v k3d &> /dev/null; then
    echo "📦 k3d가 설치되어 있지 않습니다. 설치를 시작합니다..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        if command -v brew &> /dev/null; then
            brew install k3d
        else
            echo "❌ Homebrew가 설치되어 있지 않습니다. https://k3d.io/ 를 참고하여 수동으로 설치해주세요."
            exit 1
        fi
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux
        curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
    else
        echo "❌ 지원하지 않는 OS입니다. https://k3d.io/ 를 참고하여 수동으로 설치해주세요."
        exit 1
    fi
else
    echo "✅ k3d가 이미 설치되어 있습니다: $(k3d version)"
fi

# Helm 설치 확인 및 설치
if ! command -v helm &> /dev/null; then
    echo "📦 Helm이 설치되어 있지 않습니다. 설치를 시작합니다..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        if command -v brew &> /dev/null; then
            brew install helm
        else
            echo "❌ Homebrew가 설치되어 있지 않습니다. https://helm.sh/docs/intro/install/ 를 참고하여 수동으로 설치해주세요."
            exit 1
        fi
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    else
        echo "❌ 지원하지 않는 OS입니다. https://helm.sh/docs/intro/install/ 를 참고하여 수동으로 설치해주세요."
        exit 1
    fi
else
    echo "✅ Helm이 이미 설치되어 있습니다: $(helm version --short)"
fi

# 기존 클러스터 확인
if k3d cluster list | grep -q "${CLUSTER_NAME}"; then
    echo "⚠️  클러스터 '${CLUSTER_NAME}'가 이미 존재합니다."
    read -p "기존 클러스터를 삭제하고 새로 생성하시겠습니까? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "🗑️  기존 클러스터 삭제 중..."
        k3d cluster delete "${CLUSTER_NAME}"
    else
        echo "ℹ️  기존 클러스터를 사용합니다."
        exit 0
    fi
fi

# kubeconfig 디렉토리 생성
mkdir -p "${KUBECONFIG_DIR}"

# k3d 클러스터 생성
echo "🔨 k3d 클러스터 생성 중..."
k3d cluster create "${CLUSTER_NAME}" \
    --api-port 6443 \
    --port "${NODEPORT_START}-${NODEPORT_END}:${NODEPORT_START}-${NODEPORT_END}@loadbalancer" \
    --servers 1 \
    --agents 1 \
    --k3s-arg "--disable=traefik@server:0" \
    --wait

# kubeconfig 가져오기
echo "📋 kubeconfig 설정 중..."
k3d kubeconfig write "${CLUSTER_NAME}" --output "${KUBECONFIG_FILE}"

# kubeconfig 권한 설정
chmod 600 "${KUBECONFIG_FILE}"

# Helm 저장소 추가
echo "📦 Helm 저장소 추가 중..."
helm repo add bitnami https://charts.bitnami.com/bitnami 2>/dev/null || true
helm repo add apache-airflow https://airflow.apache.org 2>/dev/null || true
helm repo update

echo ""
echo "✅ k3d 클러스터 생성 완료!"
echo ""
echo "다음 명령어로 kubeconfig를 설정하세요:"
echo "  export KUBECONFIG=${KUBECONFIG_FILE}"
echo ""
echo "또는:"
echo "  export KUBECONFIG=\$(pwd)/kubeconfig/config"
echo ""
echo "클러스터 상태 확인:"
echo "  kubectl --kubeconfig=${KUBECONFIG_FILE} get nodes"
echo ""

