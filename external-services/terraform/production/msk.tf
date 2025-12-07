# =============================================================================
# Amazon MSK (Managed Streaming for Apache Kafka)
# KRaft 모드 - Zookeeper 없이 운영
# =============================================================================

# MSK 생성 여부
variable "create_msk" {
  description = "Whether to create MSK cluster"
  type        = bool
  default     = true
}

# MSK 인스턴스 타입
variable "msk_instance_type" {
  description = "MSK broker instance type"
  type        = string
  default     = "kafka.m7g.large"  # KRaft 모드 최소 사양 (Graviton)
}

# MSK 브로커 수
variable "msk_broker_count" {
  description = "Number of MSK brokers (must be multiple of AZ count)"
  type        = number
  default     = 3
}

# MSK Kafka 버전
variable "msk_kafka_version" {
  description = "Kafka version for MSK"
  type        = string
  default     = "3.7.x.kraft"  # KRaft 모드
}

# MSK EBS 볼륨 크기
variable "msk_ebs_volume_size" {
  description = "EBS volume size per broker (GB)"
  type        = number
  default     = 100
}

# =============================================================================
# MSK Configuration
# =============================================================================

resource "aws_msk_configuration" "this" {
  count = var.create_msk ? 1 : 0

  name              = "${var.resource_prefix}-msk-config"
  description       = "MSK configuration for ${var.project_name} (KRaft mode)"
  kafka_versions    = [var.msk_kafka_version]

  server_properties = <<PROPERTIES
auto.create.topics.enable=true
log.retention.hours=168
num.partitions=3
default.replication.factor=3
PROPERTIES

  lifecycle {
    create_before_destroy = true
  }
}

# =============================================================================
# MSK Cluster
# =============================================================================

resource "aws_msk_cluster" "this" {
  count = var.create_msk ? 1 : 0

  cluster_name           = "${var.resource_prefix}-kafka"
  kafka_version          = var.msk_kafka_version
  number_of_broker_nodes = var.msk_broker_count

  broker_node_group_info {
    instance_type   = var.msk_instance_type
    client_subnets  = module.vpc_app.private_subnets
    security_groups = [aws_security_group.msk[0].id]

    storage_info {
      ebs_storage_info {
        volume_size = var.msk_ebs_volume_size
      }
    }
  }

  configuration_info {
    arn      = aws_msk_configuration.this[0].arn
    revision = aws_msk_configuration.this[0].latest_revision
  }

  encryption_info {
    encryption_in_transit {
      client_broker = "TLS_PLAINTEXT"
      in_cluster    = true
    }
  }

  logging_info {
    broker_logs {
      cloudwatch_logs {
        enabled   = false
        log_group = ""
      }
    }
  }

  tags = {
    Name        = "${var.resource_prefix}-kafka"
    Environment = var.environment
    Project     = var.project_name
    Owner       = var.owner
    CostCenter  = var.cost_center
  }
}

# =============================================================================
# MSK Security Group
# =============================================================================

resource "aws_security_group" "msk" {
  count = var.create_msk ? 1 : 0

  name        = "${var.resource_prefix}-msk-sg"
  description = "Security group for MSK cluster"
  vpc_id      = module.vpc_app.vpc_id

  # Kafka plaintext
  ingress {
    from_port   = 9092
    to_port     = 9092
    protocol    = "tcp"
    cidr_blocks = [var.vpc_app_cidr]
    description = "Kafka plaintext from VPC"
  }

  # Kafka TLS
  ingress {
    from_port   = 9094
    to_port     = 9094
    protocol    = "tcp"
    cidr_blocks = [var.vpc_app_cidr]
    description = "Kafka TLS from VPC"
  }

  # Zookeeper (for non-KRaft mode)
  ingress {
    from_port   = 2181
    to_port     = 2181
    protocol    = "tcp"
    cidr_blocks = [var.vpc_app_cidr]
    description = "Zookeeper from VPC"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = {
    Name        = "${var.resource_prefix}-msk-sg"
    Environment = var.environment
    Project     = var.project_name
  }
}

# =============================================================================
# Outputs
# =============================================================================

output "msk_cluster_arn" {
  description = "MSK cluster ARN"
  value       = var.create_msk ? aws_msk_cluster.this[0].arn : null
}

output "msk_bootstrap_brokers" {
  description = "MSK bootstrap brokers (plaintext)"
  value       = var.create_msk ? aws_msk_cluster.this[0].bootstrap_brokers : null
}

output "msk_bootstrap_brokers_tls" {
  description = "MSK bootstrap brokers (TLS)"
  value       = var.create_msk ? aws_msk_cluster.this[0].bootstrap_brokers_tls : null
}

output "msk_zookeeper_connect_string" {
  description = "MSK Zookeeper connection string"
  value       = var.create_msk ? aws_msk_cluster.this[0].zookeeper_connect_string : null
}
