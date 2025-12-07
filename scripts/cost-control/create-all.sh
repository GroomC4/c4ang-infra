#!/bin/bash
# =============================================================================
# AWS 리소스 생성 스크립트 (Terraform 기반)
# destroy-all.sh로 삭제한 리소스를 다시 생성
# =============================================================================

set -e

TERRAFORM_DIR="/Users/castle/Workspace/c4ang-infra/external-services/terraform/production"
REGION="ap-northeast-2"

echo "========================================"
echo "  AWS 리소스 생성 (Terraform)"
echo "========================================"
echo ""

# -----------------------------------------------------------------------------
# 1. Terraform 디렉토리 이동
# -----------------------------------------------------------------------------
cd "$TERRAFORM_DIR"

# -----------------------------------------------------------------------------
# 2. Terraform Init (필요한 경우)
# -----------------------------------------------------------------------------
echo "[1/4] Terraform 초기화..."
terraform init -upgrade

# -----------------------------------------------------------------------------
# 3. Terraform Plan
# -----------------------------------------------------------------------------
echo ""
echo "[2/4] Terraform Plan..."
terraform plan -out=tfplan

# -----------------------------------------------------------------------------
# 4. 사용자 확인
# -----------------------------------------------------------------------------
echo ""
read -p "위 리소스를 생성하시겠습니까? (yes 입력): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
  echo "취소되었습니다."
  rm -f tfplan
  exit 0
fi

# -----------------------------------------------------------------------------
# 5. Terraform Apply
# -----------------------------------------------------------------------------
echo ""
echo "[3/4] Terraform Apply..."
terraform apply tfplan
rm -f tfplan

# -----------------------------------------------------------------------------
# 6. 후속 작업 안내
# -----------------------------------------------------------------------------
echo ""
echo "[4/4] 후속 작업..."
echo ""
echo "========================================"
echo "  리소스 생성 완료!"
echo "========================================"
echo ""
echo "다음 단계:"
echo ""
echo "1. kubeconfig 업데이트:"
echo "   aws eks update-kubeconfig --name c4-cluster --region $REGION"
echo ""
echo "2. ArgoCD 동기화 (K8s 앱 배포):"
echo "   kubectl get applications -n argocd"
echo "   argocd app sync --all"
echo ""
echo "3. 서비스 상태 확인:"
echo "   kubectl get pods -A"
echo ""
echo "4. MSK Bootstrap Servers 확인 후 K8s 설정 업데이트:"
echo "   aws kafka list-clusters --query 'ClusterInfoList[*].[ClusterName,State]'"
echo "   aws kafka get-bootstrap-brokers --cluster-arn <ARN>"
echo ""
echo "예상 소요 시간:"
echo "  - EKS 클러스터: 15-20분"
echo "  - MSK: 15-20분"
echo "  - RDS: 5-10분"
echo "  - 노드 그룹: 5-10분"
