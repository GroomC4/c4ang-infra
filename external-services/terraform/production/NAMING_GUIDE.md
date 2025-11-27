# 🏷️ 환경별 네이밍 설정 가이드

## 📋 개요
이 문서는 `environment_suffix`와 `resource_prefix` 변수를 사용하여 환경별로 리소스 네이밍을 쉽게 관리하는 방법을 설명합니다.

## 🔧 네이밍 변수 설명

### **1. `resource_prefix`**
- **용도**: 모든 리소스 이름의 접두사
- **기본값**: `"c4"`
- **예시**: `c4-vpc-app`, `c4-eks-cluster`

### **2. `environment_suffix`**
- **용도**: 환경별 접미사 (선택사항)
- **기본값**: `""` (빈 문자열)
- **예시**: `-dev`, `-test`, `-staging`, `-prod`

### **3. `environment`**
- **용도**: 환경 이름 (태그용)
- **기본값**: `"production"` 또는 `"test"`
- **예시**: `dev`, `test`, `staging`, `production`

## 🎯 환경별 설정 예시

### **Development 환경**
```hcl
# terraform.tfvars
resource_prefix = "c4"
environment_suffix = "-dev"
environment = "dev"
```

**결과 네이밍:**
- VPC: `c4-vpc-app-dev`
- EKS: `c4-eks-cluster-dev`
- RDS: `c4-rds-dev`

### **Test 환경**
```hcl
# terraform.tfvars
resource_prefix = "c4"
environment_suffix = "-test"
environment = "test"
```

**결과 네이밍:**
- VPC: `c4-vpc-app-test`
- EKS: `c4-eks-cluster-test`
- RDS: `c4-rds-test`

### **Staging 환경**
```hcl
# terraform.tfvars
resource_prefix = "c4"
environment_suffix = "-staging"
environment = "staging"
```

**결과 네이밍:**
- VPC: `c4-vpc-app-staging`
- EKS: `c4-eks-cluster-staging`
- RDS: `c4-rds-staging`

### **Production 환경 (접미사 없음)**
```hcl
# terraform.tfvars
resource_prefix = "c4"
environment_suffix = ""  # 빈 문자열
environment = "production"
```

**결과 네이밍:**
- VPC: `c4-vpc-app`
- EKS: `c4-eks-cluster`
- RDS: `c4-rds`

## 🔄 환경 변경 방법

### **1. 기존 환경에서 새 환경으로 변경**
```bash
# 1. terraform.tfvars 수정
vim terraform.tfvars

# 2. 환경 변수 변경
environment_suffix = "-staging"
environment = "staging"

# 3. 계획 확인
terraform plan

# 4. 적용
terraform apply
```

### **2. 환경 접미사 제거 (Production으로 변경)**
```bash
# 1. terraform.tfvars 수정
environment_suffix = ""  # 빈 문자열로 변경
environment = "production"

# 2. 계획 확인
terraform plan

# 3. 적용
terraform apply
```

## 📊 네이밍 규칙

### **리소스 이름 패턴**
```
${resource_prefix}-${resource_type}${environment_suffix}
```

### **예시**
| 리소스 타입 | Development | Test | Staging | Production |
|-------------|-------------|------|---------|------------|
| **VPC APP** | `c4-vpc-app-dev` | `c4-vpc-app-test` | `c4-vpc-app-staging` | `c4-vpc-app` |
| **VPC DB** | `c4-vpc-db-dev` | `c4-vpc-db-test` | `c4-vpc-db-staging` | `c4-vpc-db` |
| **EKS** | `c4-eks-cluster-dev` | `c4-eks-cluster-test` | `c4-eks-cluster-staging` | `c4-eks-cluster` |
| **RDS** | `c4-rds-dev` | `c4-rds-test` | `c4-rds-staging` | `c4-rds` |

## ⚠️ 주의사항

### **1. 환경 변경 시 고려사항**
- **리소스 이름 변경**: 대부분의 AWS 리소스는 이름 변경이 불가능
- **새 리소스 생성**: 이름이 변경되면 새 리소스가 생성됨
- **기존 리소스 삭제**: 기존 리소스는 수동으로 삭제해야 함

### **2. 안전한 환경 변경 방법**
```bash
# 1. 백업 생성
terraform state list > backup_state.txt

# 2. 계획 확인
terraform plan

# 3. 단계별 적용
terraform apply -target=module.vpc_app
terraform apply -target=module.vpc_db
# ... 기타 리소스

# 4. 기존 리소스 정리
terraform destroy -target=old_resource
```

### **3. 권장사항**
- **개발 초기**: `environment_suffix` 사용
- **Production**: `environment_suffix = ""` (접미사 없음)
- **일관성**: 팀 전체가 동일한 네이밍 규칙 사용

## 🚀 빠른 시작

### **새 환경 생성**
```bash
# 1. 폴더 복사
cp -r test staging

# 2. 설정 변경
cd staging
vim terraform.tfvars

# 3. 환경 변수 설정
environment_suffix = "-staging"
environment = "staging"

# 4. 배포
terraform init
terraform apply
```

### **기존 환경 수정**
```bash
# 1. 현재 설정 확인
terraform show | grep -E "(name|environment)"

# 2. 설정 변경
vim terraform.tfvars

# 3. 계획 확인
terraform plan

# 4. 적용
terraform apply
```

---
**작성일**: 2024년 12월
**작성자**: tjpark
