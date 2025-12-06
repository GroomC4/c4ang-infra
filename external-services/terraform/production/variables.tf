# =============================================================================
# 기본 설정
# =============================================================================

# AWS Region
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-2"
}

# Project Name
variable "project_name" {
  description = "Project name"
  type        = string
  default     = "c4"
}

# Environment
variable "environment" {
  description = "Environment name (e.g., dev, test, staging, production)"
  type        = string
  default     = "production"
}

# Environment Suffix (for naming)
variable "environment_suffix" {
  description = "Environment suffix for resource naming (e.g., -dev, -test, -staging, -prod)"
  type        = string
  default     = ""
}

# Resource Naming Prefix
variable "resource_prefix" {
  description = "Prefix for all resource names"
  type        = string
  default     = "c4"
}

# Owner
variable "owner" {
  description = "Resource owner"
  type        = string
  default     = "c4-team"
}

# Cost Center
variable "cost_center" {
  description = "Cost center for billing"
  type        = string
  default     = "c4-network"
}

# =============================================================================
# EKS 설정
# =============================================================================

# EKS Cluster Creation Flag
variable "create_eks_cluster" {
  description = "Whether to create EKS cluster"
  type        = bool
  default     = true
}

# EKS Cluster Configuration
variable "eks_cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = ""
}

# =============================================================================
# EKS 노드그룹 설정 (최소 사양)
# =============================================================================

variable "core_node_group" {
  description = "Core node group for system addons and shared services"
  type = object({
    instance_types = list(string)
    min_size       = number
    desired_size   = number
    max_size       = number
    disk_size      = number
  })
  default = {
    instance_types = ["t3.large"]
    min_size       = 1
    desired_size   = 1
    max_size       = 1
    disk_size      = 40
  }
}

variable "high_traffic_node_group" {
  description = "Node group for high traffic workloads"
  type = object({
    instance_types = list(string)
    min_size       = number
    desired_size   = number
    max_size       = number
    disk_size      = number
  })
  default = {
    instance_types = ["t3.large"]
    min_size       = 1
    desired_size   = 1
    max_size       = 1
    disk_size      = 40
  }
}

variable "low_traffic_node_group" {
  description = "Node group for low traffic supporting services"
  type = object({
    instance_types = list(string)
    min_size       = number
    desired_size   = number
    max_size       = number
    disk_size      = number
  })
  default = {
    instance_types = ["t3.medium"]
    min_size       = 1
    desired_size   = 1
    max_size       = 1
    disk_size      = 40
  }
}

variable "stateful_storage_node_group" {
  description = "Node group for Redis, Loki and other stateful workloads"
  type = object({
    instance_types = list(string)
    min_size       = number
    desired_size   = number
    max_size       = number
    disk_size      = number
  })
  default = {
    instance_types = ["m5.large"]
    min_size       = 1
    desired_size   = 1
    max_size       = 1
    disk_size      = 100
  }
}

variable "kafka_storage_node_group" {
  description = "Node group for Kafka StatefulSet workloads"
  type = object({
    instance_types = list(string)
    min_size       = number
    desired_size   = number
    max_size       = number
    disk_size      = number
  })
  default = {
    instance_types = ["m5.large"]
    min_size       = 1
    desired_size   = 1
    max_size       = 1
    disk_size      = 200
  }
}

# 베스천 호스트 접근용 IP 주소
variable "my_ip_for_bastion" {
  description = "Your IP address for bastion host access"
  type        = string
  default     = "0.0.0.0/32"
}

# Bastion Host AMI ID (e.g., Amazon Linux 2023 in ap-northeast-2)
variable "bastion_ami_id" {
  description = "AMI ID for Bastion Host"
  type        = string
  default     = ""
}

# Bastion Host key pair name
variable "bastion_key_pair_name" {
  description = "Key pair name for Bastion Host"
  type        = string
  default     = "bastion"
}

# GPU 노드그룹 - AWS GPU 인스턴스 제한으로 인해 주석처리
# 필요시 AWS Support에 GPU 인스턴스 제한 해제 요청 후 활성화
# variable "gpu_node_group" {
#   description = "GPU node group configuration"
#   type = object({
#     instance_types = list(string)
#     min_size       = number
#     max_size       = number
#     desired_size   = number
#     disk_size      = number
#     capacity_type  = string
#   })
#   default = {
#     instance_types = ["g5.xlarge", "g6.xlarge"]
#     min_size       = 0
#     max_size       = 6
#     desired_size   = 0
#     disk_size      = 20
#     capacity_type  = "SPOT"
#   }
# }

# =============================================================================
# 가용영역 및 네트워크 설정
# =============================================================================

# Availability Zones
variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
  default     = ["ap-northeast-2a", "ap-northeast-2b", "ap-northeast-2c"]
}

# VPC CIDR Blocks
variable "vpc_db_cidr" {
  description = "CIDR block for VPC-DB"
  type        = string
  default     = "172.21.0.0/16"
}

variable "vpc_app_cidr" {
  description = "CIDR block for VPC-APP"
  type        = string
  default     = "172.20.0.0/16"
}

# VPC-DB Private Subnets
variable "vpc_db_private_subnets" {
  description = "Private subnets for VPC-DB"
  type        = list(string)
  default = [
    "172.21.0.0/20",  # Private-DB AZ-a
    "172.21.16.0/20", # Private-DB AZ-b
    "172.21.32.0/20"  # Private-DB AZ-c
  ]
}

# VPC-APP Public Subnets
variable "vpc_app_public_subnets" {
  description = "Public subnets for VPC-APP"
  type        = list(string)
  default = [
    "172.20.0.0/20",  # Public AZ-a
    "172.20.16.0/20", # Public AZ-b
    "172.20.32.0/20"  # Public AZ-c
  ]
}

# VPC-APP Private Subnets
variable "vpc_app_private_subnets" {
  description = "Private subnets for VPC-APP"
  type        = list(string)
  default = [
    "172.20.48.0/20", # Private AZ-a
    "172.20.64.0/20", # Private AZ-b
    "172.20.80.0/20"  # Private AZ-c
  ]
}


# NAT/VPN 비용 제어 플래그
variable "enable_nat_gateway" {
  description = "Enable NAT gateway for VPC-APP (costly resource)"
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Use single NAT gateway instead of one per AZ"
  type        = bool
  default     = true
}



# =============================================================================
# RDS 데이터베이스 설정
# =============================================================================

# RDS 생성 여부
variable "create_rds" {
  description = "Whether to create RDS database"
  type        = bool
  default     = true
}

# RDS 엔진 타입
variable "rds_engine" {
  description = "RDS engine type"
  type        = string
  default     = "postgres"
}

# RDS 엔진 버전
variable "rds_engine_version" {
  description = "RDS engine version"
  type        = string
  default     = "17.6" # PostgreSQL 15.4 대신 15.3 사용
}

# RDS 인스턴스 클래스
variable "rds_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro" # 테스트 환경용 작은 인스턴스
}

# RDS 할당 스토리지
variable "rds_allocated_storage" {
  description = "RDS allocated storage in GB"
  type        = number
  default     = 20
}

# RDS 최대 할당 스토리지 (자동 스케일링)
variable "rds_max_allocated_storage" {
  description = "RDS max allocated storage for autoscaling"
  type        = number
  default     = 100
}

# RDS 데이터베이스 이름
variable "rds_database_name" {
  description = "RDS database name"
  type        = string
  default     = "app"
}

# RDS 마스터 사용자명
variable "rds_master_username" {
  description = "RDS master username"
  type        = string
  default     = "appuser"
}

# RDS 마스터 비밀번호
variable "rds_master_password" {
  description = "RDS master password"
  type        = string
  sensitive   = true
  default     = "airflow123!"
}

# RDS 백업 보존 기간
variable "rds_backup_retention_period" {
  description = "RDS backup retention period in days"
  type        = number
  default     = 7
}

# RDS 백업 윈도우
variable "rds_backup_window" {
  description = "RDS backup window"
  type        = string
  default     = "03:00-04:00"
}

# RDS 유지보수 윈도우
variable "rds_maintenance_window" {
  description = "RDS maintenance window"
  type        = string
  default     = "sun:04:00-sun:05:00"
}

# RDS 멀티 AZ 배포
variable "rds_multi_az" {
  description = "RDS multi-AZ deployment"
  type        = bool
  default     = false # 테스트 환경에서는 비용 절약을 위해 false
}

# RDS 스토리지 암호화
variable "rds_storage_encrypted" {
  description = "RDS storage encryption"
  type        = bool
  default     = true
}

# RDS 삭제 보호
variable "rds_deletion_protection" {
  description = "RDS deletion protection"
  type        = bool
  default     = false # 테스트 환경에서는 false
}

# RDS 스킵 최종 스냅샷
variable "rds_skip_final_snapshot" {
  description = "RDS skip final snapshot"
  type        = bool
  default     = true # 테스트 환경에서는 true
}

# RDS 퍼블릭 액세스 (테스트용)
variable "rds_public_access" {
  description = "Whether to expose RDS instance publicly (not recommended for production)"
  type        = bool
  default     = false
}

# RDS 퍼블릭 액세스 시 허용할 CIDR 목록
variable "rds_allowed_cidr_blocks" {
  description = "Additional CIDR blocks allowed to access RDS (will always include VPC-APP CIDR)"
  type        = list(string)
  default     = []
}

# =============================================================================
# MSK (Amazon Managed Streaming for Apache Kafka) 설정
# =============================================================================

# MSK 생성 여부
variable "create_msk" {
  description = "Whether to create MSK Kafka cluster"
  type        = bool
  default     = false # 기본 비활성화 (비용 주의)
}

# MSK 인스턴스 타입
variable "msk_instance_type" {
  description = "MSK broker instance type"
  type        = string
  default     = "kafka.m5.large" # 최소 지원 인스턴스 타입 (kafka.t3.small은 지원 안됨)
}

# MSK Kafka 버전
variable "msk_kafka_version" {
  description = "Kafka version for MSK (3.7+ supports KRaft mode)"
  type        = string
  default     = "3.7.0" # KRaft 모드 지원 버전
}

# MSK KRaft 모드 사용 여부
variable "msk_use_kraft" {
  description = "Whether to use KRaft mode (requires Kafka 3.7+, no Zookeeper needed)"
  type        = bool
  default     = true # 기본값: KRaft 모드 사용
}

# MSK EBS 볼륨 크기 (GB)
variable "msk_ebs_volume_size" {
  description = "EBS volume size per broker (GB)"
  type        = number
  default     = 100
}

# =============================================================================
# S3 버킷 설정
# =============================================================================

# S3 버킷 생성 여부
variable "create_s3_buckets" {
  description = "Whether to create S3 buckets for Airflow logs and Spark checkpoints"
  type        = bool
  default     = true
}

# Airflow 로그용 S3 버킷 이름
variable "airflow_logs_bucket_name" {
  description = "S3 bucket name for Airflow logs (empty string = auto-generate with environment suffix and account ID)"
  type        = string
  default     = "" # 빈 값이면 자동 생성: c4-airflow-logs-{environment}-{account-id-last-6}
}

# Tracking log용 S3 버킷 이름
variable "tracking_log_bucket_name" {
  description = "S3 bucket name for tracking logs (empty string = use default: c4-tracking-log)"
  type        = string
  default     = "" # 빈 값이면 기본값 사용: c4-tracking-log
}

# S3 버킷 버전 관리
variable "s3_bucket_versioning" {
  description = "S3 bucket versioning"
  type        = bool
  default     = true
}

# S3 버킷 암호화
variable "s3_bucket_encryption" {
  description = "S3 bucket encryption"
  type        = bool
  default     = true
}

# S3 버킷 생명주기 정책 (로그 정리)
variable "s3_lifecycle_enabled" {
  description = "Enable S3 lifecycle policy for log cleanup"
  type        = bool
  default     = true
}

# S3 로그 보존 기간 (일)
variable "s3_log_retention_days" {
  description = "S3 log retention period in days"
  type        = number
  default     = 30
}

# Kubernetes 리소스 설정
# =============================================================================

# Kubernetes 리소스 생성 여부
variable "create_k8s_resources" {
  description = "Whether to create Kubernetes resources (namespaces, service accounts)"
  type        = bool
  default     = false # 기본적으로 비활성화 (EKS 클러스터 생성 후 별도 배포)

}

# =============================================================================
# EKS 보안 설정
# =============================================================================

# EKS 퍼블릭 액세스 허용 여부
variable "eks_public_access_enabled" {
  description = "Whether to enable public access to EKS cluster endpoint"
  type        = bool
  default     = true
}

# 추가 IP CIDR 블록 (현재 IP 외에 추가로 허용할 IP들)
variable "eks_additional_public_access_cidrs" {
  description = "Additional CIDR blocks for EKS public access (besides current IP)"
  type        = list(string)
  default     = [] # 현재 IP만 허용 (보안 강화)
}

# 모든 IP 허용 여부 (보안상 권장하지 않음)
variable "eks_allow_all_ips" {
  description = "Whether to allow all IPs (0.0.0.0/0) - NOT RECOMMENDED for production"
  type        = bool
  default     = false # 보안을 위해 현재 IP만 허용
}
