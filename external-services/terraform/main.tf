# =============================================================================
# MSA External Data Services (AWS)
# PostgreSQL (RDS), Redis (ElastiCache), Kafka (MSK)
# =============================================================================
#
# 이 설정은 c4ang-terraform의 VPC, EKS 모듈에 의존합니다.
# terraform.tfvars에서 해당 리소스의 ID를 제공해야 합니다.
#
# 사용법:
#   1. terraform.tfvars.example을 terraform.tfvars로 복사
#   2. VPC, EKS 정보 입력
#   3. terraform init && terraform apply

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Component   = "external-services"
    }
  }
}

# 현재 AWS 계정 정보
data "aws_caller_identity" "current" {}

locals {
  name_prefix = "${var.project_name}-${var.environment}"

  # 서비스별 데이터베이스 정의
  databases = {
    customer = { name = "customer_db", port_offset = 0 }
    product  = { name = "product_db", port_offset = 1 }
    order    = { name = "order_db", port_offset = 2 }
    store    = { name = "store_db", port_offset = 3 }
    saga     = { name = "saga_db", port_offset = 4 }
  }

  # Redis 인스턴스 정의
  redis_instances = {
    cache   = { description = "Application cache" }
    session = { description = "Session store" }
  }
}

# =============================================================================
# RDS Subnet Group
# =============================================================================

resource "aws_db_subnet_group" "msa" {
  name       = "${local.name_prefix}-msa-db-subnet"
  subnet_ids = var.database_subnet_ids

  tags = {
    Name = "${local.name_prefix}-msa-db-subnet"
  }
}

# =============================================================================
# RDS Security Group
# =============================================================================

resource "aws_security_group" "rds" {
  name_prefix = "${local.name_prefix}-rds-"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.eks_node_security_group_id]
    description     = "PostgreSQL from EKS nodes"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-rds-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# =============================================================================
# RDS PostgreSQL Instances (서비스별)
# =============================================================================

resource "aws_db_instance" "msa" {
  for_each = var.create_rds ? local.databases : {}

  identifier = "${local.name_prefix}-${each.key}-db"

  # Engine
  engine         = "postgres"
  engine_version = var.rds_engine_version
  instance_class = var.rds_instance_class

  # Storage
  allocated_storage     = var.rds_allocated_storage
  max_allocated_storage = var.rds_max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true

  # Database
  db_name  = each.value.name
  username = var.rds_master_username
  password = var.rds_master_password

  # Network
  db_subnet_group_name   = aws_db_subnet_group.msa.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  # Backup
  backup_retention_period = var.environment == "prod" ? 7 : 1
  backup_window           = "03:00-04:00"
  maintenance_window      = "Mon:04:00-Mon:05:00"

  # HA (prod만)
  multi_az = var.environment == "prod"

  # Protection
  deletion_protection = var.environment == "prod"
  skip_final_snapshot = var.environment != "prod"
  final_snapshot_identifier = var.environment == "prod" ? "${local.name_prefix}-${each.key}-final" : null

  tags = {
    Name    = "${local.name_prefix}-${each.key}-db"
    Service = each.key
  }
}

# =============================================================================
# ElastiCache Subnet Group
# =============================================================================

resource "aws_elasticache_subnet_group" "msa" {
  count = var.create_elasticache ? 1 : 0

  name       = "${local.name_prefix}-redis-subnet"
  subnet_ids = var.database_subnet_ids

  tags = {
    Name = "${local.name_prefix}-redis-subnet"
  }
}

# =============================================================================
# ElastiCache Security Group
# =============================================================================

resource "aws_security_group" "redis" {
  count = var.create_elasticache ? 1 : 0

  name_prefix = "${local.name_prefix}-redis-"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [var.eks_node_security_group_id]
    description     = "Redis from EKS nodes"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-redis-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# =============================================================================
# ElastiCache Redis Clusters
# =============================================================================

resource "aws_elasticache_cluster" "msa" {
  for_each = var.create_elasticache ? local.redis_instances : {}

  cluster_id           = "${local.name_prefix}-${each.key}-redis"
  engine               = "redis"
  engine_version       = var.redis_engine_version
  node_type            = var.redis_node_type
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  port                 = 6379

  subnet_group_name  = aws_elasticache_subnet_group.msa[0].name
  security_group_ids = [aws_security_group.redis[0].id]

  snapshot_retention_limit = var.environment == "prod" ? 7 : 0

  tags = {
    Name    = "${local.name_prefix}-${each.key}-redis"
    Purpose = each.value.description
  }
}

# =============================================================================
# MSK (Kafka) - Optional
# =============================================================================
# MSK는 비용이 높으므로 필요시 활성화
# 대안: EKS 내 Strimzi Operator 사용 (charts/kafka-cluster)

resource "aws_msk_cluster" "msa" {
  count = var.create_msk ? 1 : 0

  cluster_name           = "${local.name_prefix}-kafka"
  kafka_version          = var.msk_kafka_version
  number_of_broker_nodes = var.environment == "prod" ? 3 : 2

  broker_node_group_info {
    instance_type   = var.msk_instance_type
    client_subnets  = var.database_subnet_ids
    security_groups = [aws_security_group.msk[0].id]

    storage_info {
      ebs_storage_info {
        volume_size = var.msk_ebs_volume_size
      }
    }
  }

  encryption_info {
    encryption_in_transit {
      client_broker = "TLS_PLAINTEXT"
      in_cluster    = true
    }
  }

  configuration_info {
    arn      = aws_msk_configuration.msa[0].arn
    revision = aws_msk_configuration.msa[0].latest_revision
  }

  tags = {
    Name = "${local.name_prefix}-kafka"
  }
}

resource "aws_msk_configuration" "msa" {
  count = var.create_msk ? 1 : 0

  name              = "${local.name_prefix}-kafka-config"
  kafka_versions    = [var.msk_kafka_version]

  server_properties = <<PROPERTIES
auto.create.topics.enable=true
default.replication.factor=3
min.insync.replicas=2
num.partitions=3
PROPERTIES
}

resource "aws_security_group" "msk" {
  count = var.create_msk ? 1 : 0

  name_prefix = "${local.name_prefix}-msk-"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 9092
    to_port         = 9098
    protocol        = "tcp"
    security_groups = [var.eks_node_security_group_id]
    description     = "Kafka from EKS nodes"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-msk-sg"
  }
}
