# =============================================================================
# Variables for MSA External Data Services
# =============================================================================

# -----------------------------------------------------------------------------
# 기본 설정
# -----------------------------------------------------------------------------

variable "aws_region" {
  description = "AWS 리전"
  type        = string
  default     = "ap-northeast-2"
}

variable "project_name" {
  description = "프로젝트 이름 (태그 및 리소스 명명에 사용)"
  type        = string
  default     = "c4ang"
}

variable "environment" {
  description = "환경 (dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment는 dev, staging, prod 중 하나여야 합니다."
  }
}

# -----------------------------------------------------------------------------
# 네트워크 설정 (c4ang-terraform 모듈 출력값)
# -----------------------------------------------------------------------------

variable "vpc_id" {
  description = "VPC ID (c4ang-terraform의 VPC 모듈 출력값)"
  type        = string
}

variable "database_subnet_ids" {
  description = "데이터베이스 서브넷 ID 목록 (최소 2개, 다른 AZ)"
  type        = list(string)

  validation {
    condition     = length(var.database_subnet_ids) >= 2
    error_message = "데이터베이스 서브넷은 최소 2개 필요합니다."
  }
}

variable "eks_node_security_group_id" {
  description = "EKS 노드 보안 그룹 ID (데이터베이스 접근 허용용)"
  type        = string
}

# -----------------------------------------------------------------------------
# RDS PostgreSQL 설정
# -----------------------------------------------------------------------------

variable "create_rds" {
  description = "RDS PostgreSQL 인스턴스 생성 여부"
  type        = bool
  default     = true
}

variable "rds_instance_class" {
  description = "RDS 인스턴스 클래스"
  type        = string
  default     = "db.t3.micro"  # 개발용, 프로덕션은 db.r6g.large 권장
}

variable "rds_engine_version" {
  description = "PostgreSQL 엔진 버전"
  type        = string
  default     = "15.4"
}

variable "rds_allocated_storage" {
  description = "초기 스토리지 크기 (GB)"
  type        = number
  default     = 20
}

variable "rds_max_allocated_storage" {
  description = "자동 확장 최대 스토리지 크기 (GB)"
  type        = number
  default     = 100
}

variable "rds_master_username" {
  description = "RDS 마스터 사용자 이름"
  type        = string
  default     = "postgres"
}

variable "rds_master_password" {
  description = "RDS 마스터 비밀번호 (최소 8자)"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.rds_master_password) >= 8
    error_message = "RDS 비밀번호는 최소 8자 이상이어야 합니다."
  }
}

# -----------------------------------------------------------------------------
# ElastiCache Redis 설정
# -----------------------------------------------------------------------------

variable "create_elasticache" {
  description = "ElastiCache Redis 클러스터 생성 여부"
  type        = bool
  default     = true
}

variable "redis_node_type" {
  description = "Redis 노드 타입"
  type        = string
  default     = "cache.t3.micro"  # 개발용, 프로덕션은 cache.r6g.large 권장
}

variable "redis_engine_version" {
  description = "Redis 엔진 버전"
  type        = string
  default     = "7.0"
}

# -----------------------------------------------------------------------------
# MSK Kafka 설정 (선택적 - 비용 높음)
# -----------------------------------------------------------------------------

variable "create_msk" {
  description = "MSK Kafka 클러스터 생성 여부 (비용 주의)"
  type        = bool
  default     = false  # 기본 비활성화, K8s 내 Strimzi 사용 권장
}

variable "msk_instance_type" {
  description = "MSK 브로커 인스턴스 타입"
  type        = string
  default     = "kafka.t3.small"  # 개발용, 프로덕션은 kafka.m5.large 권장
}

variable "msk_kafka_version" {
  description = "Kafka 버전"
  type        = string
  default     = "3.6.0"
}

variable "msk_ebs_volume_size" {
  description = "브로커당 EBS 볼륨 크기 (GB)"
  type        = number
  default     = 100
}
