#!/bin/bash
set -e

# 환경 변수 설정
CLUSTER_NAME="${CLUSTER_NAME:-msa-quality-cluster}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🧹 k3d 리소스 정리 스크립트"
echo "=================================="
echo "클러스터 이름: ${CLUSTER_NAME}"
echo ""

# --force 플래그 확인
FORCE=false
if [[ "$1" == "--force" ]]; then
    FORCE=true
fi

# 클러스터 삭제 확인
if k3d cluster list | grep -q "${CLUSTER_NAME}"; then
    if [ "$FORCE" = false ]; then
        read -p "클러스터 '${CLUSTER_NAME}'를 삭제하시겠습니까? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "❌ 취소되었습니다."
            exit 0
        fi
    fi
    
    echo "🗑️  클러스터 삭제 중..."
    k3d cluster delete "${CLUSTER_NAME}"
    echo "✅ 클러스터가 삭제되었습니다."
else
    echo "ℹ️  클러스터 '${CLUSTER_NAME}'를 찾을 수 없습니다."
fi

# kubeconfig 파일 삭제
KUBECONFIG_FILE="$(dirname "${SCRIPT_DIR}")/kubeconfig/config"
if [ -f "${KUBECONFIG_FILE}" ]; then
    echo "🗑️  kubeconfig 파일 삭제 중..."
    rm -f "${KUBECONFIG_FILE}"
    echo "✅ kubeconfig 파일이 삭제되었습니다."
fi

echo ""
echo "✅ 정리 완료!"
echo ""
echo "새 클러스터를 생성하려면:"
echo "  cd $(dirname "${SCRIPT_DIR}")"
echo "  ./install-k3s.sh"
echo ""

