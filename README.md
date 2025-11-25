# C4ang Infrastructure

MSA 기반 E-commerce 플랫폼을 위한 Kubernetes 인프라 구성 리포지토리입니다.

## 프로젝트 구조

```
c4ang-infra/
├── scripts/                       # 사용자 유형별 스크립트
│   ├── dev/                      # 서비스 개발자용 스크립트
│   │   ├── create-cluster.sh    # k3d 클러스터 생성
│   │   ├── start-environment.sh # 환경 시작
│   │   ├── stop-environment.sh  # 환경 중지
│   │   └── cleanup.sh           # 환경 정리
│   └── infra/                    # 인프라 담당자용 스크립트
│       ├── install-argocd.sh    # ArgoCD 설치
│       ├── install-istio.sh     # Istio 설치
│       ├── uninstall-istio.sh   # Istio 제거
│       ├── deploy-monitoring.sh # 모니터링 스택 배포
│       └── setup-sops-age.sh    # SOPS/Age 시크릿 설정
│
├── charts/                        # Helm 차트 (환경 중립적)
│   ├── airflow/                  # Apache Airflow
│   ├── argo-rollouts/            # Argo Rollouts + Analysis
│   ├── istio/                    # Istio Service Mesh 설정
│   ├── monitoring/               # Prometheus, Grafana, Loki, Tempo
│   ├── kafka-*/                  # Kafka 관련 차트
│   ├── services/                 # 마이크로서비스 차트
│   └── statefulset-base/         # StatefulSet 템플릿 (Redis, PostgreSQL)
│
├── config/                        # 환경별 Values 오버라이드
│   ├── local/                    # 로컬 k3d 환경 설정
│   └── prod/                     # 운영 환경 설정 (EKS)
│
├── environments/                  # 환경별 리소스
│   ├── local/                    # k3d 로컬 환경
│   │   ├── kubeconfig/          # kubeconfig 저장
│   │   └── docs/                # 환경별 문서
│   └── prod/                     # 운영 환경
│       └── secrets/             # External Secrets 설정
│
├── argocd/                        # ArgoCD 리소스
│   ├── projects/                 # ArgoCD Projects 정의
│   └── applicationsets/          # ApplicationSet (Matrix Generator)
│
├── bootstrap/                     # ArgoCD App of Apps 부트스트랩
├── docs/                          # 프로젝트 문서
├── performance-tests/             # k6 성능 테스트
└── Makefile                       # 개발자 편의 명령어
```

## 사용자 가이드

### 서비스 개발자 (로컬 테스트 환경)

로컬에서 마이크로서비스를 개발하고 테스트하기 위한 k3d 환경을 구성합니다.

```bash
# 1. k3d 클러스터 생성
./scripts/dev/create-cluster.sh

# 2. kubectl 설정
export KUBECONFIG=$(pwd)/environments/local/kubeconfig/config

# 3. 환경 시작 (Redis, PostgreSQL 등 기본 서비스 배포)
./scripts/dev/start-environment.sh

# 4. 환경 상태 확인
kubectl get pods -A

# 5. 환경 중지 (클러스터 유지)
./scripts/dev/stop-environment.sh

# 6. 환경 완전 삭제
./scripts/dev/cleanup.sh
```

| 스크립트 | 설명 |
|---------|------|
| `create-cluster.sh` | k3d 클러스터 생성 및 기본 설정 |
| `start-environment.sh` | 클러스터 시작 및 기본 서비스 배포 |
| `stop-environment.sh` | Helm 릴리스 제거 및 클러스터 중지/삭제 선택 |
| `cleanup.sh` | 모든 k3d 리소스 완전 삭제 |

### 인프라 담당자 (인프라 관리)

인프라 컴포넌트를 설치하고 관리합니다.

```bash
# ArgoCD 설치 (GitOps)
./scripts/infra/install-argocd.sh

# Istio Service Mesh 설치
./scripts/infra/install-istio.sh

# 모니터링 스택 배포 (Prometheus, Grafana, Loki, Tempo)
./scripts/infra/deploy-monitoring.sh

# SOPS/Age 시크릿 관리 설정
./scripts/infra/setup-sops-age.sh
```

| 스크립트 | 설명 |
|---------|------|
| `install-argocd.sh` | ArgoCD 설치 및 App of Apps 부트스트랩 |
| `install-istio.sh` | Istio Control Plane 및 설정 배포 |
| `uninstall-istio.sh` | Istio 제거 |
| `deploy-monitoring.sh` | 모니터링 스택 배포 |
| `setup-sops-age.sh` | Age 키 생성 및 SOPS 설정 |

## 환경별 Helm 배포

### 로컬 환경 (k3d)

```bash
# 모니터링 스택
helm upgrade --install monitoring charts/monitoring \
  -f config/local/monitoring.yaml \
  -n monitoring --create-namespace

# Istio 설정
helm upgrade --install istio-config charts/istio \
  -f config/local/istio.yaml \
  -n ecommerce --create-namespace

# Redis
helm upgrade --install redis charts/statefulset-base/redis \
  -f config/local/redis.yaml \
  -n msa-quality --create-namespace
```

### 운영 환경 (EKS)

```bash
# 모니터링 스택
helm upgrade --install monitoring charts/monitoring \
  -f config/prod/monitoring.yaml \
  -n monitoring --create-namespace

# Istio 설정
helm upgrade --install istio-config charts/istio \
  -f config/prod/istio.yaml \
  -n ecommerce --create-namespace

# External Secrets 설정
kubectl apply -f environments/prod/secrets/
```

## 주요 기능

### GitOps (ArgoCD ApplicationSet)

Matrix Generator를 사용하여 환경(local/prod)과 컴포넌트를 조합:

```yaml
# argocd/applicationsets/infrastructure.yaml
generators:
  - matrix:
      generators:
        - list:
            elements:
              - env: local
              - env: prod
        - list:
            elements:
              - name: monitoring
              - name: istio
```

결과: `monitoring-local`, `monitoring-prod`, `istio-local`, `istio-prod` 자동 생성

### 환경별 설정 분리

- **charts/**: 환경 중립적인 Helm 차트 (기본값)
- **config/local/**: k3d 최적화 설정 (리소스 최소화, 단일 replica)
- **config/prod/**: EKS 운영 설정 (HA, 모니터링, 알림 활성화)

### 시크릿 관리

| 환경 | 방식 | 경로 |
|-----|------|-----|
| 로컬 (k3d) | SOPS + Age | `config/local/*.secrets.enc.yaml` |
| 운영 (EKS) | AWS Secrets Manager + External Secrets | `environments/prod/secrets/` |

## Makefile 명령어

```bash
make help                 # 모든 명령어 보기

# 로컬 환경
make local-up             # 환경 시작
make local-down           # 환경 중지
make local-status         # 상태 확인
make local-clean          # 환경 삭제

# ArgoCD
make argocd-install       # ArgoCD 설치
make argocd-status        # 상태 확인

# Istio
make istio-install        # Istio 설치
make istio-status         # 상태 확인

# 모니터링
make deploy-monitoring    # 모니터링 스택 배포

# 유틸리티
make kubectl-config       # kubeconfig 정보
make version              # 도구 버전 확인
```

## 디렉토리 설명

| 디렉토리 | 설명 |
|---------|------|
| `scripts/dev/` | 서비스 개발자용 스크립트 (로컬 환경 관리) |
| `scripts/infra/` | 인프라 담당자용 스크립트 (인프라 컴포넌트 관리) |
| `charts/` | 환경 중립적 Helm 차트 |
| `config/local/` | k3d 환경 Values 오버라이드 |
| `config/prod/` | EKS 환경 Values 오버라이드 |
| `environments/local/` | k3d 환경 리소스 (kubeconfig 등) |
| `environments/prod/` | 운영 환경 리소스 (External Secrets 등) |
| `argocd/` | ArgoCD Projects 및 ApplicationSets |
| `bootstrap/` | ArgoCD App of Apps 부트스트랩 |

## 참고 문서

- [ARCHITECTURE.md](./ARCHITECTURE.md) - 상세 아키텍처 설명
- [environments/local/docs/](./environments/local/docs/) - k3d 로컬 환경 가이드
- [bootstrap/README.md](./bootstrap/README.md) - ArgoCD 부트스트랩 가이드
- [docs/](./docs/) - 추가 문서
