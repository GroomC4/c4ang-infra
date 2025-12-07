#!/bin/bash
# =============================================================================
# AWS 리소스 스케일 업 스크립트
# 스케일 다운된 리소스를 다시 운영 상태로 복구
# =============================================================================

set -e

CLUSTER_NAME="c4-cluster"
REGION="ap-northeast-2"

echo "=== AWS 리소스 스케일 업 시작 ==="
echo "시작 시간: $(date)"

# -----------------------------------------------------------------------------
# 1. RDS 인스턴스 시작 (먼저 시작 - 부팅 시간이 김)
# -----------------------------------------------------------------------------
echo ""
echo "[1/3] RDS 인스턴스 시작..."

RDS_INSTANCES=$(aws rds describe-db-instances --region $REGION \
  --query "DBInstances[?TagList[?Key=='Project' && Value=='c4']].DBInstanceIdentifier" \
  --output text 2>/dev/null)

for db in $RDS_INSTANCES; do
  STATUS=$(aws rds describe-db-instances --db-instance-identifier "$db" --region $REGION \
    --query 'DBInstances[0].DBInstanceStatus' --output text 2>/dev/null)

  if [ "$STATUS" == "stopped" ]; then
    echo "  - $db 시작 중..."
    aws rds start-db-instance --db-instance-identifier "$db" --region $REGION 2>/dev/null || true
  else
    echo "  - $db (상태: $STATUS)"
  fi
done

# -----------------------------------------------------------------------------
# 2. EKS 노드 그룹 스케일 업
# -----------------------------------------------------------------------------
echo ""
echo "[2/3] EKS 노드 그룹 스케일 업..."

# core-on: 2개
CORE_NG=$(aws eks list-nodegroups --cluster-name $CLUSTER_NAME --region $REGION \
  --query "nodegroups[?contains(@, 'core-on')]|[0]" --output text)
if [ -n "$CORE_NG" ] && [ "$CORE_NG" != "None" ]; then
  echo "  - $CORE_NG → 2개"
  aws eks update-nodegroup-config \
    --cluster-name $CLUSTER_NAME \
    --nodegroup-name "$CORE_NG" \
    --scaling-config minSize=2,maxSize=4,desiredSize=2 \
    --region $REGION 2>/dev/null || true
fi

# high-traffic: 1개
HIGH_NG=$(aws eks list-nodegroups --cluster-name $CLUSTER_NAME --region $REGION \
  --query "nodegroups[?contains(@, 'high-traffic')]|[0]" --output text)
if [ -n "$HIGH_NG" ] && [ "$HIGH_NG" != "None" ]; then
  echo "  - $HIGH_NG → 1개"
  aws eks update-nodegroup-config \
    --cluster-name $CLUSTER_NAME \
    --nodegroup-name "$HIGH_NG" \
    --scaling-config minSize=1,maxSize=4,desiredSize=1 \
    --region $REGION 2>/dev/null || true
fi

# low-traffic: 2개
LOW_NG=$(aws eks list-nodegroups --cluster-name $CLUSTER_NAME --region $REGION \
  --query "nodegroups[?contains(@, 'low-traffic')]|[0]" --output text)
if [ -n "$LOW_NG" ] && [ "$LOW_NG" != "None" ]; then
  echo "  - $LOW_NG → 2개"
  aws eks update-nodegroup-config \
    --cluster-name $CLUSTER_NAME \
    --nodegroup-name "$LOW_NG" \
    --scaling-config minSize=2,maxSize=4,desiredSize=2 \
    --region $REGION 2>/dev/null || true
fi

# kafka-storage, stateful-storage: 0개 유지 (AWS MSK/ElastiCache 사용)
echo "  - kafka-storage, stateful-storage: 0개 유지 (AWS 관리형 서비스 사용)"

# -----------------------------------------------------------------------------
# 3. RDS 상태 확인
# -----------------------------------------------------------------------------
echo ""
echo "[3/3] RDS 상태 확인 중... (완전히 시작되기까지 5-10분 소요)"

for db in $RDS_INSTANCES; do
  STATUS=$(aws rds describe-db-instances --db-instance-identifier "$db" --region $REGION \
    --query 'DBInstances[0].DBInstanceStatus' --output text 2>/dev/null)
  echo "  - $db: $STATUS"
done

# -----------------------------------------------------------------------------
# 완료
# -----------------------------------------------------------------------------
echo ""
echo "=== 스케일 업 요청 완료 ==="
echo "완료 시간: $(date)"
echo ""
echo "노드 그룹 상태 확인: aws eks list-nodegroups --cluster-name $CLUSTER_NAME"
echo "RDS 상태 확인: aws rds describe-db-instances --query 'DBInstances[*].[DBInstanceIdentifier,DBInstanceStatus]'"
echo ""
echo "모든 리소스가 준비되기까지 약 10-15분 소요됩니다."
