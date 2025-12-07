# =============================================================================
# Domain-specific RDS PostgreSQL Instances (물리적 분리)
# =============================================================================

locals {
  # 도메인별 데이터베이스 정의
  domain_databases = {
    customer = {
      db_name     = "customer_db"
      description = "Customer Service Database"
    }
    store = {
      db_name     = "store_db"
      description = "Store Service Database"
    }
    product = {
      db_name     = "product_db"
      description = "Product Service Database"
    }
    order = {
      db_name     = "order_db"
      description = "Order Service Database"
    }
    payment = {
      db_name     = "payment_db"
      description = "Payment Service Database"
    }
    saga = {
      db_name     = "saga_db"
      description = "Saga Tracker Database"
    }
  }
}

# =============================================================================
# 도메인별 RDS 인스턴스
# =============================================================================

resource "aws_db_instance" "domain_db" {
  for_each = var.create_domain_rds ? local.domain_databases : {}

  # 기본 설정
  identifier = "${var.project_name}-${each.key}-db"

  # 엔진 설정
  engine         = var.rds_engine
  engine_version = var.rds_engine_version
  instance_class = var.domain_rds_instance_class

  # 스토리지 설정
  allocated_storage     = var.domain_rds_allocated_storage
  max_allocated_storage = var.domain_rds_max_allocated_storage
  storage_type          = "gp2"
  storage_encrypted     = var.rds_storage_encrypted

  # 데이터베이스 설정
  db_name  = each.value.db_name
  username = var.rds_master_username
  password = var.rds_master_password

  # 네트워크 설정
  db_subnet_group_name   = aws_db_subnet_group.rds_subnet_group[0].name
  vpc_security_group_ids = [aws_security_group.rds_sg[0].id]
  publicly_accessible    = var.rds_public_access

  # 백업 설정
  backup_retention_period = var.rds_backup_retention_period
  backup_window           = var.rds_backup_window
  maintenance_window      = var.rds_maintenance_window

  # 고가용성 설정
  multi_az = var.rds_multi_az

  # 보안 설정
  deletion_protection = var.rds_deletion_protection
  skip_final_snapshot = var.rds_skip_final_snapshot

  # 모니터링 설정
  monitoring_interval = 0
  monitoring_role_arn = null

  # 성능 인사이트
  performance_insights_enabled = false

  tags = {
    Name        = "${var.project_name}-${each.key}-db"
    Environment = var.environment
    Owner       = var.owner
    CostCenter  = var.cost_center
    Purpose     = each.value.description
    Domain      = each.key
  }
}

# =============================================================================
# 도메인별 RDS 엔드포인트 출력
# =============================================================================

output "domain_rds_endpoints" {
  description = "Domain-specific RDS endpoints"
  value = var.create_domain_rds ? {
    for k, v in aws_db_instance.domain_db : k => {
      endpoint = v.endpoint
      address  = v.address
      port     = v.port
      db_name  = v.db_name
    }
  } : {}
}

output "domain_rds_connection_strings" {
  description = "Domain-specific JDBC connection strings"
  value = var.create_domain_rds ? {
    for k, v in aws_db_instance.domain_db : k => "jdbc:postgresql://${v.endpoint}/${v.db_name}"
  } : {}
  sensitive = true
}
