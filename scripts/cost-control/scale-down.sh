#!/bin/bash
# =============================================================================
# AWS 리소스 스케일 다운 스크립트
# 사용량이 없을 때 비용 절감을 위해 리소스를 최소화
# =============================================================================

set -e

CLUSTER_NAME="c4-cluster"
REGION="ap-northeast-2"

echo "=== AWS 리소스 스케일 다운 시작 ==="
echo "시작 시간: $(date)"

# -----------------------------------------------------------------------------
# 1. EKS 노드 그룹 스케일 다운 (0개)
# -----------------------------------------------------------------------------
echo ""
echo "[1/4] EKS 노드 그룹 스케일 다운..."

NODE_GROUPS=$(aws eks list-nodegroups --cluster-name $CLUSTER_NAME --region $REGION --query 'nodegroups[*]' --output text)

for ng in $NODE_GROUPS; do
  echo "  - $ng → 0개로 축소"
  aws eks update-nodegroup-config \
    --cluster-name $CLUSTER_NAME \
    --nodegroup-name "$ng" \
    --scaling-config minSize=0,maxSize=1,desiredSize=0 \
    --region $REGION 2>/dev/null || echo "    (이미 0개이거나 업데이트 진행 중)"
done

# -----------------------------------------------------------------------------
# 2. RDS 인스턴스 중지
# -----------------------------------------------------------------------------
echo ""
echo "[2/4] RDS 인스턴스 중지..."

RDS_INSTANCES=$(aws rds describe-db-instances --region $REGION \
  --query "DBInstances[?TagList[?Key=='Project' && Value=='c4']].DBInstanceIdentifier" \
  --output text 2>/dev/null)

for db in $RDS_INSTANCES; do
  STATUS=$(aws rds describe-db-instances --db-instance-identifier "$db" --region $REGION \
    --query 'DBInstances[0].DBInstanceStatus' --output text 2>/dev/null)

  if [ "$STATUS" == "available" ]; then
    echo "  - $db 중지 중..."
    aws rds stop-db-instance --db-instance-identifier "$db" --region $REGION 2>/dev/null || true
  else
    echo "  - $db (상태: $STATUS - 스킵)"
  fi
done

# -----------------------------------------------------------------------------
# 3. MSK 클러스터 (삭제하지 않음 - 데이터 보존)
# -----------------------------------------------------------------------------
echo ""
echo "[3/4] MSK 클러스터..."
echo "  - MSK는 스케일 다운 불가 (삭제 시 데이터 손실)"
echo "  - 완전 비용 절감이 필요하면 별도로 삭제하세요"

# -----------------------------------------------------------------------------
# 4. NAT Gateway (선택적 - 삭제 시 Private 서브넷 인터넷 불가)
# -----------------------------------------------------------------------------
echo ""
echo "[4/4] NAT Gateway..."
echo "  - NAT Gateway 유지 (삭제 시 재생성 필요)"
echo "  - 완전 삭제하려면: terraform destroy -target=aws_nat_gateway.this"

# -----------------------------------------------------------------------------
# 완료
# -----------------------------------------------------------------------------
echo ""
echo "=== 스케일 다운 완료 ==="
echo "완료 시간: $(date)"
echo ""
echo "예상 비용 절감:"
echo "  - EC2 노드: ~\$50/5일 → \$0"
echo "  - RDS 중지: ~\$22/5일 → \$0 (스토리지 비용만 발생)"
echo ""
echo "복구하려면: ./scale-up.sh 실행"
