# Infracost 설정 가이드

Infracost는 Terraform 코드에 정의된 인프라의 예상 비용을 계산하고, 코드 변경에 따른 비용 변동을 분석하는 도구입니다.

## 📋 목차

1. [Infracost란?](#infracost란)
2. [설치 방법](#설치-방법)
3. [API 키 발급](#api-키-발급)
4. [설정 방법](#설정-방법)
5. [사용 방법](#사용-방법)
6. [CI/CD 통합](#cicd-통합)

## Infracost란?

Infracost는 다음 기능을 제공합니다:

- **비용 계산**: Terraform 코드를 분석하여 월별 예상 비용 계산
- **비용 변동 분석**: 코드 변경에 따른 비용 증감 분석
- **비용 최적화 제안**: 더 저렴한 대안 제시
- **CI/CD 통합**: Pull Request에 비용 정보 자동 추가

## 설치 방법

### macOS (Homebrew)

```bash
brew install infracost
```

### Linux / 다른 운영체제

```bash
curl -fsSL https://raw.githubusercontent.com/infracost/infracost/master/scripts/install.sh | sh
```

### 자동 설치 스크립트 사용

```bash
cd production
chmod +x scripts/infracost-setup.sh
./scripts/infracost-setup.sh
```

## API 키 발급

1. **Infracost 웹사이트 접속**
   - https://www.infracost.io/ 접속
   - "Get Started" 클릭

2. **계정 생성**
   - GitHub 계정으로 로그인 (또는 이메일로 가입)

3. **API 키 발급**
   - 대시보드에서 API 키 확인
   - 또는 Settings > API Keys에서 새 API 키 생성

4. **API 키 설정**

   ```bash
   # 방법 1: 환경 변수로 설정 (임시)
   export INFRACOST_API_KEY=your_api_key_here
   
   # 방법 2: .env.infracost 파일 생성 (영구)
   # .env.infracost 파일 생성 (Git에 커밋하지 마세요!)
   cat > .env.infracost << EOF
   INFRACOST_API_KEY=your_api_key_here
   EOF
   
   # 파일 로드
   source .env.infracost
   
   # 또는 ~/.zshrc 또는 ~/.bashrc에 추가 (영구 설정)
   echo 'export INFRACOST_API_KEY=your_api_key_here' >> ~/.zshrc
   source ~/.zshrc
   ```

   **⚠️ 주의**: 
   - `.env.infracost` 파일은 Git에 커밋하지 마세요!
   - `.gitignore` 파일에 이미 추가되어 있습니다.

## 설정 방법

### 1. 설정 파일 생성

`.infracost.yml` 파일이 이미 생성되어 있습니다. 필요에 따라 수정하세요:

```yaml
version: 0.1

terraform_dir: .
terraform_var_files:
  - only-rds.tfvars
```

### 2. 환경 변수 설정

`.env.infracost` 파일을 생성하여 API 키를 설정하세요:

```bash
cp .env.infracost.example .env.infracost
# .env.infracost 파일을 편집하여 API 키 입력
```

## 사용 방법

### 기본 비용 분석

```bash
# 현재 디렉토리의 Terraform 코드 분석
infracost breakdown --path .

# 변수 파일 지정
infracost breakdown --path . --terraform-var-file=only-rds.tfvars
```

### 스크립트 사용

```bash
# 비용 분석 스크립트 실행
chmod +x scripts/infracost-cost.sh
./scripts/infracost-cost.sh only-rds.tfvars
```

### 출력 형식 선택

```bash
# 테이블 형식 (기본)
infracost breakdown --path . --format table

# JSON 형식
infracost breakdown --path . --format json

# HTML 리포트
infracost breakdown --path . --format html > cost-report.html

# Diff 비교 (변경사항 비용)
infracost diff --path . --terraform-var-file=only-rds.tfvars
```

### 예제 출력

```
Project: production

 Name                                                              Monthly Qty  Unit   Monthly Cost 
                                                                                                    
 module.vpc_app.aws_nat_gateway.this[0]                                   730  hours       $32.85 
 module.vpc_app.aws_vpc.this[0]                                             1  months       $0.00 
 aws_db_instance.airflow_db[0]                                            730  hours       $15.20 
 module.vpc_db.aws_vpc.this[0]                                              1  months       $0.00 
                                                                                                    
 OVERALL TOTAL                                                                              $48.05 
────────────────────────────────────
```

## CI/CD 통합

Infracost는 두 가지 방식으로 통합할 수 있습니다:

1. **GitHub App (권장)**: 자동화된 통합, CI/CD 설정 불필요
2. **GitHub Actions**: 수동 설정, 더 많은 제어 가능

### GitHub App 통합 (권장) ⭐

GitHub App은 **가장 간단하고 권장되는 방법**입니다. CI/CD 파이프라인 설정 없이 자동으로 Pull Request에 비용 정보를 표시합니다.

#### 장점

- ✅ **CI/CD 설정 불필요**: Infracost가 자동으로 관리
- ✅ **한 번의 클릭으로 여러 리포지토리 추가 가능**
- ✅ **AutoFix PR 자동 생성**: 기존 이슈에 대한 자동 수정 PR 생성
- ✅ **더 빠른 실행**: 변경된 폴더만 실행
- ✅ **자동 업데이트**: Infracost가 최신 버전 유지

#### 설정 방법

1. **Infracost Cloud 가입**
   - https://www.infracost.io/cloud 접속
   - GitHub 계정으로 로그인 (또는 이메일로 가입)
   - 무료 체험 시작 (신용카드 불필요)

2. **조직 생성**
   - 모든 사용자는 개인용 기본 조직을 가지고 있습니다
   - 회사를 위한 새 조직 생성 (페이지 상단의 조직 드롭다운 사용)

3. **GitHub App 설치**
   - Settings > Org Settings > Integrations > GitHub 이동
   - 마법사를 따라 리포지토리 선택
   - Infracost에게 접근 권한을 부여할 리포지토리 선택

4. **설정 파일 추가 (선택사항)**
   - 리포지토리 루트에 `infracost.yml` 또는 `infracost.yml.tmpl` 파일 추가
   - 또는 Repo > my repo > Settings 탭에서 설정
   - `infracost-usage.yml` 파일로 사용량 값 정의 가능

5. **테스트**
   - 테스트 Pull Request 생성
   - Infracost가 자동으로 코멘트 추가
   - Infracost Cloud 대시보드에서도 비용 추정 확인

#### GitHub App 작동 방식

- Pull Request가 열리거나 새 커밋이 푸시될 때마다 자동 실행
- 기본 브랜치와 비교하여 비용 차이 계산
- Pull Request에 코멘트 자동 추가
- FinOps 정책 이슈 및 태깅 정책 표시

#### Pull Request 코멘트 비활성화

- Org Settings > Integrations > GitHub App 페이지에서 비활성화 가능
- 비용 추정은 Infracost Cloud 대시보드에서만 확인 가능
- 엔지니어 워크플로우에 영향을 주지 않고 테스트 가능

#### 정책 이슈 해제 또는 일시 중지

- GitHub Pull Request UI에서 직접 해제 또는 일시 중지 가능
- 정책에서 수정을 요구하더라도 가능
- 엔지니어가 중요한 변경사항을 빠르게 배포할 수 있음
- Pull Request 코멘트에 `@infracost help`를 추가하면 더 많은 정보 확인 가능

#### Required Check로 설정

정책을 "엔지니어가 이슈 해결 또는 해제 필요"로 표시하면, Infracost는 해당 정책을 실패한 Pull Request에 대해 "failed" 상태 체크를 GitHub에 반환합니다.

그러나 이것만으로는 GitHub에서 병합 버튼이 차단되지 않습니다. 병합을 차단하려면 Infracost를 "Required Check"로 표시해야 합니다:

1. **권장 방법**: GitHub Ruleset 생성
   - GitHub에서 Settings > Repository > Rulesets 이동
   - 새 ruleset 생성 (스크린샷 참조)
   - 체크 추가 시 "Infracost" (대문자 I) 사용
   - 조직의 모든 리포지토리에 적용

2. **대안**: Branch Protection Rules 사용
   - 리포지토리별로 설정 필요
   - Settings > Branches > Protect matching branches
   - "Require status checks to pass before merging" 옵션 활성화

#### GitHub Enterprise 지원

- **GitHub Enterprise Cloud**: 일반 GitHub App과 동일한 사용 방법
- **GitHub Enterprise Server**: support@infracost.io로 이메일 발송하여 활성화
- mTLS 지원 가능 (클라이언트 인증서 필요)

자세한 내용: [Infracost GitHub App 공식 문서](https://www.infracost.io/docs/integrations/github_app/)

### GitHub Actions 통합

수동으로 CI/CD 파이프라인을 설정하고 싶다면 GitHub Actions를 사용할 수 있습니다.

`.github/workflows/infracost.yml` 파일 생성:

```yaml
name: Infracost
on:
  pull_request:
    paths:
      - 'production/**/*.tf'
      - 'production/**/*.tfvars'

jobs:
  infracost:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Setup Infracost
        uses: infracost/actions/setup@v2
        with:
          api-key: ${{ secrets.INFRACOST_API_KEY }}
      
      - name: Run Infracost
        run: |
          cd production
          infracost breakdown --path . \
            --format json \
            --out-file /tmp/infracost.json
      
      - name: Comment PR
        uses: infracost/actions/comment@v2
        with:
          path: /tmp/infracost.json
          behavior: update
```

**참고**: GitHub App을 사용하는 경우 GitHub Actions 설정은 필요하지 않습니다. GitHub App이 자동으로 모든 것을 처리합니다.

#### GitHub Actions에서 GitHub App으로 마이그레이션

1. GitHub App 설치 (위의 GitHub App 통합 섹션 참조)
2. 테스트 Pull Request로 확인
3. GitHub Actions에서 모든 Infracost 단계 제거

### GitLab CI/CD

`.gitlab-ci.yml`에 추가:

```yaml
infracost:
  image: infracost/infracost:latest
  script:
    - cd production
    - infracost breakdown --path . --format json --out-file infracost.json
    - infracost comment gitlab --path infracost.json --pull-request $CI_MERGE_REQUEST_IID
  only:
    - merge_requests
  variables:
    INFRACOST_API_KEY: $INFRACOST_API_KEY
```

## 고급 기능

### 비용 예산 설정

`.infracost.yml`에 예산 설정 추가:

```yaml
budget:
  monthly_budget: 100
  currency: USD
```

### 특정 리소스만 분석

```bash
# 특정 리소스 타입만 분석
infracost breakdown --path . --terraform-var-file=only-rds.tfvars \
  --include-path-pattern="**/rds.tf"
```

### 비교 분석

```bash
# 현재 코드와 변경사항 비교
infracost diff --path . \
  --terraform-var-file=only-rds.tfvars \
  --compare-to=terraform.tfstate
```

## 문제 해결

### API 키 오류

```
Error: INFRACOST_API_KEY is not set
```

**해결 방법**: API 키를 환경 변수로 설정하세요.

```bash
export INFRACOST_API_KEY=your_api_key
```

### Terraform 변수 오류

```
Error: Missing required variable
```

**해결 방법**: 변수 파일을 지정하세요.

```bash
infracost breakdown --path . --terraform-var-file=only-rds.tfvars
```

### 리소스 인식 안 됨

일부 리소스는 Infracost에서 지원하지 않을 수 있습니다. `--show-skipped` 옵션으로 확인하세요:

```bash
infracost breakdown --path . --show-skipped
```

## 참고 자료

- [Infracost 공식 문서](https://www.infracost.io/docs/)
- [Infracost GitHub](https://github.com/infracost/infracost)
- [지원되는 리소스 목록](https://www.infracost.io/docs/supported_resources/)

