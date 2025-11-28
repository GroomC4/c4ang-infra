# 로컬 개발 환경 설정 - 남은 작업

## 현재 상태

- ArgoCD ApplicationSet의 targetRevision이 feature 브랜치로 변경됨
- AnalysisTemplate에 count 값 추가 완료
- Argo Rollouts CRD 설치 완료
- AppProject에 Istio/Gateway API 리소스 권한 추가 완료
- **ECR Secret 관리 스크립트 추가 완료** (`scripts/platform/ecr.sh`)

## ECR 이미지 Pull Secret

### 자동 설정 (권장)

`local.sh` 스크립트가 클러스터 초기화 시 ECR Secret을 자동으로 생성합니다.

```bash
# 전체 환경 초기화 (ECR Secret 포함)
./scripts/bootstrap/local.sh
```

**사전 요구사항:**
- AWS CLI 설치: `brew install awscli`
- AWS 자격증명 설정: `aws configure` 또는 `aws sso login`

### 수동 관리

ECR Secret을 수동으로 관리하려면 전용 스크립트를 사용합니다:

```bash
# Secret 생성/갱신
./scripts/platform/ecr.sh

# 상태 확인 (만료 시간 포함)
./scripts/platform/ecr.sh --status

# Secret 삭제
./scripts/platform/ecr.sh --delete
```

### 토큰 만료 시 갱신 (12시간 후)

로컬 환경에서 12시간 이상 작업하는 경우, Secret을 수동으로 갱신해야 합니다:

```bash
./scripts/platform/ecr.sh
```

### Helm Chart 설정

imagePullSecrets를 values에 추가하려면 `config/local/customer-service.yaml`에 다음 추가:

```yaml
imagePullSecrets:
  - name: ecr-secret
```

또는 모든 서비스에 적용하려면 ServiceAccount에 imagePullSecrets를 추가:

```bash
kubectl patch serviceaccount default -n ecommerce \
  -p '{"imagePullSecrets": [{"name": "ecr-secret"}]}'
```

## 남은 작업

### 1. ArgoCD 동기화 확인

ECR Secret 생성 후 ArgoCD에서 customer-service-local 동기화:

```bash
# Hard refresh 실행
kubectl patch application root-application -n argocd \
  --type merge \
  -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'

# 또는 ArgoCD CLI 사용
argocd app sync customer-service-local

# Pod 상태 확인
kubectl get pods -n ecommerce -l app.kubernetes.io/name=customer-service
```

### 2. 개발 완료 후 targetRevision 복구

개발 작업 완료 시 ApplicationSet의 targetRevision을 HEAD로 복구:

```bash
# 수정이 필요한 파일들
# - argocd/applicationsets/services.yaml
# - argocd/applicationsets/infrastructure.yaml
# - argocd/applicationsets/airflow.yaml

# 각 파일에서 다음 라인을 수정:
# 변경 전: targetRevision: feature/adding-db-schema-and-enhancement-external-service
# 변경 후: targetRevision: HEAD
```

## 트러블슈팅

### ImagePullBackOff 에러

```bash
# Pod 이벤트 확인
kubectl describe pod <pod-name> -n ecommerce

# Secret 확인
kubectl get secret ecr-secret -n ecommerce -o yaml

# Docker config 디코딩하여 확인
kubectl get secret ecr-secret -n ecommerce -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d
```

### ECR 접근 권한 확인

```bash
# ECR 로그인 테스트
aws ecr get-login-password --region ap-northeast-2 | docker login --username AWS --password-stdin 963403601423.dkr.ecr.ap-northeast-2.amazonaws.com

# 이미지 존재 확인
aws ecr describe-images --repository-name c4ang-customer-service --region ap-northeast-2
```

## 관련 문서

- [docs/local-development-setup.md](./local-development-setup.md) - 로컬 개발 환경 전체 설정 가이드
- [docs/external-resource-dependency-management.md](./external-resource-dependency-management.md) - 외부 리소스 의존성 관리
