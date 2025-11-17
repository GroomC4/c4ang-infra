# ArgoCD Application for Istio

이 디렉토리는 이 Helm 차트를 ArgoCD로 배포하기 위한 Application 매니페스트를 포함합니다.

## 📋 파일

- `application.yaml`: ArgoCD Application 정의

## 🚀 사용 방법

### 1. Git 리포지토리 URL 업데이트

```bash
# application.yaml의 repoURL을 실제 리포지토리로 변경
sed -i 's|https://github.com/your-org/c4ang-infra.git|YOUR_REPO_URL|g' application.yaml
```

### 2. ArgoCD에 등록

```bash
# Application 생성
kubectl apply -f application.yaml

# 또는 ArgoCD CLI 사용
argocd app create -f application.yaml
```

### 3. 동기화

```bash
# 자동 동기화가 활성화되어 있으므로 자동으로 배포됨
# 수동으로 즉시 동기화하려면:
argocd app sync istio-config
```

### 4. 확인

```bash
# Application 상태
argocd app get istio-config

# 네임스페이스 라벨 확인
kubectl get namespace ecommerce --show-labels
# 출력에 istio-injection=enabled 포함되어야 함
```

## 🔧 환경별 설정

### Development

```yaml
# application-dev.yaml
spec:
  source:
    helm:
      values: |
        namespace:
          name: ecommerce-dev
        gateway:
          main:
            hostname: api-dev.ecommerce.com
```

### Production

```yaml
# application-prod.yaml
spec:
  source:
    helm:
      values: |
        namespace:
          name: ecommerce
        gateway:
          main:
            hostname: api.ecommerce.com
        security:
          mTLS:
            mode: STRICT
```

## 📝 참고

- [ArgoCD 공식 문서](https://argo-cd.readthedocs.io/)
- [상위 README](../README.md)

