# =============================================================================
# MSK (Amazon Managed Streaming for Apache Kafka)
# =============================================================================

locals {
  msk_target_vpc_id     = module.vpc_db.vpc_id
  msk_target_subnet_ids = module.vpc_db.private_subnets
  msk_eks_node_sg_id    = try(module.eks[0].node_security_group_id, null)
}

# =============================================================================
# MSK Configuration
# =============================================================================

resource "aws_msk_configuration" "msk_config" {
  count = var.create_msk ? 1 : 0

  name           = "${var.project_name}-msk-config${var.environment_suffix}"
  kafka_versions = [var.msk_kafka_version]
  description    = "MSK configuration for ${var.project_name} (${var.msk_use_kraft ? "KRaft" : "Zookeeper"} mode)"

  server_properties = <<PROPERTIES
# 기본 설정
auto.create.topics.enable=true
default.replication.factor=${var.environment == "production" ? 3 : 2}
min.insync.replicas=${var.environment == "production" ? 2 : 1}
num.partitions=3

# 성능 최적화
num.network.threads=8
num.io.threads=8
socket.send.buffer.bytes=102400
socket.receive.buffer.bytes=102400
socket.request.max.bytes=104857600

# 압축
compression.type=snappy

# 로그 리텐션 (7일)
log.retention.hours=168
log.segment.bytes=1073741824

# KRaft 모드 설정 (Kafka 3.7+)
${var.msk_use_kraft ? <<-EOT
# KRaft 모드: Zookeeper 없이 메타데이터 관리
# MSK가 자동으로 KRaft 모드로 설정됨 (Kafka 3.7+)
EOT
: "# Zookeeper 모드 사용"}
PROPERTIES

  # 참고: aws_msk_configuration 리소스는 tags를 지원하지 않음
}

# =============================================================================
# MSK Security Group
# =============================================================================

resource "aws_security_group" "msk_sg" {
  count = var.create_msk ? 1 : 0

  name_prefix = "${var.project_name}-msk-sg-"
  vpc_id      = local.msk_target_vpc_id
  description = "Security group for MSK cluster"

  # Kafka 브로커 통신 (9092-9098) - EKS 노드에서만 접근
  dynamic "ingress" {
    for_each = local.msk_eks_node_sg_id != null ? [local.msk_eks_node_sg_id] : []
    content {
      from_port       = 9092
      to_port         = 9098
      protocol        = "tcp"
      security_groups = [ingress.value]
      description     = "Kafka from EKS nodes"
    }
  }

  # Zookeeper 통신 (2181) - KRaft 모드가 아닐 때만 필요
  dynamic "ingress" {
    for_each = var.msk_use_kraft ? [] : [1]
    content {
      from_port   = 2181
      to_port     = 2181
      protocol    = "tcp"
      self        = true
      description = "Zookeeper internal communication (not needed in KRaft mode)"
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${var.project_name}-msk-sg${var.environment_suffix}"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# =============================================================================
# MSK Cluster
# =============================================================================

resource "aws_msk_cluster" "msk_cluster" {
  count = var.create_msk ? 1 : 0

  cluster_name           = "${var.project_name}-kafka${var.environment_suffix}"
  kafka_version          = var.msk_kafka_version
  number_of_broker_nodes = var.environment == "production" ? 3 : 2

  broker_node_group_info {
    instance_type   = var.msk_instance_type
    client_subnets  = local.msk_target_subnet_ids
    security_groups = [aws_security_group.msk_sg[0].id]

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
    arn      = aws_msk_configuration.msk_config[0].arn
    revision = aws_msk_configuration.msk_config[0].latest_revision
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${var.project_name}-kafka${var.environment_suffix}"
    }
  )
}

# =============================================================================
# Outputs
# =============================================================================

output "msk_cluster_arn" {
  description = "MSK cluster ARN"
  value       = var.create_msk ? aws_msk_cluster.msk_cluster[0].arn : null
}

output "msk_bootstrap_brokers" {
  description = "MSK bootstrap brokers (plaintext)"
  value       = var.create_msk ? aws_msk_cluster.msk_cluster[0].bootstrap_brokers : null
}

output "msk_bootstrap_brokers_tls" {
  description = "MSK bootstrap brokers (TLS)"
  value       = var.create_msk ? aws_msk_cluster.msk_cluster[0].bootstrap_brokers_tls : null
}

output "msk_zookeeper_connect_string" {
  description = "MSK Zookeeper connection string"
  value       = var.create_msk ? aws_msk_cluster.msk_cluster[0].zookeeper_connect_string : null
}
