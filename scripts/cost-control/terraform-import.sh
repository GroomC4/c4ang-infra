#!/bin/bash
# =============================================================================
# Terraform Import Script
# 기존 AWS 리소스를 Terraform state에 import
# 실행 전 반드시 terraform init 실행 필요
# =============================================================================

set -e

TERRAFORM_DIR="/Users/castle/Workspace/c4ang-infra/external-services/terraform/production"
REGION="ap-northeast-2"

echo "========================================="
echo "  Terraform Import - AWS Resources"
echo "========================================="
echo ""
echo "WARNING: 이 스크립트는 기존 AWS 리소스를 Terraform state에 import합니다."
echo "         import 실패 시 수동으로 진행해야 할 수 있습니다."
echo ""

cd "$TERRAFORM_DIR"

# -----------------------------------------------------------------------------
# Terraform Init (필수)
# -----------------------------------------------------------------------------
echo "[0/7] Terraform 초기화..."
terraform init -upgrade

# -----------------------------------------------------------------------------
# 1. VPC-APP Import
# -----------------------------------------------------------------------------
echo ""
echo "[1/7] VPC-APP 리소스 Import..."

# VPC
echo "  - VPC..."
terraform import 'module.vpc_app.aws_vpc.this[0]' vpc-0f26099f532f44c82 2>/dev/null || echo "    (이미 import됨 또는 실패)"

# Internet Gateway
echo "  - Internet Gateway..."
terraform import 'module.vpc_app.aws_internet_gateway.this[0]' igw-0dcaeabb387188ee9 2>/dev/null || echo "    (이미 import됨 또는 실패)"

# Public Subnets
echo "  - Public Subnets..."
terraform import 'module.vpc_app.aws_subnet.public[0]' subnet-08adb9b5e9e980127 2>/dev/null || echo "    (이미 import됨 또는 실패)"
terraform import 'module.vpc_app.aws_subnet.public[1]' subnet-0d007efd4de9b541e 2>/dev/null || echo "    (이미 import됨 또는 실패)"
terraform import 'module.vpc_app.aws_subnet.public[2]' subnet-01e4fe7ff4fdaca98 2>/dev/null || echo "    (이미 import됨 또는 실패)"

# Private Subnets
echo "  - Private Subnets..."
terraform import 'module.vpc_app.aws_subnet.private[0]' subnet-082db99d913229b07 2>/dev/null || echo "    (이미 import됨 또는 실패)"
terraform import 'module.vpc_app.aws_subnet.private[1]' subnet-0c7a1a932d2e523ea 2>/dev/null || echo "    (이미 import됨 또는 실패)"
terraform import 'module.vpc_app.aws_subnet.private[2]' subnet-0c8fbe044cbca4545 2>/dev/null || echo "    (이미 import됨 또는 실패)"

# NAT Gateway
echo "  - NAT Gateway..."
terraform import 'module.vpc_app.aws_nat_gateway.this[0]' nat-033fe4d9a14a3edbe 2>/dev/null || echo "    (이미 import됨 또는 실패)"

# Route Tables
echo "  - Route Tables..."
terraform import 'module.vpc_app.aws_route_table.public[0]' rtb-0fce92fbd826c3f9d 2>/dev/null || echo "    (이미 import됨 또는 실패)"
terraform import 'module.vpc_app.aws_route_table.private[0]' rtb-010c4a815431bdec4 2>/dev/null || echo "    (이미 import됨 또는 실패)"

# -----------------------------------------------------------------------------
# 2. VPC-DB Import
# -----------------------------------------------------------------------------
echo ""
echo "[2/7] VPC-DB 리소스 Import..."

# VPC
echo "  - VPC..."
terraform import 'module.vpc_db.aws_vpc.this[0]' vpc-005baa0446f0c787c 2>/dev/null || echo "    (이미 import됨 또는 실패)"

# Private Subnets
echo "  - Private Subnets..."
terraform import 'module.vpc_db.aws_subnet.private[0]' subnet-072a0af4e2df44fdf 2>/dev/null || echo "    (이미 import됨 또는 실패)"
terraform import 'module.vpc_db.aws_subnet.private[1]' subnet-00e042142706b61e4 2>/dev/null || echo "    (이미 import됨 또는 실패)"
terraform import 'module.vpc_db.aws_subnet.private[2]' subnet-08a2cce7cb3d427ca 2>/dev/null || echo "    (이미 import됨 또는 실패)"

# -----------------------------------------------------------------------------
# 3. VPC Peering Import
# -----------------------------------------------------------------------------
echo ""
echo "[3/7] VPC Peering Import..."
terraform import 'aws_vpc_peering_connection.app_to_db' pcx-095c16bb098761295 2>/dev/null || echo "    (이미 import됨 또는 실패)"

# -----------------------------------------------------------------------------
# 4. EKS Cluster Import
# -----------------------------------------------------------------------------
echo ""
echo "[4/7] EKS 클러스터 Import..."

# EKS Cluster
echo "  - EKS Cluster..."
terraform import 'module.eks[0].aws_eks_cluster.this[0]' c4-cluster 2>/dev/null || echo "    (이미 import됨 또는 실패)"

# Node Groups
echo "  - Node Groups..."
terraform import 'module.eks[0].module.eks_managed_node_group["core-on"].aws_eks_node_group.this[0]' 'c4-cluster:core-on-2025120406513330660000000f' 2>/dev/null || echo "    (이미 import됨 또는 실패)"
terraform import 'module.eks[0].module.eks_managed_node_group["high-traffic"].aws_eks_node_group.this[0]' 'c4-cluster:high-traffic-2025120406513330630000000d' 2>/dev/null || echo "    (이미 import됨 또는 실패)"
terraform import 'module.eks[0].module.eks_managed_node_group["low-traffic"].aws_eks_node_group.this[0]' 'c4-cluster:low-traffic-20251204065133307400000015' 2>/dev/null || echo "    (이미 import됨 또는 실패)"
terraform import 'module.eks[0].module.eks_managed_node_group["kafka-storage"].aws_eks_node_group.this[0]' 'c4-cluster:kafka-storage-20251204065133306900000011' 2>/dev/null || echo "    (이미 import됨 또는 실패)"
terraform import 'module.eks[0].module.eks_managed_node_group["stateful-storage"].aws_eks_node_group.this[0]' 'c4-cluster:stateful-storage-20251204065133307300000013' 2>/dev/null || echo "    (이미 import됨 또는 실패)"

# -----------------------------------------------------------------------------
# 5. RDS Import
# -----------------------------------------------------------------------------
echo ""
echo "[5/7] RDS 인스턴스 Import..."

# Domain RDS Instances
echo "  - Domain RDS Instances..."
terraform import 'aws_db_instance.domain_rds["app"]' c4-app-db 2>/dev/null || echo "    (이미 import됨 또는 실패)"
terraform import 'aws_db_instance.domain_rds["customer"]' c4-customer-db 2>/dev/null || echo "    (이미 import됨 또는 실패)"
terraform import 'aws_db_instance.domain_rds["order"]' c4-order-db 2>/dev/null || echo "    (이미 import됨 또는 실패)"
terraform import 'aws_db_instance.domain_rds["payment"]' c4-payment-db 2>/dev/null || echo "    (이미 import됨 또는 실패)"
terraform import 'aws_db_instance.domain_rds["product"]' c4-product-db 2>/dev/null || echo "    (이미 import됨 또는 실패)"
terraform import 'aws_db_instance.domain_rds["saga"]' c4-saga-db 2>/dev/null || echo "    (이미 import됨 또는 실패)"
terraform import 'aws_db_instance.domain_rds["store"]' c4-store-db 2>/dev/null || echo "    (이미 import됨 또는 실패)"

# -----------------------------------------------------------------------------
# 6. ElastiCache Import
# -----------------------------------------------------------------------------
echo ""
echo "[6/7] ElastiCache Import..."

echo "  - Cache Redis..."
terraform import 'aws_elasticache_cluster.cache_redis[0]' c4-cache-redis 2>/dev/null || echo "    (이미 import됨 또는 실패)"

echo "  - Session Redis..."
terraform import 'aws_elasticache_cluster.session_redis[0]' c4-session-redis 2>/dev/null || echo "    (이미 import됨 또는 실패)"

# -----------------------------------------------------------------------------
# 7. MSK Import
# -----------------------------------------------------------------------------
echo ""
echo "[7/7] MSK 클러스터 Import..."

MSK_ARN=$(aws kafka list-clusters --region $REGION \
  --query "ClusterInfoList[?ClusterName=='c4-kafka-m7g'].ClusterArn" \
  --output text 2>/dev/null)

if [ -n "$MSK_ARN" ] && [ "$MSK_ARN" != "None" ]; then
  echo "  - MSK Cluster: $MSK_ARN"
  terraform import 'aws_msk_cluster.this[0]' "$MSK_ARN" 2>/dev/null || echo "    (이미 import됨 또는 실패)"
else
  echo "  - MSK Cluster not found"
fi

# -----------------------------------------------------------------------------
# 완료 및 검증
# -----------------------------------------------------------------------------
echo ""
echo "========================================="
echo "  Import 완료 - 검증 실행"
echo "========================================="
echo ""

echo "Terraform Plan 실행 중..."
terraform plan -out=verify.tfplan 2>&1 | head -50

echo ""
echo "========================================="
echo "  Import 결과"
echo "========================================="
echo ""
echo "State 파일 확인:"
ls -la terraform.tfstate
echo ""
echo "리소스 수:"
terraform state list 2>/dev/null | wc -l
echo ""
echo "다음 단계:"
echo "  1. terraform plan 출력 검토"
echo "  2. 변경사항이 있으면 tfvars 조정"
echo "  3. 변경사항이 없으면 import 완료"
echo ""
rm -f verify.tfplan 2>/dev/null
