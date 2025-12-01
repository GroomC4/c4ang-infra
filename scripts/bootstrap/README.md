# 환경 부트스트랩 스크립트

환경별로 전체 플로우를 자동화하는 부트스트랩 스크립트입니다.
도메인 서비스 개발자가 인프라 상세 내용을 몰라도 스크립트 하나로 개발 환경을 구축할 수 있습니다.

## 전체 플로우

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        Environment Bootstrap Flow                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  Phase 1: External Services                                                  │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │  Local: Docker Compose        │    Prod: Terraform (AWS)            │    │
│  │  - PostgreSQL (5)             │    - RDS PostgreSQL (5)             │    │
│  │  - Redis (2)                  │    - ElastiCache Redis (2)          │    │
│  │  - Kafka (KRaft)              │    - MSK Kafka (optional)           │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                     ↓                                        │
│  Phase 2: Kubernetes Cluster                                                 │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │  Local: k3d                   │    Prod: EKS                        │    │
│  │  - msa-quality-cluster        │    - c4ang-prod-eks                 │    │
│  │  - Traefik disabled           │    - Managed node groups            │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                     ↓                                        │
│  Phase 3: ECR Secret 설정 (로컬 환경)                                       │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │  - AWS 자격증명으로 ECR 토큰 발급                                     │    │
│  │  - docker-registry Secret 생성 (12시간 유효)                          │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                     ↓                                        │
│  Phase 4: ArgoCD Bootstrap (App of Apps)                                    │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │  - ArgoCD 설치                                                       │    │
│  │  - Projects 생성                                                     │    │
│  │  - Root Application 배포 → ApplicationSets 자동 생성                  │    │
│  │  - 환경별 자동 동기화 (external-services → monitoring → istio → ...)  │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 스크립트 목록

| 스크립트 | 환경 | 설명 |
|---------|------|------|
| `local.sh` | 로컬 개발 | Docker Compose + k3d + ECR Secret + ArgoCD |
| `prod.sh` | AWS 프로덕션 | Terraform + EKS + ArgoCD |

## 사용법

### 로컬 개발 환경

```bash
# 최초 환경 구축 (전체 플로우 실행)
./scripts/bootstrap/local.sh

# 환경 시작 (이미 초기화된 경우)
./scripts/bootstrap/local.sh --up

# 환경 중지 (데이터 유지)
./scripts/bootstrap/local.sh --down

# 상태 확인
./scripts/bootstrap/local.sh --status

# 환경 완전 삭제 (데이터 포함)
./scripts/bootstrap/local.sh --destroy
```

**사전 요구사항:**
- Docker Desktop 실행
- AWS CLI 설치 및 자격증명 설정 (`aws configure` 또는 `aws sso login`)

### AWS 프로덕션 환경

```bash
# 사전 요구사항
# 1. AWS CLI 설정: aws configure
# 2. c4ang-terraform으로 VPC, EKS 생성 완료
# 3. external-services/aws/terraform.tfvars 설정

# 전체 환경 구축
./scripts/bootstrap/prod.sh

# Terraform plan만 실행
./scripts/bootstrap/prod.sh --plan

# Terraform apply만 실행
./scripts/bootstrap/prod.sh --apply

# EKS 연결만 설정
./scripts/bootstrap/prod.sh --connect

# ArgoCD bootstrap만 실행
./scripts/bootstrap/prod.sh --bootstrap

# 상태 확인
./scripts/bootstrap/prod.sh --status

# 환경 삭제 (주의!)
./scripts/bootstrap/prod.sh --destroy
```

## 디렉토리 구조

```
scripts/
├── bootstrap/            # 환경 부트스트랩 (이 디렉토리)
│   ├── local.sh          # 로컬 개발 환경 (도메인 개발자용)
│   ├── prod.sh           # AWS 프로덕션 환경
│   └── README.md
│
└── platform/             # 플랫폼 컴포넌트 관리 (인프라 담당자용)
    ├── argocd.sh         # ArgoCD 설치/관리
    ├── istio.sh          # Istio 설치/관리
    ├── kafka.sh          # Kafka (Strimzi) 설치/관리
    ├── monitoring.sh     # Prometheus/Grafana 설치/관리
    ├── secrets.sh        # SOPS/Age 시크릿 관리
    └── ecr.sh            # ECR Secret 관리 (로컬 k3d용)
```

## 외부 서비스 접근

ArgoCD가 배포하는 ExternalName Service를 통해 외부 데이터 서비스에 접근합니다:

| 서비스 | K8s Service 이름 | 로컬 포트 | AWS 엔드포인트 |
|-------|-----------------|----------|---------------|
| Customer DB | `customer-db` | 5432 | RDS endpoint |
| Product DB | `product-db` | 5433 | RDS endpoint |
| Order DB | `order-db` | 5434 | RDS endpoint |
| Store DB | `store-db` | 5435 | RDS endpoint |
| Saga DB | `saga-db` | 5436 | RDS endpoint |
| Cache Redis | `cache-redis` | 6379 | ElastiCache |
| Session Redis | `session-redis` | 6380 | ElastiCache |
| Kafka | `kafka` | 9092 | K8s/MSK |

## 환경 변수

### 로컬 환경 (local.sh)

| 변수 | 기본값 | 설명 |
|------|-------|------|
| `CLUSTER_NAME` | `msa-quality-cluster` | k3d 클러스터 이름 |

### 프로덕션 환경 (prod.sh)

| 변수 | 기본값 | 설명 |
|------|-------|------|
| `AWS_REGION` | `ap-northeast-2` | AWS 리전 |
| `EKS_CLUSTER_NAME` | `c4ang-prod-eks` | EKS 클러스터 이름 |

## 트러블슈팅

### 로컬 환경

```bash
# Docker 서비스 상태 확인
cd external-services/local && docker-compose ps

# k3d 클러스터 상태 확인
k3d cluster list

# kubeconfig 수동 설정
export KUBECONFIG=$(pwd)/k8s-dev-k3d/kubeconfig/config

# 포트 충돌 확인
lsof -i :80 -i :443 -i :6443
```

### AWS 환경

```bash
# AWS 자격 증명 확인
aws sts get-caller-identity

# EKS 클러스터 상태 확인
aws eks describe-cluster --name c4ang-prod-eks --region ap-northeast-2

# kubeconfig 수동 업데이트
aws eks update-kubeconfig --name c4ang-prod-eks --region ap-northeast-2

# Terraform 상태 확인
cd external-services/aws && terraform state list
```
