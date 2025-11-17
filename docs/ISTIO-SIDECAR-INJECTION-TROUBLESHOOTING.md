# Istio 사이드카 자동 주입 문제 해결 가이드

## 📋 목차

1. [개요](#개요)
2. [문제 증상](#문제-증상)
3. [주요 원인](#주요-원인)
4. [자동 진단 및 수정](#자동-진단-및-수정)
5. [수동 문제 해결](#수동-문제-해결)
6. [검증 방법](#검증-방법)
7. [예방 조치](#예방-조치)

## 개요

EKS 환경에서 Istio 사이드카가 자동으로 주입되지 않는 문제는 여러 원인으로 발생할 수 있습니다. 이 문서는 Istio 공식 문서를 기반으로 문제를 진단하고 해결하는 방법을 제공합니다.

**참고 문서**:
- [Istio 공식 문서 - Sidecar Injection](https://istio.io/latest/docs/setup/additional-setup/sidecar-injection/)
- [Istio 공식 문서 - Installation](https://istio.io/latest/docs/setup/install/)

## 문제 증상

다음과 같은 증상이 나타나면 사이드카 자동 주입에 문제가 있는 것입니다:

### 1. Pod에 컨테이너가 1개만 있음

```bash
kubectl get pods -n ecommerce

# 예상 결과: 2/2 (앱 컨테이너 + istio-proxy)
# 문제 발생 시: 1/1 (앱 컨테이너만 있음)
```

### 2. istio-proxy 컨테이너가 없음

```bash
kubectl get pod <pod-name> -n ecommerce -o jsonpath='{.spec.containers[*].name}'

# 예상 결과: <app-container> istio-proxy
# 문제 발생 시: <app-container>
```

### 3. Istio 기능이 작동하지 않음

- mTLS 연결 실패
- VirtualService 라우팅이 작동하지 않음
- Circuit Breaker가 적용되지 않음
- Istio 메트릭이 수집되지 않음

## 주요 원인

### 1. 네임스페이스 라벨 누락 ⭐️ (가장 흔한 원인)

**문제**: 네임스페이스에 `istio-injection=enabled` 라벨이 없음

**확인**:
```bash
kubectl get namespace ecommerce --show-labels
```

**해결**:
```bash
kubectl label namespace ecommerce istio-injection=enabled --overwrite
```

### 2. MutatingWebhookConfiguration 문제

**문제**: Istio Webhook이 설치되지 않았거나 제대로 작동하지 않음

**확인**:
```bash
# Webhook 존재 확인
kubectl get mutatingwebhookconfiguration | grep istio

# Webhook 상세 정보
kubectl get mutatingwebhookconfiguration istio-sidecar-injector -o yaml
```

**해결**:
```bash
# Istio 재설치
cd k8s-eks/istio
./install-istio.sh
```

### 3. Pod 주석으로 주입 비활성화

**문제**: Deployment에 `sidecar.istio.io/inject: "false"` 주석이 있음

**확인**:
```bash
kubectl get deployment <deployment-name> -n ecommerce \
  -o jsonpath='{.spec.template.metadata.annotations}'
```

**해결**:
```bash
# 주석 제거 또는 true로 변경
kubectl patch deployment <deployment-name> -n ecommerce --type=json \
  -p='[{"op": "remove", "path": "/spec/template/metadata/annotations/sidecar.istio.io~1inject"}]'

# 또는 true로 설정
kubectl patch deployment <deployment-name> -n ecommerce --type=json \
  -p='[{"op": "replace", "path": "/spec/template/metadata/annotations/sidecar.istio.io~1inject", "value": "true"}]'
```

### 4. istiod (Control Plane) 문제

**문제**: Istio Control Plane이 정상 작동하지 않음

**확인**:
```bash
# istiod Pod 상태 확인
kubectl get pods -n istio-system -l app=istiod

# istiod 로그 확인
kubectl logs -n istio-system -l app=istiod
```

**해결**:
```bash
# istiod 재시작
kubectl rollout restart deployment istiod -n istio-system

# 준비될 때까지 대기
kubectl wait --for=condition=ready pod -l app=istiod -n istio-system --timeout=300s
```

### 5. Webhook 서비스 연결 문제

**문제**: Kubernetes API 서버가 Webhook 서비스에 연결할 수 없음

**확인**:
```bash
# Webhook 서비스 확인
kubectl get svc -n istio-system istiod

# Webhook endpoint 확인
kubectl get endpoints -n istio-system istiod
```

**해결**:
- 네트워크 정책 확인
- 보안 그룹 확인 (EKS)
- istiod 서비스 재시작

## 자동 진단 및 수정

### 1단계: 자동 진단 실행

```bash
cd k8s-eks/istio
./diagnose-sidecar-injection.sh
```

**진단 항목**:
- ✅ Istio Control Plane 상태
- ✅ MutatingWebhookConfiguration 존재 여부
- ✅ 네임스페이스 라벨 확인
- ✅ 기존 Pod의 사이드카 상태
- ✅ Deployment 주석 확인
- ✅ RBAC 권한 확인
- ✅ Webhook 연결성 테스트

**출력 예시**:
```
========================================
Istio 사이드카 자동 주입 진단 도구
========================================
네임스페이스: ecommerce
Istio 네임스페이스: istio-system

[검사] Istio Control Plane 상태 확인
[✓] istiod Pod가 정상적으로 실행 중입니다.
  - istiod 버전: 1.22.0

[검사] MutatingWebhookConfiguration 확인
[✓] MutatingWebhookConfiguration이 존재합니다: istio-sidecar-injector

[검사] 네임스페이스 'ecommerce' 라벨 확인
[✗] 네임스페이스에 istio-injection 라벨이 없습니다.
[해결방법] kubectl label namespace ecommerce istio-injection=enabled --overwrite

...
```

### 2단계: 자동 수정 실행

진단에서 문제가 발견되면 자동 수정 스크립트를 실행합니다:

```bash
cd k8s-eks/istio
./fix-sidecar-injection.sh
```

**수정 내용**:
1. 네임스페이스 생성 및 라벨 설정
2. Deployment 주석 수정
3. Istio 컴포넌트 재시작 (선택적)
4. 기존 Pod 재시작 (선택적)
5. 자동 검증

## 수동 문제 해결

자동 스크립트가 문제를 해결하지 못하는 경우 다음 단계를 수동으로 수행합니다.

### 단계 1: Istio 설치 확인

```bash
# Istio 네임스페이스 확인
kubectl get namespace istio-system

# istiod 확인
kubectl get pods -n istio-system -l app=istiod

# Istio 버전 확인
istioctl version
```

### 단계 2: 네임스페이스 설정

```bash
# 네임스페이스 생성 (없는 경우)
kubectl create namespace ecommerce

# istio-injection 라벨 추가
kubectl label namespace ecommerce istio-injection=enabled --overwrite

# 확인
kubectl get namespace ecommerce --show-labels
```

### 단계 3: Webhook 확인 및 수정

```bash
# MutatingWebhookConfiguration 확인
kubectl get mutatingwebhookconfigurations

# Webhook 상세 정보 확인
kubectl get mutatingwebhookconfig istio-sidecar-injector -o yaml

# namespaceSelector 확인 (중요!)
kubectl get mutatingwebhookconfig istio-sidecar-injector \
  -o jsonpath='{.webhooks[0].namespaceSelector}'
```

**예상 출력** (네임스페이스 라벨 기반):
```json
{
  "matchLabels": {
    "istio-injection": "enabled"
  }
}
```

### 단계 4: 테스트 Pod 배포

```bash
# 테스트 Pod 생성
kubectl run test-nginx --image=nginx:1.25-alpine -n ecommerce

# Pod 확인 (2개 컨테이너 예상)
kubectl get pod test-nginx -n ecommerce

# 컨테이너 이름 확인
kubectl get pod test-nginx -n ecommerce -o jsonpath='{.spec.containers[*].name}'
# 예상 출력: test-nginx istio-proxy

# 테스트 Pod 삭제
kubectl delete pod test-nginx -n ecommerce
```

### 단계 5: 기존 Deployment 재시작

```bash
# 모든 Deployment 재시작
kubectl rollout restart deployment -n ecommerce

# 또는 개별 Deployment 재시작
kubectl rollout restart deployment customer-api -n ecommerce

# 재시작 상태 확인
kubectl rollout status deployment customer-api -n ecommerce

# Pod 상태 확인
kubectl get pods -n ecommerce
```

## 검증 방법

### 1. Pod 컨테이너 수 확인

```bash
# 모든 Pod 확인
kubectl get pods -n ecommerce

# 예상 결과: 2/2 (앱 + istio-proxy)
NAME                            READY   STATUS    RESTARTS   AGE
customer-api-5d8f6c8b9d-abc12   2/2     Running   0          1m
order-api-6c9d7b8a7e-def34      2/2     Running   0          1m
```

### 2. istio-proxy 컨테이너 확인

```bash
# 특정 Pod의 컨테이너 확인
kubectl get pod customer-api-5d8f6c8b9d-abc12 -n ecommerce \
  -o jsonpath='{.spec.containers[*].name}'

# 예상 출력: customer-service istio-proxy
```

### 3. Istio 라벨 확인

```bash
# Pod 라벨 확인
kubectl get pod customer-api-5d8f6c8b9d-abc12 -n ecommerce --show-labels

# istio.io/rev, security.istio.io/tlsMode 등의 라벨이 있어야 함
```

### 4. Envoy 프록시 설정 확인

```bash
# Envoy 설정 확인
istioctl proxy-config cluster customer-api-5d8f6c8b9d-abc12.ecommerce

# 리스너 확인
istioctl proxy-config listener customer-api-5d8f6c8b9d-abc12.ecommerce

# 라우트 확인
istioctl proxy-config route customer-api-5d8f6c8b9d-abc12.ecommerce
```

### 5. mTLS 확인

```bash
# mTLS 상태 확인
istioctl authn tls-check customer-api-5d8f6c8b9d-abc12.ecommerce

# 예상 출력:
# HOST:PORT                                  STATUS     SERVER     CLIENT     AUTHN POLICY     DESTINATION RULE
# order-service.ecommerce.svc.cluster.local  OK         STRICT     ISTIO      default/         -
```

### 6. 통합 검증

```bash
# Istio 전체 검증
istioctl analyze -n ecommerce

# 예상 출력 (문제가 없는 경우):
# ✔ No validation issues found when analyzing namespace: ecommerce.
```

## 예방 조치

### 1. 네임스페이스 생성 시 항상 라벨 추가

**잘못된 방법**:
```bash
kubectl create namespace myapp
# 라벨 없음 -> 사이드카 주입 안됨
```

**올바른 방법**:
```bash
kubectl create namespace myapp
kubectl label namespace myapp istio-injection=enabled
```

**또는 한 번에**:
```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: myapp
  labels:
    istio-injection: enabled
EOF
```

### 2. Helm 차트에서 네임스페이스 라벨 자동화

`helm/management-base/istio/values.yaml`:
```yaml
namespace:
  name: ecommerce
  create: true
  istioInjection: enabled  # 자동으로 라벨 추가
```

### 3. CI/CD 파이프라인에 검증 단계 추가

```bash
# 배포 전 검증
if ! kubectl get namespace $NAMESPACE -o jsonpath='{.metadata.labels.istio-injection}' | grep -q "enabled"; then
  echo "ERROR: Namespace $NAMESPACE does not have istio-injection=enabled label"
  exit 1
fi
```

### 4. Admission Controller 사용

네임스페이스 생성 시 자동으로 라벨을 추가하는 Admission Controller를 구성할 수 있습니다.

### 5. 모니터링 및 알림 설정

Prometheus 쿼리를 사용하여 사이드카가 없는 Pod를 감지:

```promql
# 사이드카가 없는 Pod 수
count(kube_pod_container_info{namespace="ecommerce"}) by (pod) 
- 
count(kube_pod_container_info{namespace="ecommerce", container="istio-proxy"}) by (pod)
```

## 추가 참고 자료

### Istio 공식 문서

- **Sidecar Injection**: https://istio.io/latest/docs/setup/additional-setup/sidecar-injection/
- **Installation**: https://istio.io/latest/docs/setup/install/
- **Troubleshooting**: https://istio.io/latest/docs/ops/diagnostic-tools/

### 관련 문서

- **Istio 설치 가이드**: [k8s-eks/istio/README.md](../k8s-eks/istio/README.md)
- **서비스 배포 가이드**: [helm/services/README.md](../helm/services/README.md)
- **아키텍처 문서**: [ARCHITECTURE.md](./ARCHITECTURE.md)

### 유용한 명령어 모음

```bash
# 빠른 상태 확인
kubectl get pods -n ecommerce -o wide

# 사이드카가 있는 Pod만 표시
kubectl get pods -n ecommerce --field-selector=status.phase=Running \
  -o jsonpath='{range .items[?(@.spec.containers[*].name=="istio-proxy")]}{.metadata.name}{"\n"}{end}'

# 사이드카가 없는 Pod만 표시
comm -23 \
  <(kubectl get pods -n ecommerce -o name | sort) \
  <(kubectl get pods -n ecommerce -o jsonpath='{range .items[?(@.spec.containers[*].name=="istio-proxy")]}{.metadata.name}{"\n"}{end}' | sed 's/^/pod\//' | sort)

# Istio 버전 확인
istioctl version

# Istio 설정 검증
istioctl analyze -A

# Istio 프록시 상태 확인
istioctl proxy-status
```

---

**마지막 업데이트**: 2025-11-17  
**Istio 버전**: 1.22.0+  
**EKS 버전**: 1.28+

