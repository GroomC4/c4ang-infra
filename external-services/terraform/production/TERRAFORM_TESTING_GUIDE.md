# Terraform 테스트 가이드

실제 배포 없이 Terraform 코드를 검증하고 테스트하는 방법입니다.

---

## 🚀 빠른 시작

```bash
cd external-services/terraform/production

# 전체 테스트 실행
./scripts/test-terraform.sh

# 또는 개별 테스트
terraform validate
terraform fmt -check
terraform plan
```

---

## 📋 테스트 방법

### 1. **terraform validate** - 구문 검증 ✅

**용도:** Terraform 파일의 구문 오류 확인

```bash
terraform validate
```

**예상 출력:**
```
Success! The configuration is valid.
```

**에러 예시:**
```
Error: Missing required argument
  on main.tf line 10:
  10:   name = var.name
```

**장점:**
- ✅ 빠름 (수초)
- ✅ 실제 리소스 생성 안 함
- ✅ 구문 오류 즉시 발견

---

### 2. **terraform plan** - 실행 계획 확인 (Dry-Run) ✅

**용도:** 실제로 무엇이 생성/변경/삭제될지 미리 확인

```bash
# 전체 계획 확인
terraform plan

# 특정 리소스만 확인
terraform plan -target=aws_s3_bucket.tracking_log

# 출력을 파일로 저장
terraform plan -out=tfplan
terraform show tfplan
```

**예상 출력:**
```
Terraform will perform the following actions:

  # aws_s3_bucket.tracking_log[0] will be created
  + resource "aws_s3_bucket" "tracking_log" {
      + bucket = "c4-tracking-log"
      + id     = (known after apply)
      ...
    }

Plan: 1 to add, 0 to change, 0 to destroy.
```

**장점:**
- ✅ 실제 리소스 생성 안 함
- ✅ 변경사항 미리 확인
- ✅ 비용 예측 가능

**주의:**
- ⚠️ AWS API 호출 발생 (비용 없음)
- ⚠️ AWS 자격 증명 필요

---

### 3. **terraform fmt** - 코드 포맷팅 ✅

**용도:** 코드 스타일 일관성 확인 및 자동 수정

```bash
# 포맷 확인 (변경사항 있으면 에러)
terraform fmt -check

# 포맷 자동 수정
terraform fmt

# 재귀적으로 모든 파일 확인
terraform fmt -recursive

# diff 확인
terraform fmt -diff
```

**예상 출력:**
```
main.tf
variables.tf
```

**장점:**
- ✅ 코드 스타일 통일
- ✅ 가독성 향상
- ✅ CI/CD 통합 가능

---

### 4. **terraform init -upgrade** - 모듈 업데이트 확인 ✅

**용도:** 모듈 버전 및 의존성 확인

```bash
# 모듈 업데이트 확인
terraform init -upgrade

# 의존성 확인
terraform init
```

**예상 출력:**
```
Initializing modules...
- eks in eks.tf
- vpc_app in main.tf
- vpc_db in main.tf

Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 6.0"...
- Installing hashicorp/aws v6.x.x...
```

---

### 5. **Checkov** - 보안 및 모범 사례 검사 ⭐

**용도:** 보안 취약점, 모범 사례 위반 검사

#### 설치
```bash
# macOS
brew install checkov

# 또는 pip
pip install checkov
```

#### 사용
```bash
# 기본 검사
checkov -d .

# 특정 프레임워크 지정
checkov -d . --framework terraform

# 특정 체크만 실행
checkov -d . --check CKV_AWS_144  # S3 버킷 버전 관리

# 출력 형식 지정
checkov -d . --output json
checkov -d . --output sarif
```

**예상 출력:**
```
Passed checks: 15, Failed checks: 2, Skipped checks: 0

Check: CKV_AWS_144: "Ensure that S3 bucket has cross-region replication enabled"
        FAILED for resource: aws_s3_bucket.tracking_log
        File: /s3-irsa.tf:123:1-10:123
```

**장점:**
- ✅ 보안 취약점 자동 발견
- ✅ 모범 사례 준수 확인
- ✅ CI/CD 통합 가능

---

### 6. **TFLint** - Terraform 린터 ⭐

**용도:** Terraform 코드의 잠재적 오류 및 모범 사례 검사

#### 설치
```bash
# macOS
brew install tflint

# 또는 직접 설치
wget https://github.com/terraform-linters/tflint/releases/latest/download/tflint_darwin_amd64.zip
unzip tflint_darwin_amd64.zip
sudo mv tflint /usr/local/bin/
```

#### 사용
```bash
# 기본 검사
tflint

# 특정 파일만 검사
tflint main.tf

# 자동 수정 가능한 문제 수정
tflint --fix

# AWS 플러그인 설치 (AWS 리소스 검사)
tflint --init
```

**예상 출력:**
```
1 issue(s) found:

Warning: Missing resource documentation (terraform_docs_security)
  on main.tf line 1:
   1: resource "aws_s3_bucket" "example" {
```

---

### 7. **Infracost** - 비용 추정 (이미 설정됨) ✅

**용도:** 인프라 비용 예측

#### 사용
```bash
cd external-services/terraform/production

# 비용 추정
infracost breakdown --path .

# terraform plan과 함께 사용
terraform plan -out=tfplan
infracost breakdown --path . --terraform-plan-file tfplan

# CI/CD용 (JSON 출력)
infracost breakdown --path . --format json
```

**예상 출력:**
```
Project: production

 Name                                    Monthly Qty  Unit   Monthly Cost 
                                                                           
 aws_s3_bucket.tracking_log[0]                                                     
 └─ Storage (standard)                          1    GB         $0.02     
                                                                           
 aws_db_instance.airflow_db[0]                                                   
 ├─ Database instance (on-demand, db.r6g.large)  730  hours     $350.40   
 └─ Storage (general purpose SSD, gp2)          100  GB         $11.50    
                                                                           
 OVERALL TOTAL                                                      $361.92 
```

**장점:**
- ✅ 비용 예측
- ✅ PR에 자동 코멘트 (GitHub App)
- ✅ 비용 최적화 제안

---

### 8. **terraform show** - 상태 확인 ✅

**용도:** 현재 상태 파일 확인 (이미 배포된 경우)

```bash
# 현재 상태 확인
terraform show

# JSON 형식으로 출력
terraform show -json

# 특정 리소스만 확인
terraform state show aws_s3_bucket.tracking_log[0]
```

---

## 🛠️ 통합 테스트 스크립트

### test-terraform.sh 생성

```bash
#!/bin/bash
# Terraform 테스트 스크립트

set -e

echo "🔍 Terraform 테스트 시작..."

# 1. 포맷 확인
echo "📝 1. 코드 포맷 확인..."
if terraform fmt -check -recursive; then
    echo "✅ 포맷 통과"
else
    echo "❌ 포맷 오류 발견. 'terraform fmt' 실행 필요"
    exit 1
fi

# 2. 구문 검증
echo "🔎 2. 구문 검증..."
if terraform validate; then
    echo "✅ 구문 검증 통과"
else
    echo "❌ 구문 오류 발견"
    exit 1
fi

# 3. 초기화 확인
echo "🚀 3. 모듈 초기화 확인..."
terraform init -backend=false > /dev/null 2>&1
echo "✅ 초기화 완료"

# 4. Plan 실행 (실제 리소스 생성 안 함)
echo "📋 4. 실행 계획 확인..."
if terraform plan -out=tfplan > /dev/null 2>&1; then
    echo "✅ Plan 성공"
    terraform show tfplan | head -20
    rm -f tfplan
else
    echo "❌ Plan 실패"
    exit 1
fi

# 5. Checkov (설치된 경우)
if command -v checkov &> /dev/null; then
    echo "🔒 5. 보안 검사 (Checkov)..."
    checkov -d . --framework terraform --quiet || true
else
    echo "⏭️  5. Checkov 미설치 (건너뜀)"
fi

# 6. TFLint (설치된 경우)
if command -v tflint &> /dev/null; then
    echo "🔍 6. 린터 검사 (TFLint)..."
    tflint || true
else
    echo "⏭️  6. TFLint 미설치 (건너뜀)"
fi

echo ""
echo "✅ 모든 테스트 완료!"
```

---

## 📊 CI/CD 통합

### GitHub Actions 예시

```yaml
name: Terraform Test

on:
  pull_request:
    paths:
      - 'external-services/terraform/**'

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v2
        with:
          terraform_version: 1.6.0
      
      - name: Terraform Format Check
        run: terraform fmt -check -recursive
        working-directory: external-services/terraform/production
      
      - name: Terraform Validate
        run: terraform validate
        working-directory: external-services/terraform/production
      
      - name: Terraform Plan
        run: terraform plan
        working-directory: external-services/terraform/production
        env:
          AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
          AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
      
      - name: Checkov Security Scan
        uses: bridgecrewio/checkov-action@master
        with:
          directory: external-services/terraform/production
          framework: terraform
      
      - name: Infracost
        uses: infracost/actions/setup@v1
        with:
          api-key: ${{ secrets.INFRACOST_API_KEY }}
      
      - name: Infracost Breakdown
        run: |
          terraform plan -out=tfplan
          infracost breakdown --path . --terraform-plan-file tfplan
        working-directory: external-services/terraform/production
```

---

## ✅ 체크리스트

배포 전 확인사항:

- [ ] `terraform fmt -check` 통과
- [ ] `terraform validate` 통과
- [ ] `terraform plan` 성공 (예상치 못한 변경사항 없음)
- [ ] Checkov 보안 검사 통과 (선택)
- [ ] TFLint 검사 통과 (선택)
- [ ] Infracost 비용 확인 (선택)

---

## 🎯 권장 워크플로우

1. **코드 작성 후**
   ```bash
   terraform fmt
   terraform validate
   ```

2. **변경사항 확인**
   ```bash
   terraform plan
   ```

3. **보안 검사** (선택)
   ```bash
   checkov -d .
   ```

4. **비용 확인** (선택)
   ```bash
   infracost breakdown --path .
   ```

5. **배포**
   ```bash
   terraform apply
   ```

---

## 📚 참고 자료

- [Terraform Validate](https://www.terraform.io/docs/cli/commands/validate.html)
- [Terraform Plan](https://www.terraform.io/docs/cli/commands/plan.html)
- [Checkov Documentation](https://www.checkov.io/)
- [TFLint Documentation](https://github.com/terraform-linters/tflint)
- [Infracost Documentation](https://www.infracost.io/docs/)

