# 개발환경 Bootstrap 스크립트 수정 사항

## 수정 일자: 2025-12-10

## 발견된 문제점

### 1. Istio 프로필 설정 불일치

**문제:**
- `scripts/platform/istio.sh`에서 `profile=demo` 하드코딩
- `charts/istio/INSTALL.md` 문서에서는 `profile=minimal` 권장

**영향:**
- demo 프로필은 불필요한 컴포넌트(istio-ingressgateway, istio-egressgateway) 설치
- Gateway는 ArgoCD Helm 차트가 관리하므로 중복 리소스 생성

**수정:**
```bash
# 변경 전
istioctl install --set profile=demo -y

# 변경 후
istioctl install --set profile=minimal -y
```

### 2. ArgoCD Bootstrap 패턴 불일치

**문제:**
- `scripts/platform/argocd.sh`에서 App of Apps 패턴 사용 (root-application.yaml)
- 실제 구조는 ApplicationSet 패턴 사용 (`argocd/applicationsets/dev/`)
- `bootstrap/root-application.yaml` 파일 부재로 수동 ApplicationSet 적용 필요했음

**영향:**
- dev.sh 실행 후 서비스 Application들이 생성되지 않음
- 수동으로 ApplicationSet을 적용해야 했음

**수정:**
```bash
# 변경 전: apply_root_application() - root-application.yaml 찾기
# 변경 후: apply_applicationsets() - argocd/applicationsets/{env}/ 적용
```

### 3. Istio minimal 프로필 사용 시 추가 설정 필요

**minimal vs demo 프로필 차이:**

| 컴포넌트 | minimal | demo |
|---------|---------|------|
| istiod (Control Plane) | ✅ | ✅ |
| Istio CRD | ✅ | ✅ |
| istio-ingressgateway | ❌ | ✅ |
| istio-egressgateway | ❌ | ✅ |

**minimal 프로필 선택 이유:**
- Kubernetes Gateway API 사용 (Istio IngressGateway 대신)
- Gateway 리소스는 ArgoCD Helm 차트가 관리
- 리소스 절약 (불필요한 컴포넌트 미설치)

**추가 설정 (istio.sh에서 처리):**
1. **Gateway API CRD 설치** - Kubernetes Gateway API 사용을 위해 필수
2. **Istio CRD 확인** - VirtualService, DestinationRule, AuthorizationPolicy 등
3. **ecommerce 네임스페이스 라벨** - `istio-injection=enabled` 설정

**Istio CRD 목록 (minimal 프로필에 포함):**
- `virtualservices.networking.istio.io`
- `destinationrules.networking.istio.io`
- `authorizationpolicies.security.istio.io`
- `requestauthentications.security.istio.io`
- `peerauthentications.security.istio.io`
- `envoyfilters.networking.istio.io`
- `telemetries.telemetry.istio.io`

## 수정된 파일

| 파일 | 변경 내용 |
|------|----------|
| `scripts/platform/istio.sh` | `profile=demo` → `profile=minimal`, CRD 검증 추가, namespace injection 라벨 설정 |
| `scripts/platform/argocd.sh` | `apply_root_application()` → `apply_applicationsets()`, Pod 생성 대기 로직 추가 |
| `scripts/bootstrap/dev.sh` | 로그 메시지 수정 ("App of Apps" → "ApplicationSet 패턴") |

### 4. ArgoCD Pod 대기 로직 개선

**문제:**
- `kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server` 실행 시
- Pod가 아직 생성되지 않아 "no matching resources found" 오류 발생

**수정:**
```bash
# Pod 생성 대기 (라벨이 있는 Pod가 생성될 때까지)
local max_attempts=30
local attempt=0
while [ $attempt -lt $max_attempts ]; do
    if kubectl get pods -l app.kubernetes.io/name=argocd-server -n "$ARGOCD_NS" --no-headers 2>/dev/null | grep -q .; then
        break
    fi
    sleep 2
    attempt=$((attempt + 1))
done

# 그 후 Pod Ready 대기
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server ...
```

## Bootstrap 순서 (수정 후)

```
Phase 1: External Services (Docker Compose)
├── PostgreSQL (5개 DB)
├── Redis (2개)
└── Kafka (Schema Registry 포함)

Phase 2: K3D Cluster
├── msa-quality-cluster 생성
└── ecommerce 네임스페이스 생성

Phase 3: ECR Secret
└── AWS ECR 토큰 발급 및 Secret 생성

Phase 4: Istio Control Plane (minimal 프로필)
├── Gateway API CRD 설치 (v1.2.0)
├── istioctl install --set profile=minimal
├── istiod 배포 확인
├── Istio CRD 설치 확인 (VirtualService, DestinationRule 등)
└── ecommerce 네임스페이스에 istio-injection=enabled 라벨 추가

Phase 5: ArgoCD Bootstrap (ApplicationSet 패턴)
├── ArgoCD 설치 (v2.10.0)
├── AppProject 적용 (applications, infrastructure)
├── Namespace 매니페스트 적용
└── ApplicationSet 적용 (dev 환경)
    ├── infrastructure.yaml (external-services, istio, monitoring, argo-rollouts)
    └── services.yaml (customer, order, payment, product, store, saga-tracker)

Phase 6: Port Forwarding
└── Gateway 포트포워딩 시작
```

## 검증 방법

```bash
# 1. 클러스터 상태 확인
export KUBECONFIG=/Users/castle/IdeaProjects/c4ang-infra/k8s-dev-k3d/kubeconfig/config
kubectl get nodes

# 2. ArgoCD Application 상태 확인
kubectl get applications -n argocd

# 3. ApplicationSet 확인
kubectl get applicationset -n argocd

# 4. Pod 상태 확인
kubectl get pods -n ecommerce
kubectl get pods -n istio-system
kubectl get pods -n argocd

# 5. Istio CRD 확인
kubectl get crd | grep -E "istio|gateway"
```

## ECR Secret 설정

Bootstrap 스크립트에서 Phase 3으로 ECR Secret 설정이 포함되어 있습니다.

**스크립트 위치:** `scripts/platform/ecr.sh`

**동작:**
1. AWS 자격증명 확인 (`aws sts get-caller-identity`)
2. ECR 토큰 발급 (`aws ecr get-login-password`)
3. Kubernetes docker-registry Secret 생성
4. 생성 시간 annotation 추가 (만료 시간 추적용)

**수동 실행:**
```bash
# ECR Secret 생성/갱신
./scripts/platform/ecr.sh

# 상태 확인
./scripts/platform/ecr.sh --status
```

**주의사항:**
- ECR 토큰은 **12시간 후 만료**됨
- 만료 시 서비스 Pod의 이미지 pull 실패
- 정기적으로 갱신하거나, Pod 재시작 전 갱신 필요

## 참고

- Istio 프로필 비교: https://istio.io/latest/docs/setup/additional-setup/config-profiles/
- ApplicationSet 문서: `argocd/README.md`
