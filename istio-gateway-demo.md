# Istio Gateway API 기반 인증·인가·트래픽 제어 데모 가이드

## 1. 배경과 목표
- 기존 Spring Cloud API Gateway 대신 Kubernetes Gateway API + Istio 조합으로 외부 트래픽 진입점을 구성한다.
- Ingress 구간에서 **인증/인가(JWT)**, **요청 제한(Rate Limiting)**, **서킷 브레이커(Outlier Detection)** 정책을 적용한다.
- 샘플 마이크로서비스(`orders`)를 대상으로 데모를 구축하고 검증 절차를 문서화한다.

## 2. 사전 준비
1. **클러스터 & 툴체인**
   - Kubernetes 1.26 이상, `kubectl`, `istioctl`, `helm`.
   - Istio 1.19+ 권장 (Gateway API 지원 및 Ambient Mesh 옵션 포함).
2. **Istio 설치**
   ```bash
   istioctl install -y --set profile=default
   kubectl label namespace default istio-injection=enabled
   ```
3. **Gateway API CRD 확인**
   ```bash
   kubectl get crd | grep gateway.networking.k8s.io
   kubectl get gatewayclass
   ```
   - Istio 설치 후 `istio` GatewayClass 가 등록되어 있어야 한다.
4. **데모 네임스페이스**
   ```bash
   kubectl create namespace ecommerce
   kubectl label namespace ecommerce istio-injection=enabled
   ```

## 3. 샘플 서비스 배포
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: orders-v1
  namespace: ecommerce
spec:
  replicas: 2
  selector:
    matchLabels:
      app: orders
      version: v1
  template:
    metadata:
      labels:
        app: orders
        version: v1
    spec:
      containers:
      - name: orders
        image: docker.io/istio/examples-bookinfo-orders-v1:1.17.0
        ports:
        - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: orders
  namespace: ecommerce
spec:
  selector:
    app: orders
  ports:
  - name: http
    port: 80
    targetPort: 8080
```
```bash
kubectl apply -f orders.yaml
```

## 4. Gateway API 리소스 정의
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: ecommerce-gateway
  namespace: istio-system
spec:
  gatewayClassName: istio
  listeners:
  - name: http
    port: 80
    protocol: HTTP
    allowedRoutes:
      namespaces:
        from: All
```
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: orders-route
  namespace: ecommerce
spec:
  parentRefs:
  - name: ecommerce-gateway
    namespace: istio-system
  hostnames:
  - api.example.com
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /orders
    backendRefs:
    - name: orders
      port: 80
```
```bash
kubectl apply -f gateway.yaml
kubectl apply -f httproute.yaml
```
확인:
```bash
kubectl -n istio-system get gateway
kubectl -n ecommerce get httproute
```

## 5. 인증 (JWT 검증) 구성
JWT를 사용한 요청만 수락하도록 `RequestAuthentication`과 `AuthorizationPolicy`를 정의한다.

```yaml
apiVersion: security.istio.io/v1
kind: RequestAuthentication
metadata:
  name: orders-jwt
  namespace: ecommerce
spec:
  selector:
    matchLabels:
      app: orders
  jwtRules:
  - issuer: "https://auth.example.com/"
    audiences:
    - "ecommerce-api"
    jwksUri: "https://auth.example.com/.well-known/jwks.json"
```

```yaml
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: orders-authz
  namespace: ecommerce
spec:
  selector:
    matchLabels:
      app: orders
  action: ALLOW
  rules:
  - from:
    - source:
        requestPrincipals: ["https://auth.example.com/*"]
    to:
    - operation:
        paths: ["/orders/*"]
    when:
    - key: request.auth.claims[scope]
      values: ["orders.read", "orders.write"]
```
시나리오 검증:
```bash
# JWT 미포함: 401
curl -H "Host: api.example.com" http://$INGRESS_IP/orders

# 올바른 JWT 포함: 200
curl -H "Host: api.example.com" \
     -H "Authorization: Bearer $VALID_JWT" \
     http://$INGRESS_IP/orders
```

## 6. Rate Limiting (Ingress 단 로컬 제한)
Istio 1.19부터는 Gateway API 리스너에 `EnvoyFilter`를 통해 로컬 레이트 리미팅을 삽입할 수 있다. 다음 예시는 `/orders` 경로에 분당 20건까지 허용한다.

```yaml
apiVersion: networking.istio.io/v1alpha3
kind: EnvoyFilter
metadata:
  name: ecommerce-ingress-ratelimit
  namespace: istio-system
spec:
  workloadSelector:
    labels:
      istio: ingressgateway
  configPatches:
  - applyTo: HTTP_FILTER
    match:
      context: GATEWAY
      listener:
        filterChain:
          filter:
            name: envoy.filters.network.http_connection_manager
            subFilter:
              name: envoy.filters.http.router
    patch:
      operation: INSERT_BEFORE
      value:
        name: envoy.filters.http.local_ratelimit
        typed_config:
          "@type": type.googleapis.com/envoy.extensions.filters.http.local_rate_limit.v3.LocalRateLimit
          stat_prefix: http_local_rate_limiter
          token_bucket:
            max_tokens: 20
            tokens_per_fill: 20
            fill_interval: 60s
          filter_enabled:
            default_value:
              numerator: 100
              denominator: HUNDRED
          filter_enforced:
            default_value:
              numerator: 100
              denominator: HUNDRED
          descriptors:
          - entries:
            - key: request_path
              value: "/orders"
            token_bucket:
              max_tokens: 20
              tokens_per_fill: 20
              fill_interval: 60s
```

검증:
```bash
for i in {1..25}; do
  curl -s -o /dev/null -w "%{http_code}\n" \
       -H "Host: api.example.com" \
       -H "Authorization: Bearer $VALID_JWT" \
       http://$INGRESS_IP/orders
done
# 200 20건 이후 429 발생 확인
```

> 보다 정교한 글로벌 레이트 리미팅이 필요하면 Redis 기반 Istio WasmPlugin 또는 Envoy 글로벌 rate limit service를 연결할 수 있다.

## 7. 서킷 브레이커 (DestinationRule)
백엔드 서비스 과부하 시 호출을 차단/완화하기 위한 기본 설정:

```yaml
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: orders-circuit-breaker
  namespace: ecommerce
spec:
  host: orders.ecommerce.svc.cluster.local
  trafficPolicy:
    connectionPool:
      tcp:
        maxConnections: 50
      http:
        http1MaxPendingRequests: 100
        maxRequestsPerConnection: 1
    outlierDetection:
      consecutive5xxErrors: 5
      interval: 5s
      baseEjectionTime: 30s
      maxEjectionPercent: 50
```
테스트 패턴:
1. `kubectl exec`로 내부 Pod에서 `/orders` 호출 -> 정상.
2. `kubectl scale deployment orders-v1 --replicas=0` 로 장애 유도 -> 클라이언트에서 일부 503 발생, 이어서 outlier detection으로 일정 시간 동안 인스턴스 제외.

## 8. 관찰 및 로깅
- `istioctl proxy-config log <ingress-pod>` 로 레이트 리미팅/인가 로그 확인.
- `kubectl logs -n istio-system deploy/istiod` 로 정책 적용 여부 확인.
- Prometheus/Grafana(옵션)를 통해 `istio_requests_total`, `istio_request_duration_milliseconds` 지표 모니터링.

## 9. 정리 및 확장 포인트
- 위 매니페스트는 `kubectl apply -f` 순서로 적용 가능하며 Istio Gateway API 에서 인증/인가/트래픽 제어를 한꺼번에 구성한다.
- 필요 시 추가 확장:
  1. **OPA / ExtAuthz**: 외부 정책 엔진과 연동해 세밀한 인가 처리.
  2. **글로벌 Rate Limit**: Redis + Envoy 글로벌 리미터.
  3. **버전별 라우팅**: `HTTPRoute` 규칙에 `backendRefs` 가중치로 카나리 배포.
  4. **Ambient Mesh**: 동일 매니페스트를 Ambient에서 재사용 가능하되, L7 waypoint proxy 배치를 통해 정책 적용 범위를 조정할 수 있다.

위 구성을 통해 Spring Cloud Gateway 없이도 Istio가 제공하는 데이터플레인 정책으로 외부 트래픽 제어 요구사항을 충족할 수 있다.
