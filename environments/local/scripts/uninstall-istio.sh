#!/bin/bash
set -e

# 환경 변수 설정
NAMESPACE="${NAMESPACE:-ecommerce}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_DIR="$(dirname "${SCRIPT_DIR}")"
KUBECONFIG_FILE="${ENV_DIR}/kubeconfig/config"

echo "🗑️  Istio 제거 스크립트"
echo "=================================="
echo "네임스페이스: ${NAMESPACE}"
echo ""

# kubeconfig 확인
if [ ! -f "${KUBECONFIG_FILE}" ]; then
    echo "❌ kubeconfig 파일을 찾을 수 없습니다: ${KUBECONFIG_FILE}"
    exit 1
fi

export KUBECONFIG="${KUBECONFIG_FILE}"

# 삭제 확인
read -p "Istio를 제거하시겠습니까? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ 취소되었습니다."
    exit 0
fi

# Istio 제거
echo "🗑️  Istio 제거 중..."
helm uninstall istio --namespace "${NAMESPACE}" || {
    echo "⚠️  Istio 제거 중 오류가 발생했습니다. (이미 제거되었을 수 있습니다)"
}

echo ""
echo "✅ Istio 제거 완료!"
echo ""

