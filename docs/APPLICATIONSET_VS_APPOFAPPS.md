# ApplicationSet vs App of Apps 비교

## 개요

ArgoCD에서 여러 Application을 관리하는 두 가지 패턴을 비교합니다.

---

## App of Apps 패턴

### 개념

"Application이 다른 Application들을 관리"하는 계층 구조입니다.

```
root-application (Application)
└── argocd/applications/
    ├── customer-service.yaml  → customer-service Application
    ├── order-service.yaml     → order-service Application
    ├── payment-service.yaml   → payment-service Application
    └── ... (서비스별 개별 파일)
```

### 코드 예시

**root-application.yaml**
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root-application
spec:
  source:
    repoURL: https://github.com/example/infra.git
    path: argocd/applications  # 이 폴더의 yaml 파일들을 적용
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
```

**argocd/applications/customer-service.yaml**
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: customer-service
spec:
  source:
    repoURL: https://github.com/example/infra.git
    path: charts/services/customer-service
    helm:
      valueFiles:
        - values.yaml
        - ../../config/prod/customer-service.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: ecommerce
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

**argocd/applications/order-service.yaml**
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: order-service
spec:
  source:
    repoURL: https://github.com/example/infra.git
    path: charts/services/order-service
    helm:
      valueFiles:
        - values.yaml
        - ../../config/prod/order-service.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: ecommerce
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

### 특징

- **서비스 7개 = 파일 7개 + root 1개 = 총 8개 파일**
- 각 서비스 설정이 명시적으로 보임
- 서비스 추가 시 새 파일 생성 필요
- 대부분의 내용이 중복됨 (syncPolicy, destination 등)

---

## ApplicationSet 패턴

### 개념

"템플릿 + 데이터 목록"으로 Application을 동적 생성합니다.

```
services.yaml (ApplicationSet)
├── 서비스 목록: [customer, order, payment, ...]
└── 템플릿: Application 구조 정의
    ↓
자동 생성:
├── customer-service Application
├── order-service Application
├── payment-service Application
└── ...
```

### 코드 예시

**argocd/applicationsets/services.yaml**
```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: services
  namespace: argocd
spec:
  generators:
    - list:
        elements:
          # 서비스 목록 - 여기에 한 줄 추가하면 Application 자동 생성
          - name: customer-service
          - name: order-service
          - name: payment-service
          - name: product-service
          - name: store-service
          - name: saga-tracker
          - name: recommendation-service

  template:
    metadata:
      name: '{{name}}'  # customer-service, order-service, ...
    spec:
      source:
        repoURL: https://github.com/example/infra.git
        path: 'charts/services/{{name}}'  # charts/services/customer-service, ...
        helm:
          valueFiles:
            - values.yaml
            - '../../config/prod/{{name}}.yaml'
      destination:
        server: https://kubernetes.default.svc
        namespace: ecommerce
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
```

### 특징

- **서비스 7개 = 파일 1개**
- 서비스 추가 시 목록에 한 줄만 추가
- 모든 서비스에 동일한 설정 자동 적용
- 템플릿 문법 이해 필요

---

## 비교표

| 기준 | App of Apps | ApplicationSet |
|------|-------------|----------------|
| **파일 수** | 서비스 수 + 1 | 1개 |
| **서비스 추가** | 새 파일 생성 | 목록에 1줄 추가 |
| **중복 코드** | 많음 | 없음 (템플릿) |
| **가독성** | 명시적, 직관적 | 템플릿 문법 필요 |
| **개별 커스터마이징** | 쉬움 | 가능하지만 복잡 |
| **ArgoCD 권장** | ❌ 레거시 | ✅ 권장 |

---

## 실제 프로젝트 적용

### 현재 프로젝트 구조

```
서비스 목록:
├── customer-service  (고객/인증)
├── store-service     (스토어)
├── product-service   (상품/재고)
├── order-service     (주문)
├── payment-service   (결제)
├── saga-tracker      (사가 추적)
└── recommendation-service (추천)
```

### ApplicationSet이 적합한 이유

1. **동일한 구조**: 모든 서비스가 Hexagonal Architecture, 동일한 Helm 차트 구조
2. **동일한 배포 설정**: syncPolicy, retry, namespace 모두 동일
3. **환경별 차이는 values로 분리**: `config/dev/`, `config/prod/`
4. **서비스 추가 빈번**: recommendation, saga-tracker 등 계속 추가됨

### App of Apps가 더 적합한 경우

- 서비스마다 완전히 다른 배포 설정 필요
- 서비스 수가 적고 (2-3개) 변경 거의 없음
- 팀이 템플릿 문법보다 명시적 정의 선호

---

## 새 서비스 추가 비교

### App of Apps 방식

```bash
# 1. 새 파일 생성
touch argocd/applications/notification-service.yaml

# 2. 기존 파일 복사 후 수정 (50줄 이상)
# - name 변경
# - path 변경
# - valueFiles 변경

# 3. 커밋 & 푸시
```

### ApplicationSet 방식

```yaml
# argocd/applicationsets/services.yaml
generators:
  - list:
      elements:
        - name: customer-service
        - name: order-service
        # ... 기존 서비스들
        - name: notification-service  # ← 이 한 줄만 추가
```

```bash
# 커밋 & 푸시 - 끝
```

---

## 결론

| 패턴 | 사용 시점 |
|------|----------|
| **ApplicationSet** | 동일한 구조의 서비스 여러 개, 서비스 추가/삭제 빈번 |
| **App of Apps** | 서비스별 완전히 다른 설정, 소수 서비스, 명시적 정의 선호 |

**현재 프로젝트**: ApplicationSet 사용 (7개 서비스, 동일 구조, 추가 가능성 높음)
