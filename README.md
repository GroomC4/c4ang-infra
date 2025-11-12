# C4ang Infrastructure Configuration

MSA 전환을 위한 Kubernetes 인프라 및 배포 설정 저장소입니다.

## 📋 개요

이 저장소는 다음을 관리합니다:

- **Helm 차트**: ArgoCD를 통해 Kubernetes 클러스터에 배포되는 모든 인프라 및 애플리케이션 리소스
- **로컬 개발 환경**: k3d 기반 로컬 Kubernetes 환경 구성
- **(레거시) Docker Compose**: 기존 Docker 기반 개발 환경 (유지보수)

## 📁 디렉토리 구조

```
c4ang-infra/
├── helm/                                   # Helm 차트 (ArgoCD 연동 대상)
│   ├── statefulset-base/                   # 공통 인프라
│   │   ├── postgresql/                     # PostgreSQL (Primary-Replica)
│   │   └── redis/                          # Redis Statefulset
│   ├── management-base/                    # 관리 도구
│   │   └── airflow/                        # Apache Airflow
│   ├── services/                           # MSA 서비스 리소스
│   │   └── customer-service/               # Customer Service (예시)
│   ├── test-infrastructure/                # 테스트용 통합 인프라
│   ├── build-dependencies.sh               # Helm dependencies 빌드 스크립트
│   └── README.md                           # Helm 차트 상세 가이드
└── k8s-dev-k3d/                            # 로컬 k3d 개발 환경
    ├── install-k3s.sh                      # k3d 클러스터 설치 및 부트스트랩
    ├── scripts/
    │   ├── start-environment.sh            # 로컬 환경 시작
    │   ├── stop-environment.sh             # 로컬 환경 중지
    │   └── cleanup.sh                      # k3d 리소스 정리
    ├── values/                             # 로컬 환경용 Helm values
    │   ├── postgresql.yaml
    │   ├── redis.yaml
    │   └── airflow.yaml
    └── README.md                           # k3d 환경 상세 가이드

```

## 🎯 주요 구성 요소

### 1. Helm 차트 (`helm/`)

ArgoCD를 통해 Kubernetes 클러스터에 배포되는 리소스를 관리합니다.

#### `statefulset-base/`
공통 인프라 컴포넌트:
- **postgresql**: Primary-Replica 구성의 PostgreSQL 클러스터
- **redis**: Redis Statefulset

#### `management-base/`
관리 도구:
- **airflow**: Apache Airflow (데이터 파이프라인 관리)

#### `services/`
**실제 MSA 애플리케이션 서비스들의 Kubernetes 리소스를 관리합니다.**
- **customer-service**: Customer 도메인 서비스 (예시)
- *(추가 서비스들이 이 디렉토리에 추가됩니다)*

각 서비스는 Deployment, Service, Ingress, ConfigMap, HPA 등 필요한 K8s 리소스를 포함합니다.

#### `test-infrastructure/`
테스트 환경용 경량화된 인프라 (PostgreSQL + Redis)

### 2. 로컬 개발 환경 (`k8s-dev-k3d/`)

k3d를 사용한 로컬 Kubernetes 환경:
- 개발자 로컬 머신에서 Kubernetes 환경 구축
- Helm 차트를 로컬에서 테스트
- 자동화된 설치 및 관리 스크립트 제공

## 🚀 사용 방법

### Option 1: ArgoCD를 통한 배포 (프로덕션/스테이징)

ArgoCD에서 이 저장소의 `helm/` 디렉토리를 연동하여 자동으로 배포합니다.

#### ArgoCD Application 예시

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: customer-service
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/GroomC4/c4ang-infra.git
    targetRevision: main
    path: helm/services/customer-service
    helm:
      valueFiles:
        - values.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: msa-quality
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

#### 인프라 컴포넌트 배포

```yaml
# PostgreSQL
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: postgresql
spec:
  source:
    path: helm/statefulset-base/postgresql
  # ...

# Redis
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: redis
spec:
  source:
    path: helm/statefulset-base/redis
  # ...
```

### Option 2: 로컬 k3d 환경 (개발)

로컬에서 전체 Kubernetes 환경을 실행합니다.

#### 빠른 시작

```bash
# 1. k3d 클러스터 생성
cd k8s-dev-k3d
./install-k3s.sh

# 2. 로컬 환경 시작 (PostgreSQL, Redis 자동 배포)
cd scripts
./start-environment.sh

# 3. kubeconfig 설정
export KUBECONFIG=$(pwd)/../kubeconfig/config

# 4. 배포 확인
kubectl get pods -n msa-quality
```

자세한 내용은 [k8s-dev-k3d/README.md](./k8s-dev-k3d/README.md)를 참고하세요.

### Option 3: Helm 수동 배포

특정 차트만 수동으로 배포할 수 있습니다.

```bash
# Dependencies 빌드 (최초 1회)
cd helm
./build-dependencies.sh

# PostgreSQL 배포
helm install postgresql ./statefulset-base/postgresql \
  --namespace msa-quality \
  --create-namespace \
  --wait

# Redis 배포
helm install redis ./statefulset-base/redis \
  --namespace msa-quality \
  --wait

# Customer Service 배포
helm install customer-service ./services/customer-service \
  --namespace msa-quality \
  --wait
```

자세한 내용은 [helm/README.md](./helm/README.md)를 참고하세요.

```

## 🔄 워크플로우

### 새 서비스 추가

1. `helm/services/` 아래에 새 서비스 차트 생성
2. Deployment, Service, ConfigMap 등 K8s 리소스 정의
3. values.yaml로 환경별 설정 관리
4. ArgoCD에 Application 등록하여 자동 배포

### 인프라 변경

1. `helm/statefulset-base/` 또는 `helm/management-base/` 수정
2. 로컬 k3d 환경에서 테스트
3. main 브랜치에 머지
4. ArgoCD가 자동으로 변경사항 감지 및 배포

### 로컬 개발

1. k3d 환경 시작: `k8s-dev-k3d/scripts/start-environment.sh`
2. 애플리케이션 개발 및 테스트
3. Helm 차트 수정 시 로컬에서 먼저 검증
4. 환경 정리: `k8s-dev-k3d/scripts/stop-environment.sh`

## 📦 서비스별 구조 예시

### MSA 서비스 레포지토리 구조

```
customer-service/
├── src/                        # 애플리케이션 코드
├── build.gradle.kts
├── Dockerfile
└── (Helm 차트는 c4ang-infra/helm/services/customer-service/에 위치)
```

### Helm 차트 구조

```
helm/services/customer-service/
├── Chart.yaml
├── values.yaml
├── templates/
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── ingress.yaml
│   ├── configmap.yaml
│   └── hpa.yaml
└── README.md
```

## 🔧 환경별 설정

| 환경 | 배포 방식 | Values 관리 |
|------|-----------|------------|
| **로컬 (k3d)** | `k8s-dev-k3d/scripts/start-environment.sh` | `k8s-dev-k3d/values/*.yaml` |
| **개발 (Dev)** | ArgoCD | ArgoCD Application에서 values 오버라이드 |
| **스테이징 (Staging)** | ArgoCD | ArgoCD Application에서 values 오버라이드 |
| **프로덕션 (Prod)** | ArgoCD | ArgoCD Application에서 values 오버라이드 |

## 📝 참고 문서

### 내부 문서
- [Helm 차트 가이드](./helm/README.md)
- [k3d 로컬 환경 가이드](./k8s-dev-k3d/README.md)

### 외부 문서
- [ArgoCD 공식 문서](https://argo-cd.readthedocs.io/)
- [Helm 공식 문서](https://helm.sh/docs/)
- [k3d 공식 문서](https://k3d.io/)
- [Kubernetes 공식 문서](https://kubernetes.io/docs/)
- [Bitnami Charts](https://github.com/bitnami/charts)

## 🎯 로드맵

- [x] Helm Charts 구조 설계 및 구현
- [x] k3d 로컬 환경 자동화
- [x] PostgreSQL, Redis 베이스 차트
- [x] Airflow 관리 베이스 차트
- [ ] ArgoCD 연동 가이드 문서화
- [ ] 서비스 차트 템플릿 표준화
- [ ] Monitoring Stack (Prometheus, Grafana)
- [ ] Kafka, RabbitMQ 등 추가 인프라
- [ ] CI/CD 파이프라인 통합

## 🤝 기여

인프라 변경 시:
1. 로컬 k3d 환경에서 먼저 테스트
2. PR 생성 및 리뷰
3. main 브랜치 머지 후 ArgoCD가 자동 배포

## 📞 문의
- 인프라 관련 문의: @sunhozy @tkddk0108
- ArgoCD 관련 문의: @eunjulee0603
