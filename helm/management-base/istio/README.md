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
  # mTLS 설정
  mTLS:
    enabled: true
    mode: STRICT  # STRICT, PERMISSIVE, DISABLE

  # JWT 인증
  jwt:
    enabled: true
    issuer: "https://api.ecommerce.com"
    jwksUri: "https://api.ecommerce.com/.well-known/jwks.json"
    audiences:
      - "ecommerce-api"

  # Public 엔드포인트 (인증/인가 불필요)
  publicEndpoints:
    # 인증 관련
    - /api/v1/auth/login
    - /api/v1/auth/register
    - /api/v1/auth/refresh
    - /api/v1/users/login
    - /api/v1/users/register
    - /api/v1/users/refresh-token
    - /api/v1/users/verify-email
    - /api/v1/users/reset-password

    # Health Check
    - /actuator/health
    - /actuator/prometheus

    # API 문서 (선택사항)
    - /swagger-ui/*
    - /v3/api-docs/*

  # 역할 기반 인가 (RBAC)
  authorization:
    enabled: true
    roleClaim: "role"  # JWT claim 이름
    paths:
      customer:  # 고객 - 자신의 주문만
        - /api/v1/orders/my/*
        - /api/v1/orders
      owner:     # 가게 주인 - 자신의 가게 관리
        - /api/v1/stores/my/*
        - /api/v1/orders/store/*
      manager:   # 관리자 - 모든 리소스
        - /api/v1/stores/*
        - /api/v1/orders/*
      # MASTER - 모든 권한 (/api/v1/*)
```

**역할 구조:**
- **CUSTOMER**: 자신의 주문 내역만 조회
- **OWNER**: 자신의 가게 주문, 가게 정보, 주문 처리, 메뉴 수정
- **MANAGER**: 모든 가게 및 주문 관리 (MASTER 제외한 사용자 관리)
- **MASTER**: 최고 관리자 (MANAGER 생성/수정/삭제 포함 모든 권한)

### Rate Limiting 설정 (신규 추가!)

```yaml
envoyFilter:
  rateLimit:
    enabled: true
    customResponse: true
    limits:
      default: 100      # 기본: 초당 100건
      auth: 20          # 인증: 초당 20건
      orders: 50        # 주문: 초당 50건
      payments: 30      # 결제: 초당 30건
```

**기능:**
- EnvoyFilter 기반 로컬 레이트 리미팅
- 경로별 세밀한 제한 설정
- 초과 시 429 응답 및 커스텀 메시지

### Circuit Breaker 설정 (신규 추가!)

```yaml
trafficManagement:
  destinationRules:
    enabled: true
    # Connection Pool
    connectionPool:
      tcp:
        maxConnections: 50
      http:
        http1MaxPendingRequests: 100
        maxRequestsPerConnection: 1

    # Circuit Breaker (Outlier Detection)
    circuitBreaker:
      enabled: true
      consecutive5xxErrors: 5      # 5회 연속 에러 시 차단
      interval: 5s                  # 체크 주기
      baseEjectionTime: 30s         # 차단 시간
      maxEjectionPercent: 50        # 최대 50% 인스턴스 차단
```

**기능:**
- 백엔드 과부하 시 자동 차단
- 5회 연속 5xx 에러 시 30초간 인스턴스 제외
- Connection Pool 제한으로 과도한 연결 방지

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

# EnvoyFilter 확인
kubectl get envoyfilter -n istio-system

# DestinationRule 확인
kubectl get destinationrule -n ecommerce
```

## 🧪 테스트 및 데모

### 데모 서비스 배포

`istio-gateway-demo.md` 요구사항에 따라 구현된 샘플 서비스를 배포할 수 있습니다:

```bash
# 데모 orders 서비스 배포
kubectl apply -f ./helm/management-base/istio/demo/orders-service.yaml

# Pod 확인 (2/2 - app + sidecar)
kubectl get pods -n ecommerce -l app=orders
```

### 상세 테스트 가이드

전체 기능을 테스트하고 검증하는 방법은 다음 문서를 참조하세요:

**📖 [TESTING-GUIDE.md](./TESTING-GUIDE.md)**

테스트 내용:
- ✅ JWT 인증 검증
- ✅ Rate Limiting 동작 확인
- ✅ Circuit Breaker 테스트
- ✅ mTLS 확인
- ✅ 트래픽 라우팅 검증

### 빠른 테스트

```bash
# Gateway 외부 접근 테스트
kubectl port-forward -n istio-system svc/istio-ingressgateway 8080:80 &

# 기본 요청
curl -H "Host: api.ecommerce.com" http://localhost:8080/api/v1/orders/status/200

# Rate Limit 테스트
for i in {1..25}; do
  curl -s -o /dev/null -w "%{http_code} " \
    -H "Host: api.ecommerce.com" \
    http://localhost:8080/api/v1/orders/status/200
done
echo ""
# 예상: 200 200 ... 429 429 (20개 이후 제한)
```

## 📚 참고 자료

- [Istio 공식 문서](https://istio.io/latest/docs/)
- [Kubernetes Gateway API](https://gateway-api.sigs.k8s.io/)
- [Helm 문서](https://helm.sh/docs/)
- [istio-gateway-demo.md](../../../istio-gateway-demo.md) - 원본 요구사항
- [TESTING-GUIDE.md](./TESTING-GUIDE.md) - 상세 테스트 가이드

