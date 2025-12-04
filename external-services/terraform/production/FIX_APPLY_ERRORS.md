# Terraform Apply 에러 수정 가이드

## ❌ 발생한 에러들

### 1. MSK Kafka 버전 오류
```
Error: Unsupported KafkaVersion [3.7.0]. Valid values: [..., 3.7.x, 3.7.x.kraft, ...]
```

**해결:** `3.7.0` → `3.7.x.kraft`로 변경 완료

### 2. S3 버킷 중복 오류
```
Error: BucketAlreadyOwnedByYou: Your previous request to create the named bucket succeeded and you already own it.
Bucket: c4-tracking-log
```

**해결 방법 2가지:**

#### 방법 1: 기존 버킷 Import (권장)
```bash
# 기존 버킷을 Terraform 상태에 추가
terraform import aws_s3_bucket.tracking_log[0] c4-tracking-log

# 그 다음 apply 재실행
terraform apply
```

#### 방법 2: 다른 이름 사용
```bash
# terraform.tfvars에서 다른 이름 지정
tracking_log_bucket_name = "c4-tracking-log-v2"
```

### 3. VPC 서브넷 CIDR 오류
```
Error: InvalidSubnet.Range: The CIDR '172.20.x.x/20' is invalid.
```

**원인:** VPC CIDR이 `10.0.0.0/16`인데 서브넷이 `172.20.x.x`를 사용하려고 함

**해결:** terraform.tfvars에 올바른 서브넷 CIDR 추가 완료

---

## ✅ 수정 완료된 항목

1. ✅ MSK Kafka 버전: `3.7.0` → `3.7.x.kraft`
2. ✅ VPC 서브넷 CIDR: 올바른 CIDR 추가
3. ⚠️ S3 버킷: 기존 버킷 import 필요

---

## 🔧 다음 단계

### Step 1: 기존 S3 버킷 Import

```bash
cd external-services/terraform/production

# 기존 버킷을 Terraform 상태에 추가
terraform import aws_s3_bucket.tracking_log[0] c4-tracking-log

# 관련 리소스도 import (있는 경우)
terraform import aws_s3_bucket_versioning.tracking_log_versioning[0] c4-tracking-log
terraform import aws_s3_bucket_server_side_encryption_configuration.tracking_log_encryption[0] c4-tracking-log
terraform import aws_s3_bucket_public_access_block.tracking_log_pab[0] c4-tracking-log
```

### Step 2: Apply 재실행

```bash
# Plan 확인
terraform plan

# Apply 실행
./scripts/apply-with-logs.sh
```

---

## 📋 빠른 수정 스크립트

```bash
cd external-services/terraform/production

# 1. 기존 버킷 import
terraform import aws_s3_bucket.tracking_log[0] c4-tracking-log 2>/dev/null || echo "Import 실패 또는 이미 존재"

# 2. Plan 확인
terraform plan | grep -E "will be created|will be updated|will be destroyed" | head -20

# 3. Apply 실행
./scripts/apply-with-logs.sh
```

---

## 🎯 예상 결과

수정 후:
- ✅ MSK Configuration 생성 성공
- ✅ S3 버킷 import 또는 새 이름으로 생성
- ✅ VPC 서브넷 생성 성공
- ✅ EKS 클러스터 생성 시작

