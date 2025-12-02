# ArgoCD 배포 순서

이 문서는 ArgoCD ApplicationSet의 배포 순서를 설명합니다.

## Sync Wave 순서

ArgoCD는 `sync-wave` 어노테이션을 기준으로 리소스를 순차적으로 배포합니다.

### Wave -1: 네임스페이스 (최우선)
- **Application**: `namespaces` (`argocd/applicationsets/00-namespaces.yaml`)
- **리소스**: `argocd/manifest/namespaces.yaml`
  - `ecommerce` namespace with `istio-injection: enabled`
  - `monitoring` namespace

### Wave 1-4: 인프라 컴포넌트
- **ApplicationSet**: `infrastructure` (`argocd/applicationsets/infrastructure.yaml`)

| Wave | 컴포넌트 | 네임스페이스 | 설명 |
|------|---------|-------------|------|
| 1 | external-services | ecommerce | 외부 서비스 연결 (DB, Redis, Kafka) |
| 2 | monitoring | monitoring | Prometheus, Grafana, Loki |
| 3 | istio | ecommerce | Istio Gateway, VirtualService, DestinationRule |
| 4 | argo-rollouts | argo-rollouts | Argo Rollouts + Analysis Templates |

### Wave 30: 마이크로서비스
- **ApplicationSet**: `services` (`argocd/applicationsets/services.yaml`)
- **서비스 목록**:
  - customer-service
  - order-service
  - payment-service
  - product-service
  - recommendation-service
  - saga-tracker
  - store-service

## Istio Sidecar 자동 주입

### 설정 위치

1. **네임스페이스 라벨** (Wave -1)
   ```yaml
   # argocd/manifest/namespaces.yaml
   apiVersion: v1
   kind: Namespace
   metadata:
     name: ecommerce
     labels:
       istio-injection: enabled  # ← 사이드카 자동 주입 활성화
   ```

2. **Istio Helm 차트** (Wave 3)
   ```yaml
   # charts/istio/values.yaml
   namespace:
     name: ecommerce
     create: true  # 기본값 (운영 환경)
     istioInjection: enabled
   
   # config/dev/istio.yaml (개발 환경 오버라이드)
   namespace:
     create: false  # 네임스페이스는 이미 Wave -1에서 생성됨
   ```

3. **네임스페이스 템플릿**
   ```yaml
   # charts/istio/templates/01-namespace.yaml
   {{- if .Values.namespace.create }}
   apiVersion: v1
   kind: Namespace
   metadata:
     name: {{ include "istio.namespace" . }}
     labels:
       {{- if eq .Values.namespace.istioInjection "enabled" }}
       istio-injection: enabled  # ← 라벨 추가
       {{- end }}
   {{- end }}
   ```

### 동작 방식

1. **클러스터 생성 시**:
   - Wave -1: `ecommerce` 네임스페이스가 `istio-injection: enabled` 라벨과 함께 생성됨
   - Wave 3: Istio 차트가 Gateway, VirtualService 등을 배포 (네임스페이스는 생성하지 않음)
   - Wave 30: 서비스 Pod 생성 시 Istio Mutating Webhook이 자동으로 사이드카 주입

2. **ArgoCD 재시작 시**:
   - 모든 리소스가 sync-wave 순서대로 재동기화됨
   - 네임스페이스 라벨이 유지되므로 사이드카 자동 주입 계속 작동

3. **클러스터 재시작 시**:
   - Kubernetes 리소스는 etcd에 저장되어 있으므로 유지됨
   - ArgoCD가 자동으로 상태를 확인하고 필요시 재동기화

## 검증 방법

### 1. 네임스페이스 라벨 확인
```bash
kubectl get namespace ecommerce --show-labels
# 출력: istio-injection=enabled 확인
```

### 2. Pod 사이드카 확인
```bash
kubectl get pods -n ecommerce
# READY 컬럼이 2/2 (애플리케이션 + istio-proxy)
```

### 3. Pod 컨테이너 확인
```bash
kubectl get pod <pod-name> -n ecommerce -o jsonpath='{.spec.containers[*].name}'
# 출력: <service-name> istio-proxy
```

### 4. ArgoCD Application 상태 확인
```bash
kubectl get applications -n argocd
# 모든 Application이 Healthy 상태인지 확인
```

## 문제 해결

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

### ArgoCD 동기화 실패

1. **Sync Wave 순서 확인**
   ```bash
   kubectl get applications -n argocd -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.annotations.argocd\.argoproj\.io/sync-wave}{"\n"}{end}' | sort -k2 -n
   ```

2. **수동 동기화**
   ```bash
   argocd app sync namespaces
   argocd app sync infrastructure-dev
   argocd app sync <service-name>-dev
   ```

## 참고 자료

- [ArgoCD Sync Waves](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/)
- [Istio Sidecar Injection](https://istio.io/latest/docs/setup/additional-setup/sidecar-injection/)
- [ArgoCD ApplicationSet](https://argo-cd.readthedocs.io/en/stable/user-guide/application-set/)
