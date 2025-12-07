# ArgoCD Configuration

ApplicationSet 기반 GitOps 배포 구조.

## 디렉토리 구조

```
argocd/
├── README.md
├── projects/                    # ArgoCD AppProject 정의
│   ├── applications.yaml        # MSA 서비스용
│   └── infrastructure.yaml      # 인프라 컴포넌트용
├── applicationsets/             # ApplicationSet 정의
│   ├── infrastructure.yaml      # monitoring, istio, argo-rollouts, external-services
│   ├── services.yaml            # customer, order, payment, product, store, etc.
│   └── airflow.yaml             # Airflow (prod only)
└── manifests/                   # 수동 적용 매니페스트
    └── namespaces.yaml          # ecommerce, monitoring 네임스페이스
```

## 설치

```bash
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

# 4. ApplicationSet 적용
kubectl apply -f argocd/applicationsets/ -n argocd
```

## Sync Wave 순서

| Wave | 컴포넌트 | 설명 |
|------|---------|------|
| 1 | external-services | DB, Redis, Kafka 연결 |
| 2 | monitoring | Prometheus, Grafana, Loki, Tempo |
| 3 | istio | Gateway, VirtualService |
| 4 | argo-rollouts | Rollouts Controller |
| 30 | services | MSA 서비스들 |

## 환경별 설정

ApplicationSet은 `config/{env}/` 폴더의 values 파일을 참조:

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

## 참고

- [ArgoCD ApplicationSet](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/)
- [구조 리팩토링 문서](../docs/ARGOCD_STRUCTURE_REFACTORING.md)
