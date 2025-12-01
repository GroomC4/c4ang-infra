# Scripts

인프라 및 플랫폼 관리를 위한 스크립트 모음입니다.

## 빠른 시작

```bash
# k3d 개발 환경 전체 구축 (권장)
./scripts/bootstrap/dev.sh

# AWS 프로덕션 환경 전체 구축
./scripts/bootstrap/prod.sh
```

## 디렉토리 구조

```
scripts/
├── bootstrap/            # 🚀 환경 부트스트랩 (진입점)
│   ├── dev.sh            # k3d 개발 환경 (Docker + k3d + ECR + ArgoCD)
│   ├── prod.sh           # AWS 프로덕션 환경 (Terraform + EKS + ArgoCD)
│   └── README.md
│
└── platform/             # ⚙️ 플랫폼 컴포넌트 관리
    ├── argocd.sh         # ArgoCD 설치/관리
    ├── istio.sh          # Istio 설치/관리
    ├── kafka.sh          # Kafka (Strimzi) 설치/관리
    ├── monitoring.sh     # Prometheus/Grafana 설치/관리
    ├── secrets.sh        # SOPS/Age 시크릿 관리
    └── ecr.sh            # ECR Secret 관리 (k3d 개발용)
```

## 스크립트 카테고리

### 1. 부트스트랩 스크립트 (`bootstrap/`)

전체 환경을 한 번에 구축하는 부트스트랩 스크립트입니다. **대부분의 경우 이 스크립트만 사용하면 됩니다.**

| 스크립트 | 대상 | 설명 |
|---------|-----|------|
| `bootstrap/dev.sh` | 서비스 개발자 | Docker Compose + k3d + ECR Secret + ArgoCD 전체 플로우 |
| `bootstrap/prod.sh` | 인프라 담당자 | Terraform + EKS + ArgoCD 전체 플로우 |

```bash
# 개발 환경
./scripts/bootstrap/dev.sh              # 전체 초기화
./scripts/bootstrap/dev.sh --up         # 시작
./scripts/bootstrap/dev.sh --down       # 중지
./scripts/bootstrap/dev.sh --status     # 상태 확인
./scripts/bootstrap/dev.sh --destroy    # 삭제

# 프로덕션 환경
./scripts/bootstrap/prod.sh               # 전체 초기화
./scripts/bootstrap/prod.sh --plan        # Terraform plan
./scripts/bootstrap/prod.sh --apply       # Terraform apply
./scripts/bootstrap/prod.sh --status      # 상태 확인
```

### 2. 플랫폼 스크립트 (`platform/`)

개별 플랫폼 컴포넌트 설치 및 관리 스크립트입니다. ArgoCD가 관리하지 않는 초기 설정이나 수동 작업이 필요할 때 사용합니다.

| 스크립트 | 설명 | 주요 옵션 |
|---------|------|----------|
| `argocd.sh` | ArgoCD 설치 및 App of Apps 부트스트랩 | `--status`, `--password`, `--uninstall` |
| `istio.sh` | Istio 서비스 메시 설치 | `--status`, `--uninstall` |
| `kafka.sh` | Strimzi Kafka 설치 | `--status`, `--uninstall` |
| `monitoring.sh` | Prometheus, Grafana 설치 | `--status`, `--uninstall` |
| `secrets.sh` | SOPS/Age 시크릿 관리 초기화 | `--encrypt`, `--decrypt`, `--status` |
| `ecr.sh` | AWS ECR Secret 관리 (k3d 개발용) | `--status`, `--delete` |

```bash
# 각 스크립트 도움말
./scripts/platform/argocd.sh --help
./scripts/platform/istio.sh --help
./scripts/platform/kafka.sh --help
./scripts/platform/monitoring.sh --help
./scripts/platform/secrets.sh --help
./scripts/platform/ecr.sh --help
```

## 전체 플로우

```
┌──────────────────────────────────────────────────────────────────────┐
│                     Environment Setup Flow                            │
├──────────────────────────────────────────────────────────────────────┤
│                                                                       │
│  Phase 1: External Services                                          │
│  ──────────────────────────────────────────────────────────────────  │
│  Local: docker-compose up      │  Prod: terraform apply              │
│  - PostgreSQL (5 DBs)          │  - RDS PostgreSQL (5 DBs)           │
│  - Redis (2 instances)         │  - ElastiCache Redis (2)            │
│  - Kafka (KRaft mode)          │  - MSK (optional)                   │
│                                                                       │
│  Phase 2: Kubernetes Cluster                                          │
│  ──────────────────────────────────────────────────────────────────  │
│  Local: k3d cluster create     │  Prod: aws eks update-kubeconfig    │
│                                                                       │
│  Phase 3: ECR Secret (로컬 환경)                                       │
│  ──────────────────────────────────────────────────────────────────  │
│  - AWS 자격증명으로 ECR 토큰 발급                                       │
│  - docker-registry Secret 생성 (12시간 유효)                           │
│                                                                       │
│  Phase 4: ArgoCD Bootstrap                                            │
│  ──────────────────────────────────────────────────────────────────  │
│  - ArgoCD 설치                                                        │
│  - AppProjects 생성                                                   │
│  - Root Application 배포 (App of Apps 패턴)                           │
│  - ApplicationSets 자동 동기화                                         │
│      → external-services (ExternalName Services)                     │
│      → monitoring (Prometheus, Grafana)                              │
│      → istio (Service Mesh)                                          │
│      → argo-rollouts                                                 │
│      → MSA applications                                              │
│                                                                       │
└──────────────────────────────────────────────────────────────────────┘
```

## 대상별 사용 가이드

### 서비스 개발자

```bash
# 사전 요구사항
# - Docker Desktop 실행
# - AWS CLI 설치 및 자격증명 설정: aws configure

# 1. 개발 환경 구축 (한 번만 실행)
./scripts/bootstrap/dev.sh

# 2. 개발 작업...

# 3. 환경 중지 (퇴근시)
./scripts/bootstrap/dev.sh --down

# 4. 다음날 환경 시작
./scripts/bootstrap/dev.sh --up

# 5. ECR Secret 만료 시 갱신 (12시간 이상 작업 시)
./scripts/platform/ecr.sh
```

### 인프라 담당자

```bash
# 1. 프로덕션 인프라 구축
./scripts/bootstrap/prod.sh

# 2. 개별 컴포넌트 관리
./scripts/platform/monitoring.sh --status
./scripts/platform/argocd.sh --status

# 3. 시크릿 관리
./scripts/platform/secrets.sh --encrypt config/prod/secrets.yaml
```

## 환경 변수

| 변수 | 기본값 | 설명 |
|-----|-------|------|
| `CLUSTER_NAME` | `msa-quality-cluster` | k3d 클러스터 이름 |
| `AWS_REGION` | `ap-northeast-2` | AWS 리전 |
| `EKS_CLUSTER_NAME` | `c4ang-prod-eks` | EKS 클러스터 이름 |
| `ARGOCD_VERSION` | `v2.10.0` | ArgoCD 버전 |

## 트러블슈팅

### 포트 충돌

```bash
# 사용 중인 포트 확인
lsof -i :80 -i :443 -i :6443

# 환경 완전 삭제 후 재시작
./scripts/bootstrap/dev.sh --destroy
./scripts/bootstrap/dev.sh
```

### 클러스터 연결 불가

```bash
# kubeconfig 확인
export KUBECONFIG=$(pwd)/k8s-dev-k3d/kubeconfig/config
kubectl cluster-info

# 클러스터 상태 확인
k3d cluster list
```

### ECR 이미지 Pull 실패

```bash
# ECR Secret 상태 확인
./scripts/platform/ecr.sh --status

# Secret 갱신
./scripts/platform/ecr.sh
```

### ArgoCD 비밀번호

```bash
./scripts/platform/argocd.sh --password
```
