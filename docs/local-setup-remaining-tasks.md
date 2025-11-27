# 로컬 개발 환경 설정 - 남은 작업

## 현재 상태

- ArgoCD ApplicationSet의 targetRevision이 feature 브랜치로 변경됨
- AnalysisTemplate에 count 값 추가 완료
- Argo Rollouts CRD 설치 완료
- AppProject에 Istio/Gateway API 리소스 권한 추가 완료

## 남은 작업

### 1. ECR 이미지 Pull Secret 생성

k3d 클러스터에서 AWS ECR 이미지를 pull하려면 인증 Secret이 필요합니다.

#### 사전 요구사항
- AWS CLI 설치
- AWS 자격증명 설정 (ECR pull 권한 필요)

#### 실행 명령어

```bash
# 1. AWS CLI 설치 (macOS)
brew install awscli

# 2. AWS 자격증명 설정 (이미 설정되어 있으면 스킵)
aws configure
# AWS Access Key ID: <your-access-key>
# AWS Secret Access Key: <your-secret-key>
# Default region name: ap-northeast-2
# Default output format: json

# 3. ecommerce 네임스페이스에 ECR Secret 생성
ECR_TOKEN=$(aws ecr get-login-password --region ap-northeast-2)
kubectl create secret docker-registry ecr-secret \
  --docker-server=963403601423.dkr.ecr.ap-northeast-2.amazonaws.com \
  --docker-username=AWS \
  --docker-password=$ECR_TOKEN \
  -n ecommerce

# 4. Secret 생성 확인
kubectl get secret ecr-secret -n ecommerce
```

#### Helm Chart 설정 (선택)

imagePullSecrets를 values에 추가하려면 `config/local/customer-service.yaml`에 다음 추가:

```yaml
imagePullSecrets:
  - name: ecr-secret
```

또는 모든 서비스에 적용하려면 차트의 기본 values.yaml을 수정하거나,
ServiceAccount에 imagePullSecrets를 추가합니다:

```bash
kubectl patch serviceaccount default -n ecommerce \
  -p '{"imagePullSecrets": [{"name": "ecr-secret"}]}'
```

### 2. ECR Token 갱신 (12시간마다 필요)

ECR 토큰은 12시간 후 만료됩니다. 갱신 명령어:

```bash
# Secret 삭제 후 재생성
kubectl delete secret ecr-secret -n ecommerce

ECR_TOKEN=$(aws ecr get-login-password --region ap-northeast-2)
kubectl create secret docker-registry ecr-secret \
  --docker-server=963403601423.dkr.ecr.ap-northeast-2.amazonaws.com \
  --docker-username=AWS \
  --docker-password=$ECR_TOKEN \
  -n ecommerce
```

#### 자동 갱신 스크립트

`scripts/refresh-ecr-secret.sh` 생성 권장:

```bash
#!/bin/bash
set -e

NAMESPACE=${1:-ecommerce}
SECRET_NAME=${2:-ecr-secret}
ECR_REGISTRY="963403601423.dkr.ecr.ap-northeast-2.amazonaws.com"
REGION="ap-northeast-2"

echo "Refreshing ECR secret in namespace: $NAMESPACE"

# Delete existing secret if exists
kubectl delete secret $SECRET_NAME -n $NAMESPACE 2>/dev/null || true

# Create new secret
ECR_TOKEN=$(aws ecr get-login-password --region $REGION)
kubectl create secret docker-registry $SECRET_NAME \
  --docker-server=$ECR_REGISTRY \
  --docker-username=AWS \
  --docker-password=$ECR_TOKEN \
  -n $NAMESPACE

echo "ECR secret refreshed successfully"
```

### 3. ArgoCD 동기화 확인

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

### 4. 개발 완료 후 targetRevision 복구

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
