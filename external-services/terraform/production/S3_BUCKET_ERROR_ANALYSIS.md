# S3 버킷 에러 분석 및 해결 방법

## 📋 현재 설정

### 버킷 이름
- **변수명**: `airflow_logs_bucket_name`
- **기본값**: `c4-airflow-logs`
- **설정 위치**: `variables.tf` (line 464-468)

### 리소스 정의
```hcl
resource "aws_s3_bucket" "airflow_logs" {
  count = var.create_s3_buckets ? 1 : 0
  bucket = var.airflow_logs_bucket_name
  # ...
}
```

---

## ❌ 발생 가능한 에러들

### 1. 버킷 이름 중복 (가장 가능성 높음) ⚠️

**에러 메시지:**
```
Error: error creating S3 Bucket (c4-airflow-logs): BucketAlreadyExists: 
The requested bucket name is not available. The bucket namespace is shared 
by all users of the system. Please select a different name and try again.
```

**원인:**
- S3 버킷 이름은 **전역적으로 고유**해야 함
- `c4-airflow-logs`가 이미 다른 AWS 계정에서 사용 중일 수 있음
- 주석에 "## (삭제) 랜덤 suffix 미사용"이라고 되어 있어 고유성 보장 안 됨

**해결 방법:**
1. **환경별 suffix 추가** (권장)
2. **랜덤 suffix 추가**
3. **계정 ID 포함**

### 2. 버킷 이름 규칙 위반

**에러 메시지:**
```
Error: error creating S3 Bucket: InvalidBucketName: 
The specified bucket is not valid.
```

**원인:**
- 대문자 포함
- 특수문자 사용 (하이픈, 점 제외)
- IP 주소 형식
- 3자 미만 또는 63자 초과

**현재 이름 검증:**
- `c4-airflow-logs`: ✅ 규칙 준수 (소문자, 하이픈만 사용, 3-63자)

### 3. 권한 부족

**에러 메시지:**
```
Error: AccessDenied: Access Denied
```

**원인:**
- IAM 사용자/역할에 S3 버킷 생성 권한 없음

---

## 🔧 해결 방법

### 방법 1: 환경별 Suffix 추가 (권장) ✅

**변경 사항:**
```hcl
# variables.tf
variable "airflow_logs_bucket_name" {
  description = "S3 bucket name for Airflow logs"
  type        = string
  default     = ""  # 빈 값이면 자동 생성
}

# s3-irsa.tf
locals {
  airflow_logs_bucket_name = var.airflow_logs_bucket_name != "" ? 
    var.airflow_logs_bucket_name : 
    "${var.project_name}-airflow-logs-${var.environment}${var.environment_suffix}"
}

resource "aws_s3_bucket" "airflow_logs" {
  count = var.create_s3_buckets ? 1 : 0
  bucket = local.airflow_logs_bucket_name
  # ...
}
```

**결과:**
- `c4-airflow-logs-production`
- `c4-airflow-logs-dev`
- `c4-airflow-logs-test`

### 방법 2: AWS 계정 ID 포함 (고유성 보장) ✅

**변경 사항:**
```hcl
# s3-irsa.tf
data "aws_caller_identity" "current" {}

locals {
  airflow_logs_bucket_name = "${var.project_name}-airflow-logs-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket" "airflow_logs" {
  count = var.create_s3_buckets ? 1 : 0
  bucket = local.airflow_logs_bucket_name
  # ...
}
```

**결과:**
- `c4-airflow-logs-123456789012`

### 방법 3: 랜덤 Suffix 추가 (완전 고유성) ✅

**변경 사항:**
```hcl
# s3-irsa.tf
resource "random_id" "bucket_suffix" {
  count = var.create_s3_buckets ? 1 : 0
  byte_length = 4
}

locals {
  airflow_logs_bucket_name = var.airflow_logs_bucket_name != "" ? 
    var.airflow_logs_bucket_name : 
    "${var.project_name}-airflow-logs-${random_id.bucket_suffix[0].hex}"
}

resource "aws_s3_bucket" "airflow_logs" {
  count = var.create_s3_buckets ? 1 : 0
  bucket = local.airflow_logs_bucket_name
  # ...
}
```

**결과:**
- `c4-airflow-logs-a1b2c3d4`

### 방법 4: 리전 포함 (선택사항)

**변경 사항:**
```hcl
locals {
  airflow_logs_bucket_name = "${var.project_name}-airflow-logs-${var.environment}-${var.aws_region}"
}
```

**결과:**
- `c4-airflow-logs-production-ap-northeast-2`

---

## ✅ 권장 해결책

**환경별 Suffix + 계정 ID 조합** (가장 안전)

```hcl
# s3-irsa.tf
data "aws_caller_identity" "current" {}

locals {
  airflow_logs_bucket_name = var.airflow_logs_bucket_name != "" ? 
    var.airflow_logs_bucket_name : 
    "${var.project_name}-airflow-logs-${var.environment}-${substr(data.aws_caller_identity.current.account_id, -6, -1)}"
}
```

**장점:**
- ✅ 환경별 구분 가능
- ✅ 계정 ID로 고유성 보장
- ✅ 짧은 이름 유지 (계정 ID 마지막 6자리만 사용)
- ✅ 수동 지정도 가능 (변수로 override)

---

## 🔍 현재 버킷 확인 방법

### AWS CLI로 확인
```bash
# 버킷 존재 여부 확인
aws s3 ls | grep c4-airflow-logs

# 또는
aws s3api head-bucket --bucket c4-airflow-logs 2>&1
```

### Terraform으로 확인
```bash
cd external-services/terraform/production
terraform plan
# 에러 메시지에서 정확한 원인 확인 가능
```

---

## 📝 적용 예시

### terraform.tfvars 수정
```hcl
# 방법 1: 환경별 suffix 사용 (자동 생성)
# airflow_logs_bucket_name = ""  # 빈 값이면 자동 생성

# 방법 2: 수동 지정
airflow_logs_bucket_name = "c4-airflow-logs-production-abc123"
```

---

## 🎯 즉시 적용 가능한 수정

가장 간단한 해결책: **환경별 suffix 추가**

```hcl
# s3-irsa.tf 수정
locals {
  airflow_logs_bucket_name = "${var.project_name}-airflow-logs-${var.environment}${var.environment_suffix}"
}

resource "aws_s3_bucket" "airflow_logs" {
  count = var.create_s3_buckets ? 1 : 0
  bucket = local.airflow_logs_bucket_name
  # ...
}
```

이렇게 하면:
- `c4-airflow-logs-production` (production 환경)
- `c4-airflow-logs-dev` (dev 환경)
- `c4-airflow-logs-test` (test 환경)

각 환경별로 고유한 버킷 이름이 생성됩니다.

