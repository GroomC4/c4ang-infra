#!/bin/bash
# =============================================================================
# AWS 리소스 완전 삭제 스크립트 (개발 환경 전용)
# 모든 리소스를 삭제하여 비용을 0으로 만듦
# 주의: 모든 데이터가 삭제됩니다!
# =============================================================================

set -e

REGION="ap-northeast-2"
PROJECT="c4"

echo "========================================"
echo "  AWS 리소스 완전 삭제 (개발 환경 전용)"
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

# -----------------------------------------------------------------------------
# 1. MSK 클러스터 삭제
# -----------------------------------------------------------------------------
echo ""
echo "[1/6] MSK 클러스터 삭제..."

MSK_CLUSTERS=$(aws kafka list-clusters --region "$REGION" \
  --query "ClusterInfoList[?contains(ClusterName, '$PROJECT')].ClusterArn" \
  --output text 2>/dev/null || echo "")

if [ -n "$MSK_CLUSTERS" ]; then
  while IFS= read -r arn; do
    [ -z "$arn" ] && continue
    NAME=$(echo "$arn" | rev | cut -d'/' -f2 | rev)
    echo "  - $NAME 삭제 중..."
    aws kafka delete-cluster --cluster-arn "$arn" --region "$REGION" 2>/dev/null || true
  done <<< "$MSK_CLUSTERS"
else
  echo "  - 삭제할 MSK 클러스터 없음"
fi

# -----------------------------------------------------------------------------
# 2. ElastiCache 클러스터 삭제
# -----------------------------------------------------------------------------
echo ""
echo "[2/6] ElastiCache 클러스터 삭제..."

CACHE_CLUSTERS=$(aws elasticache describe-cache-clusters --region "$REGION" \
  --query "CacheClusters[?contains(CacheClusterId, '$PROJECT')].CacheClusterId" \
  --output text 2>/dev/null || echo "")

if [ -n "$CACHE_CLUSTERS" ]; then
  for cache in $CACHE_CLUSTERS; do
    [ -z "$cache" ] && continue
    echo "  - $cache 삭제 중..."
    aws elasticache delete-cache-cluster --cache-cluster-id "$cache" --region "$REGION" 2>/dev/null || true
  done
else
  echo "  - 삭제할 ElastiCache 클러스터 없음"
fi

# -----------------------------------------------------------------------------
# 3. RDS 인스턴스 삭제 (스냅샷 없이)
# -----------------------------------------------------------------------------
echo ""
echo "[3/6] RDS 인스턴스 삭제..."

# 이름 기반으로 c4- 프리픽스 RDS 인스턴스 검색 (Tag 필터가 안될 수 있음)
RDS_INSTANCES=$(aws rds describe-db-instances --region "$REGION" \
  --query "DBInstances[?starts_with(DBInstanceIdentifier, '$PROJECT-')].DBInstanceIdentifier" \
  --output text 2>/dev/null || echo "")

if [ -n "$RDS_INSTANCES" ]; then
  for db in $RDS_INSTANCES; do
    [ -z "$db" ] && continue
    echo "  - $db 삭제 중... (스냅샷 생성 안함)"
    aws rds delete-db-instance \
      --db-instance-identifier "$db" \
      --skip-final-snapshot \
      --delete-automated-backups \
      --region "$REGION" 2>/dev/null || true
  done
else
  echo "  - 삭제할 RDS 인스턴스 없음"
fi

# -----------------------------------------------------------------------------
# 4. EKS 노드 그룹 삭제
# -----------------------------------------------------------------------------
echo ""
echo "[4/6] EKS 노드 그룹 삭제..."

CLUSTER_NAME="${PROJECT}-cluster"
NODE_GROUPS=$(aws eks list-nodegroups --cluster-name "$CLUSTER_NAME" --region "$REGION" \
  --query 'nodegroups[*]' --output text 2>/dev/null || echo "")

if [ -n "$NODE_GROUPS" ]; then
  for ng in $NODE_GROUPS; do
    [ -z "$ng" ] && continue
    echo "  - $ng 삭제 중..."
    aws eks delete-nodegroup \
      --cluster-name "$CLUSTER_NAME" \
      --nodegroup-name "$ng" \
      --region "$REGION" 2>/dev/null || true
  done
  echo "  노드 그룹 삭제 대기 중... (5-10분 소요)"
else
  echo "  - 삭제할 EKS 노드 그룹 없음"
fi

# -----------------------------------------------------------------------------
# 5. NAT Gateway 삭제
# -----------------------------------------------------------------------------
echo ""
echo "[5/6] NAT Gateway 삭제..."

# Name 태그에 프로젝트명이 포함된 NAT Gateway 검색
NAT_GATEWAYS=$(aws ec2 describe-nat-gateways --region "$REGION" \
  --filter "Name=state,Values=available" \
  --query "NatGateways[?Tags[?Key=='Name' && contains(Value, '$PROJECT')]].NatGatewayId" \
  --output text 2>/dev/null || echo "")

if [ -n "$NAT_GATEWAYS" ]; then
  for nat in $NAT_GATEWAYS; do
    [ -z "$nat" ] && continue
    echo "  - $nat 삭제 중..."
    aws ec2 delete-nat-gateway --nat-gateway-id "$nat" --region "$REGION" 2>/dev/null || true
  done
else
  echo "  - 삭제할 NAT Gateway 없음"
fi

# -----------------------------------------------------------------------------
# 6. EKS 클러스터 삭제 (선택적)
# -----------------------------------------------------------------------------
echo ""
echo "[6/6] EKS 클러스터..."
echo "  - EKS 클러스터는 노드 그룹 삭제 완료 후 terraform destroy로 삭제하세요"
echo "  - 또는: aws eks delete-cluster --name $CLUSTER_NAME --region $REGION"

# -----------------------------------------------------------------------------
# 완료
# -----------------------------------------------------------------------------
echo ""
echo "========================================"
echo "  삭제 요청 완료: $(date)"
echo "========================================"
echo ""
echo "삭제 상태 확인:"
echo "  - MSK: aws kafka list-clusters --region $REGION --query 'ClusterInfoList[*].[ClusterName,State]'"
echo "  - RDS: aws rds describe-db-instances --region $REGION --query 'DBInstances[*].[DBInstanceIdentifier,DBInstanceStatus]'"
echo "  - ElastiCache: aws elasticache describe-cache-clusters --region $REGION --query 'CacheClusters[*].[CacheClusterId,CacheClusterStatus]'"
echo "  - EKS 노드: aws eks list-nodegroups --cluster-name $CLUSTER_NAME --region $REGION"
echo ""
echo "완전 삭제 후 비용: \$0 (S3, Route53 등 일부 제외)"
echo ""
echo "다시 생성하려면:"
echo "  cd /Users/castle/Workspace/c4ang-infra/external-services/terraform/production"
echo "  terraform apply"
