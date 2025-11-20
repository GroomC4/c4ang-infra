# Istio Gateway API 배포 가이드

## 📋 개요

이 문서는 MSA 시스템에서 Istio Gateway API를 사용한 인증/인가 구현을 위한 배포 가이드입니다.

**아키텍처**: 하이브리드 중앙-분산 관리
- **중앙 관리**: Gateway, 전역 보안 정책 (Platform Team)
- **분산 관리**: 서비스별 라우팅, 인가 규칙 (Service Teams)

## 🏗️ 아키텍처 구성

```
┌─────────────────────────────────────────────┐
│         Central Gateway (istio-ingress)      │
│  ┌──────────────────────────────────────┐   │
│  │ - ecommerce-gateway                  │   │
│  │ - JWT Authentication                 │   │
│  │ - TLS Termination                   │   │
│  │ - Global Authorization Policies     │   │
│  └──────────────────────────────────────┘   │
└────────────┬────────────────────────────────┘
             │ Cross-namespace routing
     ┌───────┴──────┬─────────┬──────────┐
     ▼              ▼         ▼          ▼
┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐
│Customer  │ │ Order    │ │Product   │ │Payment   │
│Service   │ │Service   │ │Service   │ │Service   │
│          │ │          │ │          │ │(Dedicated│
│HTTPRoute │ │HTTPRoute │ │HTTPRoute │ │ Gateway) │
│AuthzPol  │ │AuthzPol  │ │AuthzPol  │ │AuthzPol  │
└──────────┘ └──────────┘ └──────────┘ └──────────┘
```

## 📁 디렉토리 구조

```
helm/
├── management-base/
│   └── istio/
│       ├── templates/
│       │   ├── 01-namespace.yaml                 # 네임스페이스 정의
│       │   ├── 03-gateway-main-enhanced.yaml     # 메인 게이트웨이
│       │   ├── 04-gateway-webhook.yaml           # 웹훅 전용 게이트웨이
│       │   ├── 06-request-authentication.yaml    # JWT 검증 설정
│       │   └── 07-authorization-policy.yaml      # 전역 인가 정책
│       └── values.yaml                           # 중앙 설정값
│
└── services/
    ├── customer-service/
    │   ├── templates/
    │   │   ├── httproute.yaml                   # 라우팅 규칙
    │   │   └── istio/
    │   │       ├── request-authentication.yaml  # 서비스 JWT 설정
    │   │       └── authorization-policy.yaml    # 서비스 인가 정책
    │   └── values.yaml
    ├── order-service/
    │   └── ...
    └── payment-service/
        └── ...
```

## 🚀 배포 절차

### 1단계: Istio Control Plane 설치

```bash
# Istio 설치 (ambient mesh 권장)
istioctl install --set values.pilot.env.PILOT_ENABLE_WORKLOAD_ENTRY_AUTOREGISTRATION=true \
                 --set values.global.proxy.autoInject=disabled \
                 --set values.telemetry.v2.prometheus.wasmEnabled=false

# Ambient mesh 활성화 (선택사항)
istioctl install --set profile=ambient

# 설치 확인
kubectl get pods -n istio-system
```

### 2단계: Gateway API CRDs 설치

```bash
# Gateway API CRDs 설치
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.0.0/standard-install.yaml

# 설치 확인
kubectl get crd | grep gateway
```

### 3단계: 중앙 Gateway 및 보안 정책 배포

```bash
# 중앙 Istio 설정 배포
helm upgrade --install istio-gateway ./helm/management-base/istio \
  --namespace ecommerce \
  --create-namespace \
  --values ./helm/management-base/istio/values.yaml \
  --set gateway.main.hostname="api.c4ang.com" \
  --set security.jwt.issuer="ecommerce-service-api" \
  --set security.jwt.jwksUri="http://customer-api.ecommerce.svc.cluster.local:8080/.well-known/jwks.json"

# 배포 확인
kubectl get gateway -n ecommerce
kubectl get requestauthentication -n ecommerce
kubectl get authorizationpolicy -n ecommerce
```

### 4단계: 네임스페이스 레이블 설정

```bash
# 서비스 네임스페이스에 gateway-access 레이블 추가
kubectl label namespace customer-service gateway-access=shared
kubectl label namespace order-service gateway-access=shared
kubectl label namespace product-service gateway-access=shared
kubectl label namespace payment-service gateway-access=dedicated

# Istio injection 활성화
kubectl label namespace customer-service istio-injection=enabled
kubectl label namespace order-service istio-injection=enabled
kubectl label namespace product-service istio-injection=enabled
kubectl label namespace payment-service istio-injection=enabled
```

### 5단계: Customer Service 배포

```bash
# Customer Service 배포 (JWT 발급 서비스)
helm upgrade --install customer-service ./helm/services/customer-service \
  --namespace customer-service \
  --create-namespace \
  --values ./helm/services/customer-service/values.yaml \
  --set istio.enabled=true \
  --set istio.gatewayAPI.enabled=true

# 배포 확인
kubectl get httproute -n customer-service
kubectl get authorizationpolicy -n customer-service
```

### 6단계: 다른 도메인 서비스 배포

```bash
# Order Service 배포
helm upgrade --install order-service ./helm/services/order-service \
  --namespace order-service \
  --create-namespace \
  --set istio.enabled=true

# Product Service 배포
helm upgrade --install product-service ./helm/services/product-service \
  --namespace product-service \
  --create-namespace \
  --set istio.enabled=true

# Payment Service 배포 (PCI 준수를 위한 별도 게이트웨이)
helm upgrade --install payment-service ./helm/services/payment-service \
  --namespace payment-service \
  --create-namespace \
  --set istio.enabled=true \
  --set istio.dedicatedGateway=true
```

## 🔧 설정 관리

### 중앙 설정 (Platform Team)

**`helm/management-base/istio/values.yaml`**:

```yaml
# 게이트웨이 설정
gateway:
  main:
    enabled: true
    hostname: api.c4ang.com
    listeners:
      https:
        enabled: true
        tls:
          certificateRefs:
            - name: wildcard-tls-cert

# 보안 설정
security:
  jwt:
    enabled: true
    issuer: "ecommerce-service-api"
    jwksUri: "http://customer-api.ecommerce.svc.cluster.local:8080/.well-known/jwks.json"

  # Public endpoints (모든 서비스 공통)
  publicEndpoints:
    - /api/v1/auth/customers/signup
    - /api/v1/auth/customers/login
    - /api/v1/auth/owners/signup
    - /api/v1/auth/owners/login
    - /api/v1/auth/refresh
```

### 서비스별 설정 (Service Teams)

**`helm/services/customer-service/values.yaml`**:

```yaml
istio:
  enabled: true
  gatewayAPI:
    enabled: true
    gatewayName: ecommerce-gateway
    gatewayNamespace: ecommerce
    hostnames:
      - api.c4ang.com

  # 서비스별 라우팅 경로
  pathPrefix: /api/v1/customers

  # 서비스별 트래픽 정책
  trafficPolicy:
    connectionPool:
      tcp:
        maxConnections: 100
    outlierDetection:
      consecutive5xxErrors: 5
      interval: 10s
```

## 🧪 배포 검증

### 1. Gateway 상태 확인

```bash
# Gateway 상태 확인
kubectl describe gateway ecommerce-gateway -n ecommerce

# Gateway 서비스 확인
kubectl get svc -n istio-ingress
```

### 2. JWT 인증 테스트

```bash
# 1. Public endpoint 테스트 (인증 불필요)
curl -X POST https://api.c4ang.com/api/v1/auth/customers/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"password"}'

# 2. JWT 토큰 추출
export TOKEN=$(curl -X POST https://api.c4ang.com/api/v1/auth/customers/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"password"}' | jq -r '.accessToken')

# 3. Protected endpoint 테스트 (인증 필요)
curl https://api.c4ang.com/api/v1/customers/profile \
  -H "Authorization: Bearer $TOKEN"

# 4. 잘못된 토큰으로 테스트 (401 에러 예상)
curl https://api.c4ang.com/api/v1/customers/profile \
  -H "Authorization: Bearer invalid-token"
```

### 3. 역할 기반 접근 테스트

```bash
# Customer 역할로 Owner 엔드포인트 접근 (403 에러 예상)
curl -X POST https://api.c4ang.com/api/v1/auth/owners/logout \
  -H "Authorization: Bearer $CUSTOMER_TOKEN"

# Owner 역할로 Owner 엔드포인트 접근 (성공 예상)
curl -X POST https://api.c4ang.com/api/v1/auth/owners/logout \
  -H "Authorization: Bearer $OWNER_TOKEN"
```

### 4. 헤더 주입 확인

```bash
# 서비스 내부에서 헤더 확인
kubectl exec -it deploy/customer-api -n customer-service -- sh
curl localhost:8080/debug/headers

# 예상 출력:
# X-User-Id: 550e8400-e29b-41d4-a716-446655440000
# X-User-Role: CUSTOMER
# X-User-Email: test@example.com
```

## 🔍 트러블슈팅

### 문제: JWT 검증 실패

```bash
# RequestAuthentication 로그 확인
kubectl logs -n istio-ingress deployment/istio-ingressgateway | grep JWT

# 해결방법:
# 1. JWKS URI 접근 가능 확인
kubectl exec -n istio-ingress deployment/istio-ingressgateway -- \
  curl http://customer-api.ecommerce.svc.cluster.local:8080/.well-known/jwks.json

# 2. JWT issuer 일치 확인
echo $TOKEN | jwt decode -
```

### 문제: 403 Forbidden 에러

```bash
# AuthorizationPolicy 상태 확인
kubectl describe authorizationpolicy -n ecommerce

# 디버깅 모드 활성화
kubectl -n istio-system set env deployment/istiod PILOT_ENABLE_WORKLOAD_ENTRY_AUTOREGISTRATION=true

# Envoy 액세스 로그 확인
kubectl logs -n customer-service deployment/customer-api -c istio-proxy | grep "403"
```

### 문제: Cross-namespace 라우팅 실패

```bash
# ReferenceGrant 확인
kubectl get referencegrant -n ecommerce

# 네임스페이스 레이블 확인
kubectl get namespace customer-service -o yaml | grep gateway-access

# HTTPRoute 상태 확인
kubectl describe httproute -n customer-service
```

## 📊 모니터링

### Grafana 대시보드 설정

```yaml
# Grafana 대시보드 import
- Gateway Traffic: 11933
- Service Mesh: 7636
- Control Plane: 7645
```

### 주요 메트릭

```promql
# Gateway 요청률
sum(rate(istio_request_total{reporter="destination",destination_service_name="istio-ingressgateway"}[1m]))

# JWT 인증 실패율
sum(rate(istio_request_total{reporter="destination",response_code="401"}[1m]))

# 서비스별 인가 거부율
sum(rate(istio_request_total{reporter="destination",response_code="403"}[1m])) by (destination_service_name)
```

## 🔄 롤백 절차

```bash
# 1. 서비스별 롤백
helm rollback customer-service -n customer-service

# 2. Gateway 롤백
helm rollback istio-gateway -n ecommerce

# 3. 긴급 시 모든 인가 정책 비활성화
kubectl delete authorizationpolicy --all -n ecommerce

# 4. Spring Security로 복귀 (필요시)
kubectl set env deployment/customer-api -n customer-service \
  SPRING_PROFILES_ACTIVE=security-enabled
```

## 📚 참고 자료

- [Istio Gateway API Documentation](https://istio.io/latest/docs/tasks/traffic-management/gateway-api/)
- [Kubernetes Gateway API](https://gateway-api.sigs.k8s.io/)
- [Istio Security Best Practices](https://istio.io/latest/docs/ops/best-practices/security/)
- [JWT Authentication in Istio](https://istio.io/latest/docs/tasks/security/authentication/jwt/)

## 📞 문의

- Platform Team: platform@company.com
- Security Team: security@company.com
- 긴급 연락처: #platform-oncall (Slack)

---

**문서 버전**: 1.0.0
**최종 수정일**: 2024-11-20
**작성자**: Platform Team