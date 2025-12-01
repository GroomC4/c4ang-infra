#!/bin/bash
set -e

# 환경 변수 설정
CLUSTER_NAME="${CLUSTER_NAME:-msa-quality-cluster}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🛑 로컬 환경 중지 스크립트"
echo "=================================="
echo "클러스터 이름: ${CLUSTER_NAME}"
echo ""

# 클러스터 중지
if k3d cluster list | grep -q "${CLUSTER_NAME}"; then
    echo "⏸️  클러스터 중지 중..."
    k3d cluster stop "${CLUSTER_NAME}"
    echo "✅ 클러스터가 중지되었습니다."
else
    echo "ℹ️  클러스터 '${CLUSTER_NAME}'를 찾을 수 없습니다."
fi

echo ""
echo "클러스터를 다시 시작하려면:"
echo "  k3d cluster start ${CLUSTER_NAME}"
echo ""

