# =============================================================================
# Outputs for MSA External Data Services
# =============================================================================
# 이 출력값들은 K8s ExternalName Service 설정에 사용됩니다.

# -----------------------------------------------------------------------------
# RDS PostgreSQL Outputs
# -----------------------------------------------------------------------------

output "rds_endpoints" {
  description = "서비스별 RDS 엔드포인트"
  value = var.create_rds ? {
    for k, v in aws_db_instance.msa : k => {
      endpoint = v.endpoint
      address  = v.address
      port     = v.port
      database = v.db_name
    }
  } : {}
}

output "rds_connection_strings" {
  description = "서비스별 PostgreSQL 연결 문자열 (비밀번호 제외)"
  value = var.create_rds ? {
    for k, v in aws_db_instance.msa : k => "postgresql://${v.username}@${v.address}:${v.port}/${v.db_name}"
  } : {}
  sensitive = true
}

# 개별 서비스 엔드포인트 (ExternalName Service용)
output "customer_db_endpoint" {
  description = "Customer 서비스 DB 엔드포인트"
  value       = var.create_rds ? aws_db_instance.msa["customer"].address : null
}

output "product_db_endpoint" {
  description = "Product 서비스 DB 엔드포인트"
  value       = var.create_rds ? aws_db_instance.msa["product"].address : null
}

output "order_db_endpoint" {
  description = "Order 서비스 DB 엔드포인트"
  value       = var.create_rds ? aws_db_instance.msa["order"].address : null
}

output "store_db_endpoint" {
  description = "Store 서비스 DB 엔드포인트"
  value       = var.create_rds ? aws_db_instance.msa["store"].address : null
}

output "saga_db_endpoint" {
  description = "Saga 서비스 DB 엔드포인트"
  value       = var.create_rds ? aws_db_instance.msa["saga"].address : null
}

# -----------------------------------------------------------------------------
# ElastiCache Redis Outputs
# -----------------------------------------------------------------------------

output "redis_endpoints" {
  description = "Redis 인스턴스별 엔드포인트"
  value = var.create_elasticache ? {
    for k, v in aws_elasticache_cluster.msa : k => {
      endpoint      = v.cache_nodes[0].address
      port          = v.cache_nodes[0].port
      configuration = v.parameter_group_name
    }
  } : {}
}

output "cache_redis_endpoint" {
  description = "캐시용 Redis 엔드포인트"
  value       = var.create_elasticache ? aws_elasticache_cluster.msa["cache"].cache_nodes[0].address : null
}

output "session_redis_endpoint" {
  description = "세션용 Redis 엔드포인트"
  value       = var.create_elasticache ? aws_elasticache_cluster.msa["session"].cache_nodes[0].address : null
}

# -----------------------------------------------------------------------------
# MSK Kafka Outputs
# -----------------------------------------------------------------------------

output "msk_bootstrap_brokers" {
  description = "MSK 부트스트랩 브로커 (PLAINTEXT)"
  value       = var.create_msk ? aws_msk_cluster.msa[0].bootstrap_brokers : null
}

output "msk_bootstrap_brokers_tls" {
  description = "MSK 부트스트랩 브로커 (TLS)"
  value       = var.create_msk ? aws_msk_cluster.msa[0].bootstrap_brokers_tls : null
}

output "msk_zookeeper_connect" {
  description = "MSK Zookeeper 연결 문자열"
  value       = var.create_msk ? aws_msk_cluster.msa[0].zookeeper_connect_string : null
}

# -----------------------------------------------------------------------------
# Security Group IDs (참조용)
# -----------------------------------------------------------------------------

output "rds_security_group_id" {
  description = "RDS 보안 그룹 ID"
  value       = aws_security_group.rds.id
}

output "redis_security_group_id" {
  description = "Redis 보안 그룹 ID"
  value       = var.create_elasticache ? aws_security_group.redis[0].id : null
}

output "msk_security_group_id" {
  description = "MSK 보안 그룹 ID"
  value       = var.create_msk ? aws_security_group.msk[0].id : null
}

# -----------------------------------------------------------------------------
# Summary Output (Helm values 생성용)
# -----------------------------------------------------------------------------

output "external_services_config" {
  description = "ExternalName Service 설정에 사용할 구성 요약"
  value = {
    databases = var.create_rds ? {
      for k, v in aws_db_instance.msa : k => v.address
    } : {}
    redis = var.create_elasticache ? {
      cache   = aws_elasticache_cluster.msa["cache"].cache_nodes[0].address
      session = aws_elasticache_cluster.msa["session"].cache_nodes[0].address
    } : {}
    kafka = var.create_msk ? {
      bootstrap_brokers = aws_msk_cluster.msa[0].bootstrap_brokers
    } : {}
  }
}
