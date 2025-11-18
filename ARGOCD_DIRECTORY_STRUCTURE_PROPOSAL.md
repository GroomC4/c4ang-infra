# ArgoCD를 위한 효율적인 디렉토리 구조 제안

## 📋 현재 구조의 문제점

현재 `helm/` 디렉토리는 다음과 같은 문제가 있습니다:

```
helm/
├── kafka-cluster/         # Kafka 관련
├── kafka-topics/          # Kafka 관련
├── schema-registry/       # Kafka 관련
├── kafka-connect/         # Kafka 관련
├── kafka-ui/              # Kafka 관련
├── management-base/       # 관리 도구
├── statefulset-base/      # 상태 저장 서비스
├── services/              # 애플리케이션 서비스
└── test-infrastructure/   # 테스트
```

**문제점:**
1. **Kafka 관련 리소스가 분산**되어 있어 ArgoCD Application 관리가 복잡
2. **배포 의존성**을 표현하기 어려움 (Kafka → Schema Registry → Connect)
3. **환경별 관리** (dev/staging/prod)가 불명확
4. **App of Apps 패턴** 적용이 어려움

---

## 🎯 제안 구조 (Option 1: App of Apps 패턴)

### 구조

```
argocd/
├── apps/                          # ArgoCD Application 정의
│   ├── kafka-infra.yaml          # Kafka 인프라 App of Apps
│   ├── data-platform.yaml        # 데이터 플랫폼 App of Apps
│   └── services.yaml             # 마이크로서비스 App of Apps
│
├── environments/                  # 환경별 설정
│   ├── dev/
│   │   ├── kafka-infra/
│   │   │   ├── kustomization.yaml
│   │   │   └── values/
│   │   │       ├── kafka-cluster.yaml
│   │   │       ├── schema-registry.yaml
│   │   │       └── kafka-connect.yaml
│   │   └── services/
│   │       └── kustomization.yaml
│   │
│   ├── staging/
│   │   └── kafka-infra/
│   │       └── kustomization.yaml
│   │
│   └── prod/
│       └── kafka-infra/
│           └── kustomization.yaml
│
└── base/                          # 기본 Helm 차트
    ├── kafka-infra/
    │   ├── kafka-cluster/
    │   │   ├── Chart.yaml
    │   │   └── values.yaml
    │   ├── schema-registry/
    │   │   ├── Chart.yaml
    │   │   └── values.yaml
    │   ├── kafka-topics/
    │   │   ├── Chart.yaml
    │   │   └── values.yaml
    │   ├── kafka-connect/
    │   │   ├── Chart.yaml
    │   │   └── values.yaml
    │   └── kafka-ui/
    │       ├── Chart.yaml
    │       └── values.yaml
    │
    ├── data-platform/
    │   ├── postgresql/
    │   ├── redis/
    │   └── airflow/
    │
    └── services/
        └── customer-service/
```

### ArgoCD Application 예시

**`argocd/apps/kafka-infra.yaml` (App of Apps)**

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: kafka-infra
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/c4ang-infra.git
    targetRevision: main
    path: argocd/environments/prod/kafka-infra
  destination:
    server: https://kubernetes.default.svc
    namespace: kafka
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

**`argocd/environments/prod/kafka-infra/kustomization.yaml`**

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: kafka

helmCharts:
  - name: kafka-cluster
    repo: oci://your-registry/charts
    releaseName: kafka-cluster
    namespace: kafka
    valuesFile: values/kafka-cluster.yaml
    includeCRDs: true

  - name: schema-registry
    repo: https://confluentinc.github.io/cp-helm-charts/
    releaseName: schema-registry
    namespace: kafka
    valuesFile: values/schema-registry.yaml
    version: 0.6.1

  - name: kafka-connect
    repo: oci://your-registry/charts
    releaseName: kafka-connect
    namespace: kafka
    valuesFile: values/kafka-connect.yaml

  - name: kafka-ui
    repo: oci://your-registry/charts
    releaseName: kafka-ui
    namespace: kafka
    valuesFile: values/kafka-ui.yaml
```

---

## 🎯 제안 구조 (Option 2: Simplified - 추천!)

### 구조

```
helm/
├── README.md
├── build-dependencies.sh
│
├── infrastructure/               # 인프라 계층
│   ├── kafka/
│   │   ├── Chart.yaml           # Umbrella Chart
│   │   ├── values.yaml          # 기본값
│   │   ├── values-dev.yaml      # 개발 환경
│   │   ├── values-prod.yaml     # 프로덕션 환경
│   │   ├── charts/              # 서브차트들
│   │   │   ├── kafka-cluster/
│   │   │   ├── schema-registry/
│   │   │   ├── kafka-topics/
│   │   │   ├── kafka-connect/
│   │   │   └── kafka-ui/
│   │   └── templates/           # 공통 리소스
│   │       └── namespace.yaml
│   │
│   └── data-platform/
│       ├── Chart.yaml           # Umbrella Chart
│       ├── values.yaml
│       └── charts/
│           ├── postgresql/
│           ├── redis/
│           └── airflow/
│
├── services/                     # 애플리케이션 계층
│   └── customer-service/
│       ├── Chart.yaml
│       ├── values-dev.yaml
│       └── values-prod.yaml
│
└── argocd/                       # ArgoCD 설정
    ├── projects/
    │   └── c4ang-platform.yaml
    │
    └── applications/
        ├── infrastructure/
        │   ├── kafka.yaml
        │   └── data-platform.yaml
        └── services/
            └── customer-service.yaml
```

### Umbrella Chart 예시

**`helm/infrastructure/kafka/Chart.yaml`**

```yaml
apiVersion: v2
name: kafka-infra
description: Kafka Infrastructure Umbrella Chart
type: application
version: 1.0.0

dependencies:
  # 1단계: Kafka Cluster (Strimzi 기반)
  - name: kafka-cluster
    version: "1.0.0"
    repository: "file://./charts/kafka-cluster"
    condition: kafka-cluster.enabled

  # 2단계: Schema Registry (Kafka 의존)
  - name: schema-registry
    version: "1.0.0"
    repository: "file://./charts/schema-registry"
    condition: schema-registry.enabled

  # 3단계: Kafka Topics
  - name: kafka-topics
    version: "1.0.0"
    repository: "file://./charts/kafka-topics"
    condition: kafka-topics.enabled

  # 4단계: Kafka Connect
  - name: kafka-connect
    version: "1.0.0"
    repository: "file://./charts/kafka-connect"
    condition: kafka-connect.enabled

  # 5단계: Kafka UI (선택)
  - name: kafka-ui
    version: "1.0.0"
    repository: "file://./charts/kafka-ui"
    condition: kafka-ui.enabled
```

**`helm/infrastructure/kafka/values.yaml` (기본값)**

```yaml
# 전역 설정
global:
  namespace: kafka
  kafkaClusterName: c4-kafka

# 각 컴포넌트 활성화 여부
kafka-cluster:
  enabled: true

schema-registry:
  enabled: true
  replicaCount: 3

kafka-topics:
  enabled: true

kafka-connect:
  enabled: true

kafka-ui:
  enabled: true
```

**`helm/infrastructure/kafka/values-prod.yaml` (프로덕션)**

```yaml
# 프로덕션 오버라이드
kafka-cluster:
  enabled: true
  replicas: 3
  storage:
    size: 100Gi
    storageClass: gp3

schema-registry:
  enabled: true
  replicaCount: 3
  resources:
    requests:
      cpu: 500m
      memory: 1Gi
    limits:
      cpu: 2000m
      memory: 2Gi

kafka-topics:
  enabled: true
  topics:
    - name: orders
      partitions: 12
      replicationFactor: 3

kafka-connect:
  enabled: true
  replicas: 3

kafka-ui:
  enabled: true
```

**`helm/infrastructure/kafka/values-dev.yaml` (개발)**

```yaml
# 개발 환경 오버라이드
kafka-cluster:
  enabled: true
  replicas: 1
  storage:
    type: ephemeral  # 개발에선 휘발성

schema-registry:
  enabled: true
  replicaCount: 1
  resources:
    requests:
      cpu: 100m
      memory: 256Mi

kafka-topics:
  enabled: true

kafka-connect:
  enabled: false  # 개발에선 비활성화

kafka-ui:
  enabled: true
```

### ArgoCD Application 정의

**`helm/argocd/applications/infrastructure/kafka.yaml`**

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: kafka-infra
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: c4ang-platform

  source:
    repoURL: https://github.com/GroomC4/c4ang-infra.git
    targetRevision: main
    path: helm/infrastructure/kafka
    helm:
      valueFiles:
        - values.yaml
        - values-prod.yaml  # 환경에 따라 변경

  destination:
    server: https://kubernetes.default.svc
    namespace: kafka

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m

  # 배포 순서 제어
  syncWaves:
    - wave: 0  # Namespace
    - wave: 1  # Kafka Cluster
    - wave: 2  # Schema Registry
    - wave: 3  # Topics, Connect
    - wave: 4  # UI
```

---

## 🔄 마이그레이션 계획

### 현재 → 제안 구조 (Option 2) 마이그레이션

```bash
# 1. 새 디렉토리 구조 생성
mkdir -p helm/infrastructure/kafka/charts
mkdir -p helm/infrastructure/data-platform/charts
mkdir -p helm/argocd/{projects,applications/{infrastructure,services}}

# 2. Kafka 관련 차트 이동
mv helm/kafka-cluster helm/infrastructure/kafka/charts/
mv helm/schema-registry helm/infrastructure/kafka/charts/
mv helm/kafka-topics helm/infrastructure/kafka/charts/
mv helm/kafka-connect helm/infrastructure/kafka/charts/
mv helm/kafka-ui helm/infrastructure/kafka/charts/

# 3. Data Platform 차트 이동
mv helm/statefulset-base/postgresql helm/infrastructure/data-platform/charts/
mv helm/statefulset-base/redis helm/infrastructure/data-platform/charts/
mv helm/management-base/airflow helm/infrastructure/data-platform/charts/

# 4. Umbrella Chart 생성
# (위의 예시 참고하여 Chart.yaml, values.yaml 생성)

# 5. ArgoCD Application 정의 생성
# (위의 예시 참고)
```

---

## 📊 비교표

| 항목 | 현재 구조 | Option 1 (App of Apps) | Option 2 (Umbrella) ⭐ |
|------|----------|------------------------|----------------------|
| **복잡도** | 낮음 | 높음 | 중간 |
| **ArgoCD 통합** | 어려움 | 쉬움 | 쉬움 |
| **배포 의존성 관리** | 수동 | 자동 (Sync Waves) | 자동 (Helm Dependencies) |
| **환경별 관리** | 어려움 | 쉬움 (Kustomize) | 쉬움 (values-{env}.yaml) |
| **재사용성** | 낮음 | 높음 | 높음 |
| **학습 곡선** | 낮음 | 높음 | 중간 |
| **유지보수** | 어려움 | 쉬움 | 쉬움 |
| **GitOps 친화도** | 낮음 | 매우 높음 | 높음 |

---

## ✅ 권장사항

### Option 2 (Umbrella Chart 방식)를 추천합니다!

**이유:**

1. **간단하면서 강력함**
   - Helm의 기본 기능(dependencies)으로 의존성 관리
   - 추가 도구(Kustomize) 없이 환경별 관리

2. **배포 순서 보장**
   - Chart dependencies가 자동으로 순서 제어
   - Schema Registry는 Kafka 이후 자동 배포

3. **환경별 관리 용이**
   - `values-dev.yaml`, `values-prod.yaml`로 명확히 분리
   - ArgoCD에서 valueFiles만 변경하면 됨

4. **Atomic 배포**
   - Kafka 인프라 전체를 하나의 단위로 배포/롤백
   - 일부만 배포되는 위험 없음

5. **모니터링 간편**
   - ArgoCD에서 하나의 Application만 모니터링
   - 의존성 그래프 자동 표시

---

## 🚀 다음 단계

1. **Option 2 구조 적용 여부 결정**
2. **마이그레이션 스크립트 작성**
3. **ArgoCD Application 정의 작성**
4. **개발 환경에서 테스트**
5. **프로덕션 적용**

---

## 📝 추가 고려사항

### Sync Waves (세밀한 제어 필요 시)

```yaml
# helm/infrastructure/kafka/templates/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: kafka
  annotations:
    argocd.argoproj.io/sync-wave: "0"
```

```yaml
# helm/infrastructure/kafka/charts/kafka-cluster/templates/kafka.yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "1"
```

```yaml
# helm/infrastructure/kafka/charts/schema-registry/templates/deployment.yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "2"
```

### Health Checks

ArgoCD가 리소스 준비 상태를 올바르게 감지하도록:

```yaml
# ArgoCD Application에 추가
spec:
  ignoreDifferences:
    - group: kafka.strimzi.io
      kind: Kafka
      jsonPointers:
        - /status

  # Custom Health Check
  health:
    - kind: Kafka
      check: |
        hs = {}
        if obj.status ~= nil then
          if obj.status.conditions ~= nil then
            for i, condition in ipairs(obj.status.conditions) do
              if condition.type == "Ready" and condition.status == "True" then
                hs.status = "Healthy"
                hs.message = "Kafka cluster is ready"
                return hs
              end
            end
          end
        end
        hs.status = "Progressing"
        hs.message = "Waiting for Kafka cluster"
        return hs
```

---

**질문이나 추가 요구사항이 있으시면 말씀해주세요!**
