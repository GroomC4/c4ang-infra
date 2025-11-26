# Terraform 도구 설정 가이드

이 프로젝트에서 사용하는 Terraform 도구들의 설정 방법을 안내합니다.

## 📋 목차

1. [Infracost 설정](#infracost-설정)
2. [Brainboard 설정](#brainboard-설정)
3. [빠른 시작](#빠른-시작)

## Infracost 설정

Infracost는 두 가지 방식으로 사용할 수 있습니다:

1. **GitHub App (권장)**: CI/CD 설정 불필요, 자동으로 Pull Request에 코멘트 추가
2. **CLI (로컬)**: 로컬에서 비용 분석 실행

### 방법 1: GitHub App 통합 (권장) ⭐

가장 간단하고 권장되는 방법입니다. CI/CD 파이프라인 설정 없이 자동으로 작동합니다.

#### 설정 단계

1. **Infracost Cloud 가입**
   - https://www.infracost.io/cloud 접속
   - GitHub 계정으로 로그인

2. **조직 생성**
   - 페이지 상단의 조직 드롭다운에서 새 조직 생성

3. **GitHub App 설치**
   - Settings > Org Settings > Integrations > GitHub 이동
   - 마법사를 따라 리포지토리 선택
   - Infracost에게 접근 권한을 부여할 리포지토리 선택

4. **테스트**
   - 테스트 Pull Request 생성
   - Infracost가 자동으로 코멘트 추가
   - 비용 정보가 Pull Request에 표시됨

#### 장점

- ✅ CI/CD 설정 불필요
- ✅ 한 번의 클릭으로 여러 리포지토리 추가
- ✅ AutoFix PR 자동 생성
- ✅ 변경된 폴더만 실행되어 더 빠름
- ✅ 자동 업데이트

자세한 설정 방법: [INFRACOST_SETUP.md](./docs/INFRACOST_SETUP.md#github-app-통합-권장)

### 방법 2: CLI 사용 (로컬)

로컬에서 비용을 분석하고 싶다면 CLI를 사용할 수 있습니다.

#### 1. 설치

```bash
# macOS (Homebrew)
brew install infracost

# 또는 자동 설치 스크립트 사용
cd production
chmod +x scripts/infracost-setup.sh
./scripts/infracost-setup.sh
```

#### 2. API 키 발급

1. https://www.infracost.io/ 접속
2. 계정 생성 (GitHub 로그인 권장)
3. API 키 발급

#### 3. API 키 설정

```bash
# 환경 변수로 설정
export INFRACOST_API_KEY=your_api_key_here

# 또는 .env.infracost 파일 생성 (영구 설정)
cat > .env.infracost << EOF
INFRACOST_API_KEY=your_api_key_here
EOF

# 파일 로드
source .env.infracost
```

**⚠️ 주의**: `.env.infracost` 파일은 Git에 커밋하지 마세요!

#### 4. 사용 방법

```bash
# 기본 비용 분석
cd production
infracost breakdown --path . --terraform-var-file=only-rds.tfvars

# 또는 스크립트 사용
./scripts/infracost-cost.sh only-rds.tfvars
```

### 5. 자세한 설정 가이드

더 자세한 설정 방법은 [INFRACOST_SETUP.md](./docs/INFRACOST_SETUP.md)를 참고하세요.

## Brainboard 설정

### 1. 계정 생성

1. https://www.brainboard.co/ 접속
2. "Get Started" 클릭
3. GitHub 계정으로 로그인 (권장)

### 2. 프로젝트 생성

1. 대시보드에서 "New Project" 클릭
2. 프로젝트 이름 입력 (예: "c4-production")
3. 클라우드 제공자 선택 (AWS)

### 3. Terraform 코드 가져오기

#### 방법 1: 파일 업로드

1. 프로젝트에서 "Import" 클릭
2. "Upload Terraform Files" 선택
3. 다음 파일들 업로드:
   - `main.tf`
   - `rds.tf`
   - `eks.tf`
   - `variables.tf`
   - `only-rds.tfvars`

#### 방법 2: Git 리포지토리 연동

1. 프로젝트 설정에서 "Git Integration" 선택
2. GitHub 리포지토리 연결
3. `production/` 디렉토리 선택

### 4. 인프라 시각화

- 자동 생성된 다이어그램 확인
- VPC, 서브넷, RDS 등 리소스 시각화
- 리소스 간 관계 확인

### 5. 자세한 설정 가이드

더 자세한 설정 방법은 [BRAINBOARD_SETUP.md](./docs/BRAINBOARD_SETUP.md)를 참고하세요.

## 빠른 시작

### Infracost 빠른 시작

```bash
# 1. 설치
brew install infracost

# 2. API 키 설정
export INFRACOST_API_KEY=your_api_key

# 3. 비용 분석
cd production
infracost breakdown --path . --terraform-var-file=only-rds.tfvars
```

### Brainboard 빠른 시작

1. https://www.brainboard.co/ 접속
2. 계정 생성
3. 새 프로젝트 생성
4. Terraform 파일 업로드
5. 인프라 시각화 확인

## 추가 도구

### Terraform-docs

```bash
# 설치
brew install terraform-docs

# 문서 생성
terraform-docs markdown table . > README.md
```

### TFLint

```bash
# 설치
brew install tflint

# 코드 검사
tflint
```

### Checkov

```bash
# 설치
brew install checkov

# 보안 검사
checkov -d .
```

## 문제 해결

### Infracost API 키 오류

```
Error: INFRACOST_API_KEY is not set
```

**해결 방법**:
```bash
export INFRACOST_API_KEY=your_api_key
```

### Brainboard 코드 파싱 오류

**해결 방법**:
- Terraform 코드 문법 확인
- Terraform 버전 호환성 확인
- 모듈 경로 확인

## 참고 자료

- [Infracost 설정 가이드](./docs/INFRACOST_SETUP.md)
- [Brainboard 설정 가이드](./docs/BRAINBOARD_SETUP.md)
- [Infracost 공식 문서](https://www.infracost.io/docs/)
- [Brainboard 공식 문서](https://docs.brainboard.co/)

