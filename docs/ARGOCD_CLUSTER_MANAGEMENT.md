# ArgoCD 클러스터 관리 전략

## 개요

이 문서는 ArgoCD를 사용한 멀티 환경(dev/prod) 클러스터 관리 전략을 설명합니다.

---

## Cluster Generator란?

### 기본 개념

ArgoCD는 **여러 K8s 클러스터를 중앙에서 관리**할 수 있습니다. ArgoCD에 클러스터를 등록하면, 등록된 클러스터 목록을 기반으로 Application을 자동 생성할 수 있습니다.

```
ArgoCD (중앙 클러스터에 설치)
├── 등록된 클러스터 목록
│   ├── "in-cluster" (자기 자신) - 자동 등록됨
│   ├── "k3d-dev" (로컬 k3d) - 수동 등록 필요
│   └── "eks-prod" (EKS) - 수동 등록 필요
│
└── Cluster Generator ApplicationSet
    → 등록된 클러스터마다 Application 자동 생성
```

### 동작 방식

```yaml
# ApplicationSet with Cluster Generator
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
spec:
  generators:
    - clusters:
        selector:
          matchLabels:
            env: prod  # env=prod 라벨이 있는 클러스터만 선택
  template:
    spec:
      destination:
        server: '{{.server}}'  # 자동으로 클러스터 URL 주입
```

**흐름:**
1. ArgoCD에 클러스터 등록 시 라벨 부여 (`env=dev`, `env=prod`)
2. Cluster Generator가 라벨 조건에 맞는 클러스터 찾음
3. 각 클러스터마다 Application 자동 생성

### 클러스터 등록이란?

ArgoCD가 다른 클러스터에 접근하려면 **인증 정보**가 필요합니다.

```bash
# k3d 클러스터를 ArgoCD에 등록
argocd cluster add k3d-msa-cluster --name k3d-dev --label env=dev

# 내부적으로 이런 일이 발생:
# 1. k3d 클러스터의 kubeconfig에서 인증 정보 추출
# 2. ArgoCD에 Secret으로 저장
# 3. 이제 ArgoCD가 k3d 클러스터에 배포 가능
```

---

## 클러스터 관리 패턴 비교

### Pattern 1: 중앙 집중형 (Cluster Generator)

```
┌─────────────────────────────────────────────────────────┐
│                    중앙 ArgoCD                           │
│                  (관리용 클러스터)                        │
│                         │                               │
│         ┌───────────────┼───────────────┐               │
│         ▼               ▼               ▼               │
│   ┌──────────┐   ┌──────────┐   ┌──────────┐           │
│   │ EKS-Dev  │   │EKS-Staging│  │ EKS-Prod │           │
│   └──────────┘   └──────────┘   └──────────┘           │
└─────────────────────────────────────────────────────────┘
```

**장점:**
- 단일 ArgoCD로 모든 환경 관리
- 통합 대시보드
- ApplicationSet 하나로 모든 클러스터에 배포

**단점:**
- 모든 클러스터가 네트워크로 연결되어야 함
- 중앙 ArgoCD 장애 시 전체 배포 중단
- 보안: 중앙에서 모든 클러스터 인증 정보 보유

**적합한 경우:**
- 여러 EKS 클러스터 관리 (dev-eks, staging-eks, prod-eks)
- 모든 클러스터가 VPC 피어링 등으로 연결된 경우

### Pattern 2: 독립 분산형 (클러스터별 ArgoCD)

```
┌─────────────────────────────────────────────────────────┐
│                                                         │
│   ┌──────────────┐              ┌──────────────┐       │
│   │   k3d-dev    │              │   EKS-prod   │       │
│   │  ┌────────┐  │              │  ┌────────┐  │       │
│   │  │ ArgoCD │  │              │  │ ArgoCD │  │       │
│   │  └────────┘  │              │  └────────┘  │       │
│   │      ↓       │              │      ↓       │       │
│   │  dev 환경    │              │  prod 환경   │       │
│   └──────────────┘              └──────────────┘       │
│                                                         │
│         (네트워크 분리 - 서로 독립적)                     │
└─────────────────────────────────────────────────────────┘
```

**장점:**
- 환경 간 완전한 격리
- 한 환경 장애가 다른 환경에 영향 없음
- 로컬(k3d)과 클라우드(EKS) 혼합 가능
- 보안: 각 클러스터가 자신의 인증만 보유

**단점:**
- ArgoCD 여러 개 관리
- 통합 대시보드 없음

**적합한 경우:**
- 로컬 개발 환경(k3d) + 클라우드 프로덕션(EKS)
- 환경 간 네트워크 분리 필요
- 높은 격리 수준 요구

---

## 현재 프로젝트 상황

```
┌─────────────────────────────────────────────────────────┐
│                                                         │
│  로컬 PC                        AWS Cloud               │
│  ┌──────────┐                  ┌──────────┐            │
│  │   k3d    │  ← 인터넷 →      │   EKS    │            │
│  │  (dev)   │    접근 불가      │  (prod)  │            │
│  └──────────┘                  └──────────┘            │
│                                                         │
│  EKS의 ArgoCD가 로컬 k3d에 접근하려면?                    │
│  → 로컬 PC가 인터넷에 공개되어야 함                       │
│  → 보안상 불가능 ❌                                      │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

**결론: 독립 분산형 패턴 사용**

각 클러스터에 ArgoCD를 독립 설치하고, 해당 환경의 설정만 적용합니다.

---

## 구현 전략

### 환경별 ApplicationSet 분리

```
argocd/applicationsets/
├── dev/                    # k3d 클러스터용
│   ├── infrastructure.yaml
│   └── services.yaml
└── prod/                   # EKS 클러스터용
    ├── infrastructure.yaml
    ├── services.yaml
    └── airflow.yaml
```

### 설치 방법

```bash
# k3d (dev 환경)
kubectl apply -f argocd/applicationsets/dev/

# EKS (prod 환경)
kubectl apply -f argocd/applicationsets/prod/
```

---

## 참고: Cluster Generator 사용 시나리오

향후 다음과 같은 구성이 필요하면 Cluster Generator 도입 검토:

```
AWS VPC
├── EKS-dev (개발)
├── EKS-staging (스테이징)
├── EKS-prod (프로덕션)
└── EKS-management (ArgoCD 중앙 관리)
    └── Cluster Generator로 위 3개 클러스터 자동 관리
```
