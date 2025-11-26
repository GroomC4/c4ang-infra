# =============================================================================
# S3 Buckets for Airflow Logs
# =============================================================================

# Airflow 로그용 S3 버킷
resource "aws_s3_bucket" "airflow_logs" {
  count = var.create_s3_buckets ? 1 : 0
  
  bucket = var.airflow_logs_bucket_name
  
  tags = {
    Name        = "${var.project_name}-airflow-logs"
    Environment = var.environment
    Owner       = var.owner
    CostCenter  = var.cost_center
    Purpose     = "Airflow Logs Storage"
  }
}

## (삭제) 랜덤 suffix 미사용

# S3 버킷 버전 관리
resource "aws_s3_bucket_versioning" "airflow_logs_versioning" {
  count = var.create_s3_buckets && var.s3_bucket_versioning ? 1 : 0
  
  bucket = aws_s3_bucket.airflow_logs[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 버킷 암호화
resource "aws_s3_bucket_server_side_encryption_configuration" "airflow_logs_encryption" {
  count = var.create_s3_buckets && var.s3_bucket_encryption ? 1 : 0
  
  bucket = aws_s3_bucket.airflow_logs[0].id
  
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 버킷 생명주기 정책 (로그 정리)
resource "aws_s3_bucket_lifecycle_configuration" "airflow_logs_lifecycle" {
  count = var.create_s3_buckets && var.s3_lifecycle_enabled ? 1 : 0
  
  bucket = aws_s3_bucket.airflow_logs[0].id
  
  rule {
    id     = "log_cleanup"
    status = "Enabled"
    
    filter {
      prefix = "log/"
    }
    
    expiration {
      days = var.s3_log_retention_days
    }
    
    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }
}

# S3 버킷 퍼블릭 액세스 차단
resource "aws_s3_bucket_public_access_block" "airflow_logs_pab" {
  count = var.create_s3_buckets ? 1 : 0
  
  bucket = aws_s3_bucket.airflow_logs[0].id
  
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# =============================================================================
# IRSA Role for Airflow
# =============================================================================

# Airflow IRSA 서비스 어카운트
resource "aws_iam_role" "airflow_irsa" {
  count = var.create_s3_buckets ? 1 : 0
  
  name = "${var.project_name}-airflow-irsa"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRoleWithWebIdentity"
      Effect = "Allow"
      Principal = {
        Federated = var.create_eks_cluster ? module.eks[0].oidc_provider_arn : null
      }
      Condition = {
        StringEquals = {
          "${var.create_eks_cluster ? module.eks[0].oidc_provider : ""}:sub" = "system:serviceaccount:airflow:airflow-irsa"
          "${var.create_eks_cluster ? module.eks[0].oidc_provider : ""}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
  
  tags = {
    Name        = "${var.project_name}-airflow-irsa"
    Environment = var.environment
    Owner       = var.owner
    CostCenter  = var.cost_center
    Purpose     = "Airflow S3 Access"
  }
}

# Airflow S3 정책
resource "aws_iam_policy" "airflow_s3_policy" {
  count = var.create_s3_buckets ? 1 : 0
  
  name        = "${var.project_name}-airflow-s3-policy"
  description = "Policy for Airflow to access S3 buckets"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.airflow_logs[0].arn,
          "${aws_s3_bucket.airflow_logs[0].arn}/*"
        ]
      }
    ]
  })
}

# 정책 연결
resource "aws_iam_role_policy_attachment" "airflow_s3_policy_attachment" {
  count = var.create_s3_buckets ? 1 : 0
  
  role       = aws_iam_role.airflow_irsa[0].name
  policy_arn = aws_iam_policy.airflow_s3_policy[0].arn
}

