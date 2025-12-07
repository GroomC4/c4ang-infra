# ArgoCD Configuration

환경별 독립 ApplicationSet 기반 GitOps 배포 구조.

## 디렉토리 구조

```
argocd/
├── README.md
├── projects/                    # ArgoCD AppProject 정의
│   ├── applications.yaml        # MSA 서비스용
│   └── infrastructure.yaml      # 인프라 컴포넌트용
├── applicationsets/
│   ├── dev/                     # k3d 로컬 클러스터용
│   │   ├── infrastructure.yaml
│   │   └── services.yaml
│   └── prod/                    # EKS 클러스터용
│       ├── infrastructure.yaml
│       ├── services.yaml
│       └── airflow.yaml
└── manifests/
    └── namespaces.yaml          # ecommerce, monitoring 네임스페이스
```

## 설치

```bash
# 자동 환경 감지 (k3d → dev, EKS → prod)
./bootstrap/install-argocd.sh
```

또는 수동 적용:

```bash
# 1. ArgoCD 설치
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 2. AppProject 적용
kubectl apply -f argocd/projects/ -n argocd

# 3. Namespace 적용
kubectl apply -f argocd/manifests/namespaces.yaml

# 4. ApplicationSet 적용 (환경별)
# dev 환경 (k3d)
kubectl apply -f argocd/applicationsets/dev/ -n argocd

# prod 환경 (EKS)
kubectl apply -f argocd/applicationsets/prod/ -n argocd
```

## 환경별 구조

### Dev (k3d)
```
applicationsets/dev/
├── infrastructure.yaml  # external-services, monitoring, istio, argo-rollouts
└── services.yaml        # 7개 MSA 서비스
```

### Prod (EKS)
```
applicationsets/prod/
├── infrastructure.yaml  # external-services, monitoring, istio, argo-rollouts
├── services.yaml        # 7개 MSA 서비스
└── airflow.yaml         # 데이터 파이프라인 (prod only)
```

## Sync Wave 순서

| Wave | 컴포넌트 | 설명 |
|------|---------|------|
| 1 | external-services | DB, Redis, Kafka 연결 |
| 2 | monitoring | Prometheus, Grafana, Loki, Tempo |
| 3 | istio | Gateway, VirtualService |
| 4 | argo-rollouts | Rollouts Controller |
| 20 | airflow | 데이터 파이프라인 (prod only) |
| 30 | services | MSA 서비스들 |

## 환경별 설정

각 환경의 values 파일은 `config/{env}/` 폴더에 위치:

```
config/
├── dev/                         # k3d 로컬 환경
│   ├── customer-service.yaml
│   ├── external-services.yaml
│   └── ...
└── prod/                        # EKS 프로덕션
    ├── customer-service.yaml
    ├── external-services.yaml
    └── ...
```

## 검증

```bash
# Application 상태 확인
kubectl get applications -n argocd

# ApplicationSet 상태 확인
kubectl get applicationset -n argocd

# Pod 상태 확인
kubectl get pods -n ecommerce
kubectl get pods -n monitoring
```

## 새 서비스 추가

1. `charts/services/` 에 Helm 차트 생성
2. `config/dev/`, `config/prod/` 에 values 파일 추가
3. ApplicationSet의 서비스 목록에 추가:

```yaml
# argocd/applicationsets/dev/services.yaml
# argocd/applicationsets/prod/services.yaml
generators:
  - list:
      elements:
        - name: customer-service
        - name: order-service
        # ... 기존 서비스
        - name: new-service  # ← 추가
```

## 참고 문서

- [ArgoCD ApplicationSet](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/)
- [구조 리팩토링](../docs/ARGOCD_STRUCTURE_REFACTORING.md)
- [클러스터 관리 전략](../docs/ARGOCD_CLUSTER_MANAGEMENT.md)
- [ApplicationSet vs App of Apps](../docs/APPLICATIONSET_VS_APPOFAPPS.md)
