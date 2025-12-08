#!/bin/bash
# =============================================================================
# AWS 리소스 생성 스크립트 (Terraform 기반)
# destroy-all.sh로 삭제한 리소스를 다시 생성
# - 리소스 생성 완료까지 대기
# - 중단 시 안전하게 재시작 가능
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="/Users/castle/Workspace/c4ang-infra/external-services/terraform/production"
REGION="ap-northeast-2"
CLUSTER_NAME="c4-cluster"

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "========================================"
echo "  AWS 리소스 생성 (Terraform)"
echo "========================================"
echo ""

cd "$TERRAFORM_DIR"

# -----------------------------------------------------------------------------
# 1. Terraform Init
# -----------------------------------------------------------------------------
echo "[1/5] Terraform 초기화..."
terraform init -upgrade

# -----------------------------------------------------------------------------
# 2. Terraform Plan
# -----------------------------------------------------------------------------
echo ""
echo "[2/5] Terraform Plan..."
terraform plan -out=tfplan

# -----------------------------------------------------------------------------
# 3. 사용자 확인
# -----------------------------------------------------------------------------
echo ""
read -p "위 리소스를 생성하시겠습니까? (yes 입력): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
  echo "취소되었습니다."
  rm -f tfplan
  exit 0
fi

# -----------------------------------------------------------------------------
# 4. Terraform Apply
# -----------------------------------------------------------------------------
echo ""
echo "[3/5] Terraform Apply..."
echo "  (리소스 생성 중... 15-30분 소요될 수 있습니다)"
echo ""
echo -e "${YELLOW}⚠️  중요: 이 과정을 중단하지 마세요!${NC}"
echo -e "${YELLOW}   중단 시 다시 이 스크립트를 실행하면 자동으로 복구됩니다.${NC}"
echo ""

terraform apply tfplan
rm -f tfplan

# -----------------------------------------------------------------------------
# 5. 리소스 생성 완료 대기
# -----------------------------------------------------------------------------
echo ""
echo "[4/5] 리소스 생성 완료 대기..."

# EKS 노드그룹 상태 확인 함수
wait_for_nodegroups() {
  echo "  EKS 노드그룹 상태 확인 중..."

  local max_attempts=60  # 최대 30분 대기 (30초 * 60)
  local attempt=0

  while [ $attempt -lt $max_attempts ]; do
    local all_active=true
    local nodegroups=$(aws eks list-nodegroups --cluster-name "$CLUSTER_NAME" --region "$REGION" \
      --query 'nodegroups[]' --output text 2>/dev/null || echo "")

    if [ -z "$nodegroups" ]; then
      echo -e "    ${YELLOW}노드그룹을 찾을 수 없습니다. 10초 후 재시도...${NC}"
      sleep 10
      ((attempt++))
      continue
    fi

    for ng in $nodegroups; do
      local ng_status=$(aws eks describe-nodegroup --cluster-name "$CLUSTER_NAME" \
        --nodegroup-name "$ng" --region "$REGION" \
        --query 'nodegroup.status' --output text 2>/dev/null || echo "UNKNOWN")

      if [ "$ng_status" = "ACTIVE" ]; then
        echo -e "    ${GREEN}✓${NC} $ng: ACTIVE"
      elif [ "$ng_status" = "CREATING" ]; then
        echo -e "    ${YELLOW}⏳${NC} $ng: CREATING"
        all_active=false
      elif [ "$ng_status" = "CREATE_FAILED" ]; then
        echo -e "    ${RED}✗${NC} $ng: CREATE_FAILED"
        echo ""
        echo -e "${RED}오류: 노드그룹 생성 실패. 로그를 확인하세요.${NC}"
        exit 1
      else
        echo -e "    ${YELLOW}?${NC} $ng: $ng_status"
        all_active=false
      fi
    done

    if $all_active; then
      echo ""
      echo -e "  ${GREEN}✓ 모든 노드그룹이 ACTIVE 상태입니다.${NC}"
      return 0
    fi

    echo ""
    echo "  30초 후 재확인... ($(( max_attempts - attempt )) 회 남음)"
    sleep 30
    ((attempt++))
  done

  echo ""
  echo -e "${RED}오류: 노드그룹 생성 타임아웃 (30분 초과)${NC}"
  echo "수동으로 상태를 확인하세요:"
  echo "  aws eks list-nodegroups --cluster-name $CLUSTER_NAME"
  exit 1
}

# EKS 노드 Ready 상태 확인 함수
wait_for_nodes_ready() {
  echo ""
  echo "  Kubernetes 노드 Ready 상태 확인 중..."

  # kubeconfig 업데이트
  aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION" &>/dev/null

  local max_attempts=30  # 최대 10분 대기 (20초 * 30)
  local attempt=0

  while [ $attempt -lt $max_attempts ]; do
    local not_ready=$(kubectl get nodes --no-headers 2>/dev/null | grep -v " Ready " | wc -l || echo "999")
    local total=$(kubectl get nodes --no-headers 2>/dev/null | wc -l || echo "0")

    if [ "$total" -eq 0 ]; then
      echo -e "    ${YELLOW}노드를 찾을 수 없습니다. 20초 후 재시도...${NC}"
      sleep 20
      ((attempt++))
      continue
    fi

    local ready_count=$((total - not_ready))
    echo -e "    노드 상태: ${GREEN}$ready_count${NC}/$total Ready"

    if [ "$not_ready" -eq 0 ]; then
      echo ""
      echo -e "  ${GREEN}✓ 모든 노드가 Ready 상태입니다.${NC}"
      return 0
    fi

    sleep 20
    ((attempt++))
  done

  echo ""
  echo -e "${YELLOW}경고: 일부 노드가 아직 Ready 상태가 아닙니다.${NC}"
  echo "kubectl get nodes 명령으로 확인하세요."
}

# 대기 실행
wait_for_nodegroups
wait_for_nodes_ready

# -----------------------------------------------------------------------------
# 6. 완료
# -----------------------------------------------------------------------------
echo ""
echo "[5/5] 후속 작업..."
echo ""
echo "========================================"
echo -e "  ${GREEN}리소스 생성 완료!${NC}"
echo "========================================"
echo ""
echo "다음 단계:"
echo ""
echo "1. ArgoCD 동기화 (K8s 앱 배포):"
echo "   kubectl get applications -n argocd"
echo "   argocd app sync --all"
echo ""
echo "2. 서비스 상태 확인:"
echo "   kubectl get pods -A"
echo ""
