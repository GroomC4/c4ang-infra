# Bootstrap - ArgoCD App of Apps Pattern

이 디렉토리는 ArgoCD를 설치하고 App of Apps 패턴으로 인프라를 부트스트랩하는 스크립트를 포함합니다.

## 구조

```
bootstrap/
├── install-argocd.sh      # ArgoCD 설치 및 부트스트랩 스크립트
├── root-application.yaml  # App of Apps 루트 애플리케이션
└── README.md
```

## 사용 방법

### 1. ArgoCD 설치 및 부트스트랩

```bash
# k3d 로컬 환경
./bootstrap/install-argocd.sh

# 또는 특정 버전으로 설치
ARGOCD_VERSION=v2.10.0 ./bootstrap/install-argocd.sh
```

### 2. ArgoCD 접속

```bash
# Port forwarding
kubectl port-forward svc/argocd-server -n argocd 8080:443

# 브라우저에서 접속
# https://localhost:8080

# 초기 비밀번호 확인
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

### 3. 수동으로 ApplicationSet 적용 (선택)

```bash
# Projects 적용
kubectl apply -f argocd/projects/ -n argocd

# ApplicationSets 적용
kubectl apply -f argocd/applicationsets/ -n argocd
```

## App of Apps 패턴 설명

```
root-application.yaml
    │
    ├── argocd/projects/
    │   ├── infrastructure.yaml (프로젝트 정의)
    │   └── applications.yaml
    │
    └── argocd/applicationsets/
        ├── infrastructure.yaml (monitoring, istio, argo-rollouts)
        ├── stateful-services.yaml (redis, postgresql)
        └── airflow.yaml
```

### 환경별 설정

- **local (k3d)**: `config/local/*.yaml` 값 파일 사용
- **prod (EKS)**: `config/prod/*.yaml` 값 파일 사용

ApplicationSet의 Matrix Generator가 환경과 컴포넌트를 조합하여 자동으로 Application을 생성합니다.

## 주의사항

1. **Git Repository URL**: `root-application.yaml`과 ApplicationSet 파일들의 `repoURL`을 실제 Git 리포지토리로 변경하세요.

2. **EKS 클러스터 URL**: ApplicationSet의 prod 환경 `cluster` URL을 실제 EKS 클러스터 URL로 변경하세요.

3. **Secrets 관리**: 운영 환경의 민감한 정보는 External Secrets 또는 Sealed Secrets를 사용하세요.
