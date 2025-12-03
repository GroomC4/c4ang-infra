# ArgoCD 마이그레이션 가이드

## 문제 상황

### 중복 Application 생성 문제

클러스터 생성 시 다음과 같은 중복 Application이 생성되었습니다:

```
service-customer (레거시)  ←→  customer-service-dev (ApplicationSet)
service-store (레거시)     ←→  store-service-dev (ApplicationSet)
service-order (레거시)     ←→  order-service-dev (ApplicationSet)
...
```

### 원인

1. **레거시 파일**: `argocd/manifest/root-apps.yaml`
   - 개별 Application을 직접 정의
   - `service-customer`, `service-store` 등 생성

2. **새로운 방식**: `argocd/applicationsets/services.yaml`
   - ApplicationSet으로 자동 생성
   - `customer-service-dev`, `store-service-dev` 등 생성

3. **충돌 발생**:
   - `argocd/applicationsets/00-namespaces.yaml`이 `argocd/manifest` 전체를 참조
   - `root-apps.yaml`도 함께 적용되어 중복 생성

## 해결 방법

### 1. 레거시 파일 비활성화

```bash
# root-apps.yaml을 deprecated로 이름 변경
mv argocd/manifest/root-apps.yaml argocd/manifest/root-apps.yaml.deprecated
```

### 2. namespaces Application 수정

`argocd/applicationsets/00-namespaces.yaml`:

```yaml
spec:
  source:
    path: argocd/manifest
    directory:
      include: 'namespaces.yaml'  # ← namespaces.yaml만 포함
```

### 3. 프로젝트 수정

```yaml
spec:
  project: default  # platform → default (platform 프로젝트가 없음)
```

### 4. 레거시 Application 삭제

```bash
# 중복된 레거시 Application 삭제
kubectl delete application service-customer service-store -n argocd
kubectl delete application service-order service-payment service-product -n argocd
kubectl delete application infra-monitoring infra-kafka-cluster -n argocd
```

## 새로운 구조

### ApplicationSet 기반 배포

```
argocd/
├── applicationsets/
│   ├── 00-namespaces.yaml      # Wave -1: 네임스페이스
│   ├── infrastructure.yaml     # Wave 1-4: 인프라
│   ├── services.yaml           # Wave 30: 서비스
│   └── airflow.yaml            # Wave 40: Airflow
├── manifest/
│   ├── namespaces.yaml         # 네임스페이스 정의만
│   └── root-apps.yaml.deprecated  # 레거시 (사용 안 함)
└── projects/
    ├── infrastructure.yaml
    └── applications.yaml
```

### 배포 순서

```
Wave -1: namespaces (istio-injection: enabled)
  ↓
Wave 1: external-services
  ↓
Wave 2: monitoring
  ↓
Wave 3: istio
  ↓
Wave 4: argo-rollouts
  ↓
Wave 30: 마이크로서비스 (사이드카 자동 주입)
```

## Istio 사이드카 자동 주입

### 설정 위치

1. **네임스페이스 라벨** (Wave -1)
   ```yaml
   # argocd/manifest/namespaces.yaml
   metadata:
     labels:
       istio-injection: enabled  # ← 사이드카 자동 주입
   ```

2. **Istio Helm 차트**
   ```yaml
   # charts/istio/templates/01-namespace.yaml
   {{- if eq .Values.namespace.istioInjection "enabled" }}
   istio-injection: enabled
   {{- end }}
   ```

3. **환경별 설정**
   ```yaml
   # config/dev/istio.yaml
   namespace:
     create: false  # 네임스페이스는 Wave -1에서 이미 생성됨
   ```

### 검증

```bash
# 1. 네임스페이스 라벨 확인
kubectl get namespace ecommerce --show-labels
# 출력: istio-injection=enabled

# 2. Pod 사이드카 확인
kubectl get pods -n ecommerce
# READY 컬럼이 2/2 (애플리케이션 + istio-proxy)

# 3. 컨테이너 확인
kubectl get pod <pod-name> -n ecommerce -o jsonpath='{.spec.containers[*].name}'
# 출력: <service-name> istio-proxy
```

## 문제 해결

### 중복 Application이 다시 생성되는 경우

1. **레거시 파일 확인**
   ```bash
   ls -la argocd/manifest/root-apps.yaml*
   # root-apps.yaml.deprecated만 있어야 함
   ```

2. **namespaces Application 확인**
   ```bash
   kubectl get application namespaces -n argocd -o yaml | grep -A 5 "source:"
   # directory.include: 'namespaces.yaml' 확인
   ```

3. **레거시 Application 삭제**
   ```bash
   kubectl get applications -n argocd | grep "service-"
   # service-customer, service-store 등이 있으면 삭제
   ```

### 사이드카가 주입되지 않는 경우

1. **네임스페이스 라벨 확인**
   ```bash
   kubectl label namespace ecommerce istio-injection=enabled --overwrite
   ```

2. **Pod 재시작**
   ```bash
   kubectl rollout restart deployment -n ecommerce
   ```

3. **Istio Webhook 확인**
   ```bash
   kubectl get mutatingwebhookconfigurations | grep istio
   ```

## 마이그레이션 체크리스트

- [x] `root-apps.yaml` → `root-apps.yaml.deprecated`로 이름 변경
- [x] `00-namespaces.yaml`에 `directory.include` 추가
- [x] `00-namespaces.yaml` 프로젝트를 `default`로 변경
- [x] 레거시 Application 삭제
- [x] `namespaces.yaml`에 `istio-injection: enabled` 라벨 추가
- [x] `charts/istio/templates/01-namespace.yaml`에 라벨 추가
- [x] 문서 작성 (`DEPLOYMENT-ORDER.md`, `MIGRATION-GUIDE.md`)

## 참고 자료

- [DEPLOYMENT-ORDER.md](./DEPLOYMENT-ORDER.md) - 배포 순서 상세 설명
- [ArgoCD ApplicationSet](https://argo-cd.readthedocs.io/en/stable/user-guide/application-set/)
- [Istio Sidecar Injection](https://istio.io/latest/docs/setup/additional-setup/sidecar-injection/)
