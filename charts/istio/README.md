# Istio Helm Chart

Istio Service Mesh 및 Gateway 설정을 Helm 차트로 관리합니다.

## 📋 개요

이 Helm 차트는 다음을 관리합니다:
- **Gateway 리소스** (Kubernetes Gateway API)
- **HTTPRoute 리소스** (서비스별 라우팅)
- **보안 정책** (mTLS, JWT 인증, Authorization Policy)
- **트래픽 관리** (Circuit Breaker, VirtualService, DestinationRule)

**참고**: Istio Control Plane은 별도로 `istioctl`로 설치해야 합니다.

## ⚠️ 중요: CRD 설치 필수

**이 Helm 차트를 설치하기 전에 반드시 CRD를 설치해야 합니다!**

자세한 설치 방법은 [INSTALL.md](./INSTALL.md)를 참고하세요.

### 빠른 설치

```bash
# 1. Istio Control Plane 설치 (Istio CRD 자동 설치)
istioctl install --set profile=minimal -y

# 2. Gateway API CRD 설치
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.0.0/standard-install.yaml

# 3. CRD 확인
kubectl get crd | grep -E "(gateway|istio)"

# 4. Helm 차트 설치
helm install istio-config ./helm/management-base/istio \
  --namespace ecommerce \
  --create-namespace
```

## 🚀 사용 방법

### 1. 사전 준비 (필수)

#### Istio Control Plane 설치

```bash
# 방법 1: 설치 스크립트 사용 (k3d 환경)
cd k8s-dev-k3d/istio
./install-istio.sh

# 방법 2: istioctl로 직접 설치
istioctl install --set profile=minimal -y
```

#### Gateway API CRD 설치

```bash
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.0.0/standard-install.yaml
```

### 2. Helm 차트 배포

```bash
# 기본 설정으로 배포
helm install istio-config ./helm/management-base/istio \
  --namespace ecommerce \
  --create-namespace

# 또는 values 파일 사용
helm install istio-config ./helm/management-base/istio \
  --namespace ecommerce \
  --create-namespace \
  -f helm/management-base/istio/values.yaml
```

### 4. 특정 서비스만 활성화

```bash
# 특정 서비스만 활성화
helm upgrade istio-config ./helm/management-base/istio \
  --namespace ecommerce \
  --set httpRoute.services.order.enabled=true \
  --set httpRoute.services.product.enabled=true \
  --set httpRoute.services.payment.enabled=false
```

## 📝 주요 설정

### Gateway 설정

```yaml
gateway:
  main:
    enabled: true
    name: ecommerce-gateway
    hostname: api.ecommerce.com
    annotations:
      service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
      service.beta.kubernetes.io/aws-load-balancer-scheme: "internet-facing"
```

### HTTPRoute 설정

```yaml
httpRoute:
  services:
    order:
      enabled: true
      path: /api/v1/orders
      serviceName: order-service
      servicePort: 8080
```

### 보안 설정

```yaml
security:
  mTLS:
    enabled: true
    mode: STRICT
  
  jwt:
    enabled: true
    issuer: "https://api.ecommerce.com"
    jwksUri: "https://api.ecommerce.com/.well-known/jwks.json"
```

## 🔧 업데이트

```bash
# Helm 차트 업데이트
helm upgrade istio-config ./helm/management-base/istio \
  --namespace ecommerce

# 특정 값만 업데이트
helm upgrade istio-config ./helm/management-base/istio \
  --namespace ecommerce \
  --set security.mTLS.mode=PERMISSIVE
```

## 🗑️ 제거

```bash
helm uninstall istio-config --namespace ecommerce
```

## 📊 확인

```bash
# Helm release 확인
helm list -n ecommerce

# Gateway 확인
kubectl get gateway -n ecommerce

# HTTPRoute 확인
kubectl get httproute -n ecommerce

# PeerAuthentication 확인
kubectl get peerauthentication -n ecommerce
```

## 📚 참고 자료

- [Istio 공식 문서](https://istio.io/latest/docs/)
- [Kubernetes Gateway API](https://gateway-api.sigs.k8s.io/)
- [Helm 문서](https://helm.sh/docs/)

