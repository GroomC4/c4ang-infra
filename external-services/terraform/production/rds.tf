# =============================================================================
# RDS PostgreSQL Database for Airflow
# =============================================================================

locals {
  rds_target_vpc_id     = var.rds_public_access ? module.vpc_app.vpc_id : module.vpc_db.vpc_id
  rds_target_subnet_ids = var.rds_public_access ? module.vpc_app.public_subnets : module.vpc_db.private_subnets
  rds_allowed_cidrs     = distinct(concat(var.rds_allowed_cidr_blocks, [var.vpc_app_cidr]))
  rds_eks_node_sg_id    = try(module.eks[0].node_security_group_id, null)
}

# RDS 서브넷 그룹 (필요 시 VPC-APP의 퍼블릭 서브넷 사용)
# create_rds 또는 create_domain_rds가 true이면 생성
resource "aws_db_subnet_group" "rds_subnet_group" {
  count = (var.create_rds || var.create_domain_rds) ? 1 : 0
  
  name       = "${var.project_name}-rds-subnet-group"
  subnet_ids = local.rds_target_subnet_ids

  tags = {
    Name        = "${var.project_name}-rds-subnet-group"
    Environment = var.environment
    Owner       = var.owner
    CostCenter  = var.cost_center
  }
}

# RDS 보안 그룹 (EKS 클러스터에서만 접근 허용)
# create_rds 또는 create_domain_rds가 true이면 생성
resource "aws_security_group" "rds_sg" {
  count = (var.create_rds || var.create_domain_rds) ? 1 : 0
  
  name_prefix = "${var.project_name}-rds-sg-"
  vpc_id      = local.rds_target_vpc_id

  # PostgreSQL 포트 (5432) - EKS 노드 SG 허용
  dynamic "ingress" {
    for_each = local.rds_eks_node_sg_id != null ? [local.rds_eks_node_sg_id] : []
    content {
      from_port       = 5432
      to_port         = 5432
      protocol        = "tcp"
      security_groups = [ingress.value]
      description     = "Allow PostgreSQL access from EKS nodes"
    }
  }

  # CIDR 기반 접근 허용 (기본적으로 VPC-APP CIDR 포함)
  dynamic "ingress" {
    for_each = toset(local.rds_allowed_cidrs)
    content {
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
      description = "Allow PostgreSQL access from allowed CIDRs"
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
    Name        = "${var.project_name}-rds-sg"
    Environment = var.environment
    Owner       = var.owner
    CostCenter  = var.cost_center
  }
}

# RDS PostgreSQL 인스턴스
resource "aws_db_instance" "airflow_db" {
  count = var.create_rds ? 1 : 0
  
  # 기본 설정
  identifier = "${var.project_name}-app-db"
  
  # 엔진 설정
  engine         = var.rds_engine
  engine_version = var.rds_engine_version
  instance_class = var.rds_instance_class
  
  # 스토리지 설정
  allocated_storage     = var.rds_allocated_storage
  max_allocated_storage = var.rds_max_allocated_storage
  storage_type          = "gp2"
  storage_encrypted     = var.rds_storage_encrypted
  
  # 데이터베이스 설정
  db_name  = var.rds_database_name
  username = var.rds_master_username
  password = var.rds_master_password
  
  # 네트워크 설정
  db_subnet_group_name   = aws_db_subnet_group.rds_subnet_group[0].name
  vpc_security_group_ids = [aws_security_group.rds_sg[0].id]
  publicly_accessible    = var.rds_public_access  # 테스트용 퍼블릭 노출 옵션
  
  # 백업 설정
  backup_retention_period = var.rds_backup_retention_period
  backup_window          = var.rds_backup_window
  maintenance_window     = var.rds_maintenance_window
  
  # 고가용성 설정
  multi_az = var.rds_multi_az
  
  # 보안 설정
  deletion_protection = var.rds_deletion_protection
  skip_final_snapshot = var.rds_skip_final_snapshot
  
  # 모니터링 설정
  monitoring_interval = 0  # 테스트 환경에서는 Enhanced Monitoring 비활성화
  monitoring_role_arn = null
  
  # 성능 인사이트
  performance_insights_enabled = false  # 테스트 환경에서는 비활성화
  
  tags = {
    Name        = "${var.project_name}-app-db"
    Environment = var.environment
    Owner       = var.owner
    CostCenter  = var.cost_center
    Purpose     = "Application Database"
  }
}

# RDS 엔드포인트 출력을 위한 데이터 소스
data "aws_db_instance" "airflow_db" {
  count = var.create_rds ? 1 : 0
  
  db_instance_identifier = aws_db_instance.airflow_db[0].identifier
  depends_on             = [aws_db_instance.airflow_db]
}

