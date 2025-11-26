# Istio Helm Chart 설치 가이드

## ⚠️ 중요: CRD 설치 필수

이 Helm 차트를 설치하기 전에 **반드시 CRD(Custom Resource Definitions)를 설치해야 합니다**.

## 📋 사전 준비

### 1. Istio Control Plane 설치

Istio Control Plane을 설치하면 Istio CRD가 자동으로 설치됩니다:

```bash
# 방법 1: 설치 스크립트 사용
cd k8s-dev-k3d/istio
./install-istio.sh

# 방법 2: istioctl로 직접 설치
istioctl install --set profile=minimal -y
```

### 2. Gateway API CRD 설치

Gateway API CRD를 별도로 설치해야 합니다:

```bash
# Gateway API CRD 설치
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.0.0/standard-install.yaml

# 설치 확인
kubectl get crd | grep gateway
```

필요한 CRD들:
- `gateways.gateway.networking.k8s.io`
- `httproutes.gateway.networking.k8s.io`
- `gatewayclasses.gateway.networking.k8s.io`
- `authorizationpolicies.security.istio.io`
- `peerauthentications.security.istio.io`
- `requestauthentications.security.istio.io`

### 3. CRD 설치 확인

```bash
# 모든 CRD 확인
kubectl get crd | grep -E "(gateway|istio)"

# 필수 CRD 확인
kubectl get crd \
  gateways.gateway.networking.k8s.io \
  httproutes.gateway.networking.k8s.io \
  gatewayclasses.gateway.networking.k8s.io \
  authorizationpolicies.security.istio.io \
  peerauthentications.security.istio.io \
  requestauthentications.security.istio.io
```

## 🚀 Helm 차트 설치

### 1. 기본 설치

```bash
# 기본 설정으로 설치
helm install istio-config ./helm/management-base/istio \
  --namespace ecommerce \
  --create-namespace
```

### 2. 커스텀 설정으로 설치

```bash
# 특정 서비스만 활성화
helm install istio-config ./helm/management-base/istio \
  --namespace ecommerce \
  --create-namespace \
  --set gateway.main.hostname=api.ecommerce.com \
  --set httpRoute.services.order.enabled=false
```

### 3. Values 파일 사용

```bash
# values 파일로 설치
helm install istio-config ./helm/management-base/istio \
  --namespace ecommerce \
  --create-namespace \
  -f custom-values.yaml
```

## 🔧 문제 해결

### CRD가 설치되지 않음

에러 메시지:
```
resource mapping not found for name: "..." from "": no matches for kind "Gateway" in version "gateway.networking.k8s.io/v1"
ensure CRDs are installed first
```

**해결 방법**:

```bash
# 1. Istio Control Plane 설치 (Istio CRD 자동 설치)
istioctl install --set profile=minimal -y

# 2. Gateway API CRD 설치
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.0.0/standard-install.yaml

# 3. CRD 확인
kubectl get crd | grep -E "(gateway|istio)"

# 4. Helm 차트 재설치
helm install istio-config ./helm/management-base/istio \
  --namespace ecommerce \
  --create-namespace
```

### Gateway가 PROGRAMMED되지 않음

```bash
# Gateway 상태 확인
kubectl get gateway -n ecommerce

# Gateway 상세 정보
kubectl describe gateway ecommerce-gateway -n ecommerce

# Gateway Pod 확인
kubectl get pods -n ecommerce -l gateway.networking.k8s.io/gateway-name=ecommerce-gateway
```

### HTTPRoute가 연결되지 않음

```bash
# HTTPRoute 상태 확인
kubectl get httproute -n ecommerce

# HTTPRoute 상세 정보
kubectl describe httproute order-service-route -n ecommerce

# 백엔드 서비스 확인
kubectl get svc -n ecommerce order-service
```

## 📝 설치 체크리스트

설치 전 확인:

- [ ] Istio Control Plane 설치됨 (`kubectl get pods -n istio-system`)
- [ ] Gateway API CRD 설치됨 (`kubectl get crd | grep gateway`)
- [ ] Istio CRD 설치됨 (`kubectl get crd | grep istio`)
- [ ] `ecommerce` 네임스페이스 생성됨 (또는 `--create-namespace` 사용)

## 🗑️ 제거

```bash
# Helm 차트 제거
helm uninstall istio-config --namespace ecommerce

# Istio Control Plane 제거 (선택사항)
istioctl uninstall --purge -y
```

## 📚 참고 자료

- [Istio 설치 가이드](https://istio.io/latest/docs/setup/install/)
- [Gateway API 설치](https://gateway-api.sigs.k8s.io/)
- [Helm CRD 관리](https://helm.sh/docs/chart_best_practices/custom_resource_definitions/)

