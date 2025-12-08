#!/bin/bash
# =============================================================================
# AWS 리소스 완전 삭제 스크립트 (Terraform 기반)
# Terraform destroy를 사용하여 state 일관성 유지
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="/Users/castle/Workspace/c4ang-infra/external-services/terraform/production"
REGION="ap-northeast-2"
CLUSTER_NAME="c4-cluster"

echo "========================================"
echo "  AWS 리소스 완전 삭제 (Terraform 기반)"
echo "========================================"
echo ""
echo "⚠️  경고: 모든 데이터가 삭제됩니다!"
echo "⚠️  이 작업은 되돌릴 수 없습니다!"
echo ""
read -p "정말로 모든 리소스를 삭제하시겠습니까? (yes 입력): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
  echo "취소되었습니다."
  exit 0
fi

echo ""
echo "=== 삭제 시작: $(date) ==="

cd "$TERRAFORM_DIR"

# -----------------------------------------------------------------------------
# 1. Terraform Destroy 실행
# -----------------------------------------------------------------------------
echo ""
echo "[1/2] Terraform Destroy 실행..."
echo "  (모든 리소스가 삭제됩니다. 15-30분 소요)"
echo ""

terraform destroy -auto-approve

# -----------------------------------------------------------------------------
# 2. 삭제 완료 확인
# -----------------------------------------------------------------------------
echo ""
echo "[2/2] 삭제 완료 확인..."

# EKS 클러스터 확인
if aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" &>/dev/null; then
  echo "  ⚠️  EKS 클러스터가 아직 존재합니다. 수동 확인 필요."
else
  echo "  ✓ EKS 클러스터 삭제 완료"
fi

# MSK 확인
MSK_COUNT=$(aws kafka list-clusters --region "$REGION" \
  --query "length(ClusterInfoList[?contains(ClusterName, 'c4')])" \
  --output text 2>/dev/null || echo "0")
if [ "$MSK_COUNT" -gt 0 ]; then
  echo "  ⚠️  MSK 클러스터가 아직 존재합니다. 수동 확인 필요."
else
  echo "  ✓ MSK 클러스터 삭제 완료"
fi

# RDS 확인
RDS_COUNT=$(aws rds describe-db-instances --region "$REGION" \
  --query "length(DBInstances[?starts_with(DBInstanceIdentifier, 'c4-')])" \
  --output text 2>/dev/null || echo "0")
if [ "$RDS_COUNT" -gt 0 ]; then
  echo "  ⚠️  RDS 인스턴스가 아직 존재합니다. 수동 확인 필요."
else
  echo "  ✓ RDS 인스턴스 삭제 완료"
fi

# -----------------------------------------------------------------------------
# 완료
# -----------------------------------------------------------------------------
echo ""
echo "========================================"
echo "  삭제 완료: $(date)"
echo "========================================"
echo ""
echo "다시 생성하려면:"
echo "  $SCRIPT_DIR/create-all.sh"
echo ""
