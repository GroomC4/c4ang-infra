# ArgoCD 구조 리팩토링

## 문제점 분석

### 기존 구조
```
bootstrap/root-application.yaml (App of Apps)
    ↓ 관리
argocd/
├── projects/
│   ├── applications.yaml      → AppProject
│   └── infrastructure.yaml    → AppProject
├── hooks/
│   └── wait-for-applicationset-controller.yaml
└── applicationsets/
    ├── 00-namespaces.yaml     → Application (이름과 다르게 ApplicationSet 아님)
    ├── infrastructure.yaml    → ApplicationSet
    ├── services.yaml          → ApplicationSet
    └── airflow.yaml           → ApplicationSet
```

### 문제점

#### 1. 불필요한 중첩 (2단계 간접 참조)
```
root-application (Application)
    → ApplicationSet들을 관리
        → ApplicationSet이 Application들을 동적 생성
```
- App of Apps 패턴과 ApplicationSet을 혼용
- root-application이 ApplicationSet을 "Application으로 관리"하는 불필요한 레이어
- 디버깅 및 문제 추적 복잡성 증가

#### 2. 혼란스러운 명명
- `applicationsets/00-namespaces.yaml` 파일이 실제로는 `Application` 리소스
- 폴더명과 리소스 타입 불일치로 유지보수 혼란

#### 3. Sync 문제
- root-application 삭제 시 finalizer로 인해 stuck 상태 발생
- ApplicationSet이 생성한 Application들의 라이프사이클 관리 복잡

#### 4. 복잡성 대비 이점 없음
- App of Apps: 여러 Application을 Git으로 관리하기 위한 패턴
- ApplicationSet: 템플릿 기반 Application 동적 생성
- 두 패턴을 혼용할 실질적 이점 없음

---

## 해결 방안

### Option A 선택: ApplicationSet 직접 적용

ApplicationSet만 사용하고 App of Apps 레이어 제거.

**이유:**
1. ApplicationSet이 이미 동적 Application 생성 제공
2. 환경별(dev/prod) 매트릭스 생성 기능 활용
3. 단일 레이어로 관리 단순화

---

## 변경된 구조

### 새로운 디렉토리 구조
```
argocd/
├── README.md                    # 구조 설명 및 사용법
├── projects/
│   ├── applications.yaml        # MSA 서비스용 AppProject
│   └── infrastructure.yaml      # 인프라 컴포넌트용 AppProject
├── applicationsets/
│   ├── infrastructure.yaml      # 인프라 컴포넌트 (monitoring, istio, etc.)
│   ├── services.yaml            # MSA 서비스 (customer, order, etc.)
│   └── airflow.yaml             # Airflow (prod only)
└── manifests/
    └── namespaces.yaml          # 네임스페이스 정의 (수동 적용)

bootstrap/
└── install-argocd.sh            # ArgoCD 설치 및 초기 설정 스크립트
```

### 삭제된 파일
- `bootstrap/root-application.yaml` - 불필요한 App of Apps
- `argocd/applicationsets/00-namespaces.yaml` - 잘못된 위치의 Application
- `argocd/bootStrap-root-app.yaml` - 레거시 파일
- `argocd/hooks/` - App of Apps용 hook (불필요)

### 배포 흐름
```
1. ArgoCD 설치
   └── kubectl apply -f https://...argocd/install.yaml

2. AppProject 적용
   └── kubectl apply -f argocd/projects/

3. Namespace 적용
   └── kubectl apply -f argocd/manifests/namespaces.yaml

4. ApplicationSet 적용
   └── kubectl apply -f argocd/applicationsets/

5. Application 자동 생성 (ApplicationSet에 의해)
   ├── infrastructure-prod, infrastructure-dev
   ├── customer-service-prod, customer-service-dev
   ├── order-service-prod, order-service-dev
   └── ...
```

---

## Bootstrap 스크립트

### install-argocd.sh
```bash
#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARGOCD_DIR="$SCRIPT_DIR/../argocd"

echo "=== ArgoCD Installation ==="

# 1. Create argocd namespace
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

# 2. Install ArgoCD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 3. Wait for ArgoCD to be ready
echo "Waiting for ArgoCD to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

# 4. Apply AppProjects
echo "Applying AppProjects..."
kubectl apply -f "$ARGOCD_DIR/projects/"

# 5. Apply Namespaces
echo "Applying Namespaces..."
kubectl apply -f "$ARGOCD_DIR/manifests/namespaces.yaml"

# 6. Apply ApplicationSets
echo "Applying ApplicationSets..."
kubectl apply -f "$ARGOCD_DIR/applicationsets/"

echo "=== ArgoCD Installation Complete ==="
echo "Get admin password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
```

---

## 마이그레이션 가이드

### 기존 클러스터 정리
```bash
# 1. 기존 root-application 삭제 (finalizer 제거 필요할 수 있음)
kubectl patch application root-application -n argocd -p '{"metadata":{"finalizers":null}}' --type=merge
kubectl delete application root-application -n argocd

# 2. 기존 ApplicationSet 삭제 (재적용 위해)
kubectl delete applicationset --all -n argocd

# 3. 새로운 구조 적용
./bootstrap/install-argocd.sh
```

### 신규 클러스터
```bash
# ArgoCD 설치부터 전체 설정
./bootstrap/install-argocd.sh
```

---

## 이점

1. **단순성**: 단일 레이어 (ApplicationSet → Application)
2. **명확성**: 각 리소스 타입이 올바른 위치에 배치
3. **디버깅 용이**: 문제 발생 시 추적 경로 단순화
4. **유지보수성**: 새 서비스/환경 추가 시 ApplicationSet만 수정
