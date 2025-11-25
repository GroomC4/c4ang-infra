# C4ang Infrastructure - Architecture

## 프로젝트 구조

```
c4ang-infra/
├── bootstrap/                    # ArgoCD 설치 및 부트스트랩
│   ├── install-argocd.sh        # ArgoCD 설치 스크립트
│   ├── root-application.yaml    # App of Apps 루트
│   └── README.md
│
├── charts/                       # Helm 차트 (모든 환경 공통)
│   ├── airflow/                 # Apache Airflow
│   ├── argo-rollouts/           # Argo Rollouts + Analysis
│   ├── istio/                   # Istio Service Mesh
│   ├── monitoring/              # Prometheus, Grafana, Loki, Tempo
│   ├── kafka-*/                 # Kafka 클러스터
│   ├── services/                # 마이크로서비스
│   │   ├── customer-service/
│   │   ├── order-service/
│   │   ├── payment-service/
│   │   └── ...
│   └── statefulset-base/        # StatefulSet 템플릿
│       ├── redis/
│       └── postgresql/
│
├── config/                       # 환경별 설정 (Values 오버라이드)
│   ├── local/                   # k3d 로컬 환경
│   │   ├── monitoring.yaml
│   │   ├── istio.yaml
│   │   ├── airflow.yaml
│   │   ├── redis.yaml
│   │   └── postgresql.yaml
│   └── prod/                    # EKS 운영 환경
│       ├── monitoring.yaml
│       ├── istio.yaml
│       ├── airflow.yaml
│       ├── redis.yaml
│       └── postgresql.yaml
│
├── argocd/                       # ArgoCD 리소스
│   ├── projects/                # ArgoCD Projects
│   │   ├── infrastructure.yaml
│   │   └── applications.yaml
│   ├── applicationsets/         # ApplicationSets (권장)
│   │   ├── infrastructure.yaml
│   │   ├── stateful-services.yaml
│   │   └── airflow.yaml
│   ├── manifest/                # [레거시] 개별 Application
│   │   └── root-apps.yaml
│   └── bootStrap-root-app.yaml  # [레거시] 루트 앱
│
├── k8s-dev-k3d/                  # k3d 환경 스크립트
│   ├── scripts/
│   │   ├── install-istio.sh
│   │   └── deploy-monitoring.sh
│   ├── kubeconfig/
│   └── values/                  # -> config/local/ 로 이동됨
│
└── k8s-eks/                      # EKS 환경 설정
    └── values/                  # -> config/prod/ 로 이동됨
```

## ArgoCD App of Apps 패턴

### 아키텍처 다이어그램

```
                    ┌─────────────────────────┐
                    │   root-application.yaml │
                    │   (bootstrap/)          │
                    └───────────┬─────────────┘
                                │
              ┌─────────────────┼─────────────────┐
              │                 │                 │
              ▼                 ▼                 ▼
    ┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐
    │    Projects     │ │ ApplicationSets │ │ ApplicationSets │
    │ infrastructure  │ │ infrastructure  │ │ stateful-svc    │
    │  applications   │ │                 │ │                 │
    └─────────────────┘ └────────┬────────┘ └────────┬────────┘
                                 │                   │
         ┌───────────────────────┼───────────────────┤
         │                       │                   │
         ▼                       ▼                   ▼
┌─────────────────┐   ┌─────────────────┐   ┌─────────────────┐
│ monitoring-local│   │ monitoring-prod │   │   redis-local   │
│  istio-local    │   │   istio-prod    │   │   redis-prod    │
│ rollouts-local  │   │  rollouts-prod  │   │   ...           │
└─────────────────┘   └─────────────────┘   └─────────────────┘
```

### ApplicationSet Matrix Generator

환경(local/prod)과 컴포넌트(monitoring/istio/...)를 조합하여 자동으로 Application 생성:

```yaml
generators:
  - matrix:
      generators:
        - list:  # 환경
            elements:
              - env: local
              - env: prod
        - list:  # 컴포넌트
            elements:
              - name: monitoring
              - name: istio
```

결과: `monitoring-local`, `monitoring-prod`, `istio-local`, `istio-prod` Application 자동 생성

## 환경별 설정 관리

### 설정 우선순위

1. `charts/<component>/values.yaml` - 기본값 (환경 중립적)
2. `config/<env>/<component>.yaml` - 환경별 오버라이드

### Local (k3d) 특성
- 리소스 최소화 (CPU/Memory limits 축소)
- `local-path` StorageClass 사용
- 모니터링/알림 비활성화
- 단일 replica

### Prod (EKS) 특성
- 충분한 리소스 할당
- `gp3` StorageClass 사용
- 모니터링/알림 활성화
- 고가용성 (multi-replica)
- Node selector/Tolerations

## 사용 방법

### 1. ArgoCD 부트스트랩

```bash
# ArgoCD 설치 및 부트스트랩
./bootstrap/install-argocd.sh

# ArgoCD UI 접속
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

### 2. 개별 컴포넌트 수동 배포 (Helm)

```bash
# Local 환경
helm upgrade --install monitoring charts/monitoring \
  -f config/local/monitoring.yaml \
  -n monitoring --create-namespace

# Prod 환경
helm upgrade --install monitoring charts/monitoring \
  -f config/prod/monitoring.yaml \
  -n monitoring --create-namespace
```

### 3. 기존 스크립트 사용 (k3d)

```bash
# Istio 설치
./k8s-dev-k3d/scripts/install-istio.sh

# 모니터링 배포
./k8s-dev-k3d/scripts/deploy-monitoring.sh
```

## 마이그레이션 가이드

### 레거시 -> ApplicationSet

1. 기존 `argocd/bootStrap-root-app.yaml` -> `bootstrap/root-application.yaml`
2. 기존 `argocd/manifest/root-apps.yaml` -> `argocd/applicationsets/*.yaml`
3. 기존 `helm/` -> `charts/`
4. 환경별 values: `k8s-dev-k3d/values/` + `k8s-eks/values/` -> `config/local/` + `config/prod/`

### 주의사항

- Git Repository URL을 실제 리포지토리로 변경
- EKS 클러스터 URL을 실제 값으로 변경
- Secrets는 External Secrets 또는 Sealed Secrets 사용 권장
