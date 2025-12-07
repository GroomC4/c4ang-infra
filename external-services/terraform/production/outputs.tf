# =============================================================================
# 네트워크 및 보안 정보
# =============================================================================

output "current_local_ip" {
  description = "Current local IP address used for EKS public access"
  value       = chomp(data.http.current_ip.response_body)
}

output "eks_public_access_cidrs" {
  description = "EKS public access CIDR blocks"
  value = var.create_eks_cluster ? [
    "${chomp(data.http.current_ip.response_body)}/32"
  ] : null
}

# EBS CSI Driver 정보
output "ebs_csi_driver_role_arn" {
  description = "EBS CSI Driver IAM role ARN"
  value       = var.create_eks_cluster ? aws_iam_role.ebs_csi_driver[0].arn : null
}

# =============================================================================
# EKS 클러스터 정보
# =============================================================================

# EKS 모듈이 생성되지 않을 수 있으므로 조건부로 출력

output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = var.create_eks_cluster ? module.eks[0].cluster_name : null
}

output "aws_region" {
  description = "AWS region"
  value       = var.aws_region
}
# EKS Security Groups
output "eks_cluster_security_group_id" {
  description = "EKS cluster security group ID"
  value       = var.create_eks_cluster ? module.eks[0].cluster_security_group_id : null
}

output "eks_node_security_group_id" {
  description = "EKS node security group ID"
  value       = var.create_eks_cluster ? module.eks[0].node_security_group_id : null
}

output "eks_cluster_id" {
  description = "EKS cluster ID"
  value       = var.create_eks_cluster ? module.eks[0].cluster_id : null
}

output "eks_cluster_arn" {
  description = "EKS cluster ARN"
  value       = var.create_eks_cluster ? module.eks[0].cluster_arn : null
}

output "eks_cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = var.create_eks_cluster ? module.eks[0].cluster_endpoint : null
}

output "eks_cluster_version" {
  description = "EKS cluster version"
  value       = var.create_eks_cluster ? module.eks[0].cluster_version : null
}

output "eks_node_groups" {
  description = "EKS node groups information (minimum footprint)"
  value = var.create_eks_cluster ? {
    core_on = {
      name           = "core-on"
      instance_types = var.core_node_group.instance_types
      min_size       = var.core_node_group.min_size
      max_size       = var.core_node_group.max_size
      desired_size   = var.core_node_group.desired_size
      disk_size      = var.core_node_group.disk_size
      workload       = "core"
      capacity_type  = "on-demand"
    }
    high_traffic = {
      name           = "high-traffic"
      instance_types = var.high_traffic_node_group.instance_types
      min_size       = var.high_traffic_node_group.min_size
      max_size       = var.high_traffic_node_group.max_size
      desired_size   = var.high_traffic_node_group.desired_size
      disk_size      = var.high_traffic_node_group.disk_size
      workload       = "high-traffic"
      capacity_type  = "on-demand"
    }
    low_traffic = {
      name           = "low-traffic"
      instance_types = var.low_traffic_node_group.instance_types
      min_size       = var.low_traffic_node_group.min_size
      max_size       = var.low_traffic_node_group.max_size
      desired_size   = var.low_traffic_node_group.desired_size
      disk_size      = var.low_traffic_node_group.disk_size
      workload       = "low-traffic"
      capacity_type  = "on-demand"
    }
    stateful_storage = {
      name           = "stateful-storage"
      instance_types = var.stateful_storage_node_group.instance_types
      min_size       = var.stateful_storage_node_group.min_size
      max_size       = var.stateful_storage_node_group.max_size
      desired_size   = var.stateful_storage_node_group.desired_size
      disk_size      = var.stateful_storage_node_group.disk_size
      workload       = "stateful"
      capacity_type  = "on-demand"
      taints         = ["workload=stateful:NoSchedule"]
    }
    kafka_storage = {
      name           = "kafka-storage"
      instance_types = var.kafka_storage_node_group.instance_types
      min_size       = var.kafka_storage_node_group.min_size
      max_size       = var.kafka_storage_node_group.max_size
      desired_size   = var.kafka_storage_node_group.desired_size
      disk_size      = var.kafka_storage_node_group.disk_size
      workload       = "kafka"
      capacity_type  = "on-demand"
      taints         = ["workload=kafka:NoSchedule"]
    }
  } : null
}

output "eks_cluster_oidc_issuer_url" {
  description = "EKS cluster OIDC issuer URL"
  value       = var.create_eks_cluster ? module.eks[0].cluster_oidc_issuer_url : null
}

output "eks_cluster_certificate_authority_data" {
  description = "EKS cluster certificate authority data"
  value       = var.create_eks_cluster ? module.eks[0].cluster_certificate_authority_data : null
}

# EKS Node Groups
output "eks_nodegroup_ids" {
  description = "EKS managed node group IDs"
  value       = var.create_eks_cluster ? module.eks[0].eks_managed_node_groups_autoscaling_group_names : null
}

# =============================================================================
# VPC 출력
# =============================================================================

output "vpc_app_id" {
  description = "VPC-APP ID"
  value       = module.vpc_app.vpc_id
}

output "vpc_db_id" {
  description = "VPC-DB ID"
  value       = module.vpc_db.vpc_id
}

output "vpc_app_cidr" {
  description = "VPC-APP CIDR"
  value       = module.vpc_app.vpc_cidr_block
}

output "vpc_db_cidr" {
  description = "VPC-DB CIDR"
  value       = module.vpc_db.vpc_cidr_block
}

# =============================================================================
# Subnet 출력
# =============================================================================

output "vpc_app_public_subnets" {
  description = "VPC-APP Public Subnets"
  value       = module.vpc_app.public_subnets
}

output "vpc_app_private_subnets" {
  description = "VPC-APP Private Subnets"
  value       = module.vpc_app.private_subnets
}

output "vpc_db_private_subnets" {
  description = "VPC-DB Private Subnets"
  value       = module.vpc_db.private_subnets
}

# =============================================================================
# VPC Peering 출력
# =============================================================================

output "vpc_peering_connection_id" {
  description = "VPC Peering Connection ID"
  value       = aws_vpc_peering_connection.app_to_db.id
}

# =============================================================================
# 단방향 통신 정보
# =============================================================================

# =============================================================================
# RDS 데이터베이스 정보
# =============================================================================

output "rds_instance_id" {
  description = "RDS instance ID"
  value       = var.create_rds ? aws_db_instance.airflow_db[0].id : null
}

output "rds_endpoint" {
  description = "RDS instance endpoint"
  value       = var.create_rds ? aws_db_instance.airflow_db[0].endpoint : null
}

output "rds_port" {
  description = "RDS instance port"
  value       = var.create_rds ? aws_db_instance.airflow_db[0].port : null
}

output "rds_database_name" {
  description = "RDS database name"
  value       = var.create_rds ? aws_db_instance.airflow_db[0].db_name : null
}

output "rds_username" {
  description = "RDS master username"
  value       = var.create_rds ? aws_db_instance.airflow_db[0].username : null
}

output "rds_connection_info" {
  description = "RDS connection information"
  value = var.create_rds ? {
    host              = aws_db_instance.airflow_db[0].endpoint
    port              = aws_db_instance.airflow_db[0].port
    database          = aws_db_instance.airflow_db[0].db_name
    username          = aws_db_instance.airflow_db[0].username
    password          = "Check terraform.tfvars for rds_master_password"
    connection_string = "postgresql://${aws_db_instance.airflow_db[0].username}:<password>@${aws_db_instance.airflow_db[0].endpoint}:${aws_db_instance.airflow_db[0].port}/${aws_db_instance.airflow_db[0].db_name}"
    note              = "Update application configuration with this connection string"
  } : null
}

output "rds_security_group_id" {
  description = "RDS security group ID"
  value       = var.create_rds ? aws_security_group.rds_sg[0].id : null
}

output "rds_subnet_group_name" {
  description = "RDS subnet group name"
  value       = var.create_rds ? aws_db_subnet_group.rds_subnet_group[0].name : null
}

# =============================================================================
# MSK Kafka 클러스터 정보
# =============================================================================

output "msk_cluster_arn" {
  description = "MSK cluster ARN"
  value       = var.create_msk ? aws_msk_cluster.msk_cluster[0].arn : null
}

output "msk_cluster_name" {
  description = "MSK cluster name"
  value       = var.create_msk ? aws_msk_cluster.msk_cluster[0].cluster_name : null
}

output "msk_bootstrap_brokers" {
  description = "MSK bootstrap brokers (PLAINTEXT)"
  value       = var.create_msk ? aws_msk_cluster.msk_cluster[0].bootstrap_brokers : null
}

output "msk_bootstrap_brokers_tls" {
  description = "MSK bootstrap brokers (TLS)"
  value       = var.create_msk ? aws_msk_cluster.msk_cluster[0].bootstrap_brokers_tls : null
}

output "msk_zookeeper_connect_string" {
  description = "MSK Zookeeper connect string"
  value       = var.create_msk ? aws_msk_cluster.msk_cluster[0].zookeeper_connect_string : null
  sensitive   = true
}

output "msk_security_group_id" {
  description = "MSK security group ID"
  value       = var.create_msk ? aws_security_group.msk_sg[0].id : null
}

output "msk_connection_info" {
  description = "MSK connection information"
  value = var.create_msk ? {
    cluster_arn           = aws_msk_cluster.msk_cluster[0].arn
    cluster_name          = aws_msk_cluster.msk_cluster[0].cluster_name
    bootstrap_brokers     = aws_msk_cluster.msk_cluster[0].bootstrap_brokers
    bootstrap_brokers_tls = aws_msk_cluster.msk_cluster[0].bootstrap_brokers_tls
    security_group_id     = aws_security_group.msk_sg[0].id
    vpc_id                = local.msk_target_vpc_id
    kafka_version         = var.msk_kafka_version
    kraft_mode            = var.msk_use_kraft
    note                  = "Update application configuration with bootstrap_brokers"
  } : null
}

# =============================================================================
# S3 버킷 정보
# =============================================================================

output "airflow_logs_bucket_name" {
  description = "Airflow logs S3 bucket name"
  value       = var.create_s3_buckets ? aws_s3_bucket.airflow_logs[0].bucket : null
}

output "airflow_logs_bucket_arn" {
  description = "Airflow logs S3 bucket ARN"
  value       = var.create_s3_buckets ? aws_s3_bucket.airflow_logs[0].arn : null
}

output "tracking_log_bucket_name" {
  description = "Tracking log S3 bucket name"
  value       = var.create_s3_buckets ? aws_s3_bucket.tracking_log[0].bucket : null
}

output "tracking_log_bucket_arn" {
  description = "Tracking log S3 bucket ARN"
  value       = var.create_s3_buckets ? aws_s3_bucket.tracking_log[0].arn : null
}

output "s3_buckets_info" {
  description = "S3 buckets information for Airflow workloads"
  value = var.create_s3_buckets ? {
    airflow_logs = {
      bucket_name = aws_s3_bucket.airflow_logs[0].bucket
      bucket_arn  = aws_s3_bucket.airflow_logs[0].arn
      s3_url      = "s3://${aws_s3_bucket.airflow_logs[0].bucket}/log"
      purpose     = "Airflow logs storage"
    }
    tracking_log = {
      bucket_name = aws_s3_bucket.tracking_log[0].bucket
      bucket_arn  = aws_s3_bucket.tracking_log[0].arn
      s3_url      = "s3://${aws_s3_bucket.tracking_log[0].bucket}/log"
      purpose     = "Tracking log storage"
    }
  } : null
}

# =============================================================================
# IRSA 서비스 어카운트 정보
# =============================================================================

output "airflow_irsa_role_arn" {
  description = "Airflow IRSA role ARN"
  value       = var.create_s3_buckets && var.create_k8s_resources ? aws_iam_role.airflow_irsa[0].arn : null
}

output "irsa_service_accounts_info" {
  description = "IRSA service accounts information"
  value = var.create_s3_buckets && var.create_k8s_resources ? {
    airflow_irsa = {
      role_arn             = aws_iam_role.airflow_irsa[0].arn
      service_account_name = "airflow-irsa"
      namespace            = "airflow"
      purpose              = "Airflow S3 access for logs"
      permissions          = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
      k8s_resource_created = var.create_k8s_resources
    }
  } : null
}

# =============================================================================
# 비용 최적화 정보
# =============================================================================

output "cost_optimization_info" {
  description = "Cost Optimization Information"
  value = {
    vpc_count         = 2
    nat_gateway_count = 1
    eks_cluster       = var.create_eks_cluster ? "Enabled" : "Disabled"
    eks_node_groups = var.create_eks_cluster ? {
      core_on          = "t3.large (2-4 nodes, on-demand)"
      high_traffic     = "t3.large (2-4 nodes, on-demand)"
      low_traffic      = "t3.medium (2-4 nodes, on-demand)"
      stateful_storage = "m5.large (2-4 nodes, on-demand, taint=workload=stateful)"
      kafka_storage    = "m5.large (3-5 nodes, on-demand, taint=workload=kafka)"
    } : null
    rds_database          = var.create_rds ? "Enabled" : "Disabled"
    rds_instance_type     = var.create_rds ? var.rds_instance_class : null
    rds_storage           = var.create_rds ? "${var.rds_allocated_storage}GB (max ${var.rds_max_allocated_storage}GB)" : null
    rds_multi_az          = var.create_rds ? var.rds_multi_az : null
    s3_buckets            = var.create_s3_buckets ? "Enabled" : "Disabled"
    s3_bucket_count       = var.create_s3_buckets ? 2 : 0
    s3_purpose            = var.create_s3_buckets ? "Airflow logs + Spark checkpoints" : null
    irsa_service_accounts = var.create_s3_buckets ? 2 : 0
    vpn_server            = "Not configured"
    note                  = "Multi-workload EKS cluster with minimal on-demand node groups. Additional scale handled via Karpenter."
  }
}
