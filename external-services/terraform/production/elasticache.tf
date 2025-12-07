# =============================================================================
# AWS ElastiCache Redis Cluster
# =============================================================================

locals {
  elasticache_target_vpc_id     = module.vpc_db.vpc_id
  elasticache_target_subnet_ids = module.vpc_db.private_subnets
  elasticache_allowed_cidrs     = [var.vpc_app_cidr]
  elasticache_eks_node_sg_id    = try(module.eks[0].node_security_group_id, null)
}

# =============================================================================
# ElastiCache 서브넷 그룹
# =============================================================================

resource "aws_elasticache_subnet_group" "redis" {
  count = var.create_elasticache ? 1 : 0

  name       = "${var.project_name}-redis-subnet-group"
  subnet_ids = local.elasticache_target_subnet_ids

  tags = {
    Name        = "${var.project_name}-redis-subnet-group"
    Environment = var.environment
    Owner       = var.owner
    CostCenter  = var.cost_center
  }
}

# =============================================================================
# ElastiCache 보안 그룹
# =============================================================================

resource "aws_security_group" "elasticache_sg" {
  count = var.create_elasticache ? 1 : 0

  name_prefix = "${var.project_name}-elasticache-sg-"
  vpc_id      = local.elasticache_target_vpc_id

  # Redis 포트 (6379) - EKS 노드 SG 허용
  dynamic "ingress" {
    for_each = local.elasticache_eks_node_sg_id != null ? [local.elasticache_eks_node_sg_id] : []
    content {
      from_port       = 6379
      to_port         = 6379
      protocol        = "tcp"
      security_groups = [ingress.value]
      description     = "Allow Redis access from EKS nodes"
    }
  }

  # CIDR 기반 접근 허용 (VPC-APP CIDR)
  dynamic "ingress" {
    for_each = toset(local.elasticache_allowed_cidrs)
    content {
      from_port   = 6379
      to_port     = 6379
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
      description = "Allow Redis access from VPC-APP"
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name        = "${var.project_name}-elasticache-sg"
    Environment = var.environment
    Owner       = var.owner
    CostCenter  = var.cost_center
  }
}

# =============================================================================
# ElastiCache Redis Cluster (Cache용)
# =============================================================================

resource "aws_elasticache_cluster" "cache_redis" {
  count = var.create_elasticache ? 1 : 0

  cluster_id           = "${var.project_name}-cache-redis"
  engine               = "redis"
  engine_version       = var.elasticache_engine_version
  node_type            = var.elasticache_node_type
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  port                 = 6379

  subnet_group_name  = aws_elasticache_subnet_group.redis[0].name
  security_group_ids = [aws_security_group.elasticache_sg[0].id]

  # 스냅샷 설정
  snapshot_retention_limit = var.elasticache_snapshot_retention
  snapshot_window          = "03:00-04:00"
  maintenance_window       = "sun:04:00-sun:05:00"

  # 자동 마이너 버전 업그레이드
  auto_minor_version_upgrade = true

  tags = {
    Name        = "${var.project_name}-cache-redis"
    Environment = var.environment
    Owner       = var.owner
    CostCenter  = var.cost_center
    Purpose     = "Application Cache"
  }
}

# =============================================================================
# ElastiCache Redis Cluster (Session용)
# =============================================================================

resource "aws_elasticache_cluster" "session_redis" {
  count = var.create_elasticache ? 1 : 0

  cluster_id           = "${var.project_name}-session-redis"
  engine               = "redis"
  engine_version       = var.elasticache_engine_version
  node_type            = var.elasticache_node_type
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  port                 = 6379

  subnet_group_name  = aws_elasticache_subnet_group.redis[0].name
  security_group_ids = [aws_security_group.elasticache_sg[0].id]

  # 스냅샷 설정
  snapshot_retention_limit = var.elasticache_snapshot_retention
  snapshot_window          = "03:00-04:00"
  maintenance_window       = "sun:04:00-sun:05:00"

  # 자동 마이너 버전 업그레이드
  auto_minor_version_upgrade = true

  tags = {
    Name        = "${var.project_name}-session-redis"
    Environment = var.environment
    Owner       = var.owner
    CostCenter  = var.cost_center
    Purpose     = "Session Storage"
  }
}

# =============================================================================
# ElastiCache 출력
# =============================================================================

output "elasticache_cache_redis_endpoint" {
  description = "ElastiCache Cache Redis endpoint"
  value       = var.create_elasticache ? aws_elasticache_cluster.cache_redis[0].cache_nodes[0].address : null
}

output "elasticache_session_redis_endpoint" {
  description = "ElastiCache Session Redis endpoint"
  value       = var.create_elasticache ? aws_elasticache_cluster.session_redis[0].cache_nodes[0].address : null
}

output "elasticache_redis_port" {
  description = "ElastiCache Redis port"
  value       = var.create_elasticache ? 6379 : null
}
