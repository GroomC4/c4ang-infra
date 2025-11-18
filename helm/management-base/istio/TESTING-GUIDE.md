# Istio Gateway API 테스트 및 검증 가이드

## 📋 개요

이 가이드는 `istio-gateway-demo.md`의 요구사항에 따라 구현된 Istio Gateway 설정을 테스트하고 검증하는 방법을 안내합니다.

## 🎯 테스트 목표

다음 기능들의 동작을 검증합니다:
1. ✅ **JWT 인증** - RequestAuthentication & AuthorizationPolicy
2. ✅ **Rate Limiting** - EnvoyFilter 기반 로컬 레이트 리미팅
3. ✅ **Circuit Breaker** - DestinationRule의 Outlier Detection
4. ✅ **트래픽 라우팅** - Gateway API HTTPRoute
5. ✅ **mTLS** - PeerAuthentication

---

## 🚀 사전 준비

### 1. 필수 구성 요소 확인

```bash
# Istio 설치 확인
istioctl version

# Gateway API CRD 확인
kubectl get crd | grep gateway.networking.k8s.io

# GatewayClass 확인
kubectl get gatewayclass
# 출력: istio GatewayClass가 있어야 함
```

### 2. 네임스페이스 준비

```bash
# ecommerce 네임스페이스 생성 (이미 있다면 스킵)
kubectl create namespace ecommerce

# Istio sidecar 자동 주입 활성화
kubectl label namespace ecommerce istio-injection=enabled
```

### 3. Istio Helm Chart 배포

```bash
# Istio 설정 배포
cd /Users/groom/IdeaProjects/c4ang-infra
helm install istio-config ./helm/management-base/istio \
  --namespace ecommerce \
  --create-namespace

# 배포 확인
helm list -n ecommerce
kubectl get all -n ecommerce
```

---

## 🧪 테스트 시나리오

### 테스트 1: 데모 서비스 배포

```bash
# 샘플 orders 서비스 배포
kubectl apply -f ./helm/management-base/istio/demo/orders-service.yaml

# Pod 상태 확인 (2/2 Ready - app + sidecar)
kubectl get pods -n ecommerce -l app=orders

# Service 확인
kubectl get svc -n ecommerce orders
```

**예상 결과:**
```
NAME          READY   STATUS    RESTARTS   AGE
orders-v1-*   2/2     Running   0          1m
```

---

### 테스트 2: Gateway 및 HTTPRoute 확인

```bash
# Gateway 확인
kubectl get gateway -n ecommerce

# HTTPRoute 확인
kubectl get httproute -n ecommerce

# Gateway 상세 정보
kubectl describe gateway ecommerce-gateway -n ecommerce
```

**예상 결과:**
- Gateway: `ecommerce-gateway` READY
- HTTPRoute: `orders-route` 등록됨

---

### 테스트 3: 기본 트래픽 테스트

```bash
# Gateway의 외부 IP 확인
export INGRESS_HOST=$(kubectl get gateway ecommerce-gateway -n ecommerce -o jsonpath='{.status.addresses[0].value}')
export INGRESS_PORT=80

echo "Gateway URL: http://$INGRESS_HOST:$INGRESS_PORT"

# Port-forward를 통한 테스트 (로컬 환경)
kubectl port-forward -n istio-system svc/istio-ingressgateway 8080:80 &

# 기본 요청 테스트
curl -H "Host: api.ecommerce.com" http://localhost:8080/api/v1/orders/status/200

# 종료 시 port-forward 프로세스 kill
# pkill -f "port-forward.*istio-ingressgateway"
```

**예상 결과:**
```
HTTP/1.1 200 OK
```

---

### 테스트 4: JWT 인증 검증

#### 4.1. JWT 없이 요청 (실패해야 함)

```bash
curl -v -H "Host: api.ecommerce.com" \
  http://localhost:8080/api/v1/orders/get
```

**예상 결과:**
- HTTP 401 Unauthorized (JWT가 필수인 경로인 경우)
- 또는 200 (public endpoint인 경우)

#### 4.2. 유효한 JWT로 요청

```bash
# 테스트용 JWT 생성 (실제 환경에서는 인증 서버에서 발급)
# 여기서는 jwt.io에서 생성한 샘플 JWT 사용
export TEST_JWT="eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJodHRwczovL2FwaS5lY29tbWVyY2UuY29tIiwic3ViIjoidGVzdC11c2VyIiwiYXVkIjoiZWNvbW1lcmNlLWFwaSIsInJvbGVzIjpbIm9yZGVycy5yZWFkIiwib3JkZXJzLndyaXRlIl0sImV4cCI6OTk5OTk5OTk5OX0.test"

curl -H "Host: api.ecommerce.com" \
  -H "Authorization: Bearer $TEST_JWT" \
  http://localhost:8080/api/v1/orders/get
```

**예상 결과:**
```
HTTP/1.1 200 OK
```

#### 4.3. JWT 클레임 확인

Istio는 JWT를 검증하고 클레임을 헤더로 전달합니다:

```bash
# 백엔드 Pod에서 수신된 헤더 확인
kubectl exec -n ecommerce deploy/orders-v1 -c orders -- \
  env | grep X-User
```

**예상 헤더:**
- `X-User-Id`: JWT의 sub 클레임
- `X-User-Roles`: JWT의 roles 클레임

---

### 테스트 5: Rate Limiting 검증

```bash
# 빠르게 25번 요청 (초당 20건 제한)
for i in {1..25}; do
  curl -s -o /dev/null -w "%{http_code} " \
    -H "Host: api.ecommerce.com" \
    -H "Authorization: Bearer $TEST_JWT" \
    http://localhost:8080/api/v1/orders/status/200
done
echo ""
```

**예상 결과:**
```
200 200 200 ... 200 429 429 429 429 429
```
- 처음 20개: 200 OK
- 이후: 429 Too Many Requests

#### Rate Limit 응답 확인

```bash
# 429 응답 상세 확인
curl -v -H "Host: api.ecommerce.com" \
  http://localhost:8080/api/v1/orders/status/200

# 예상 응답 헤더
# x-local-rate-limit: true
# retry-after: 1
# content-type: application/json

# 예상 응답 바디
# {
#   "error": "Too Many Requests",
#   "message": "Rate limit exceeded. Please try again later.",
#   "status": 429
# }
```

---

### 테스트 6: Circuit Breaker 검증

#### 6.1. 정상 상태 확인

```bash
# 정상 요청
for i in {1..10}; do
  curl -s -H "Host: api.ecommerce.com" \
    http://localhost:8080/api/v1/orders/status/200 | head -1
done
```

**예상 결과:** 모두 200 OK

#### 6.2. 장애 유도

```bash
# orders 서비스 스케일 다운 (장애 시뮬레이션)
kubectl scale deployment orders-v1 -n ecommerce --replicas=0

# Pod 종료 확인
kubectl get pods -n ecommerce -l app=orders
```

#### 6.3. Circuit Breaker 동작 확인

```bash
# 요청 시도
for i in {1..10}; do
  curl -s -o /dev/null -w "%{http_code} " \
    -H "Host: api.ecommerce.com" \
    http://localhost:8080/api/v1/orders/status/200
  sleep 1
done
echo ""
```

**예상 결과:**
```
503 503 503 503 503 ...
```
- 5회 연속 5xx 에러 후 Circuit Breaker 작동
- 30초간 인스턴스 제외 (baseEjectionTime)

#### 6.4. 복구

```bash
# 서비스 복구
kubectl scale deployment orders-v1 -n ecommerce --replicas=2

# Pod 시작 대기
kubectl wait --for=condition=ready pod -l app=orders -n ecommerce --timeout=60s

# 정상 요청 확인
curl -H "Host: api.ecommerce.com" \
  http://localhost:8080/api/v1/orders/status/200
```

---

### 테스트 7: mTLS 검증

```bash
# PeerAuthentication 확인
kubectl get peerauthentication -n ecommerce

# mTLS 상태 확인
istioctl authn tls-check -n ecommerce deploy/orders-v1

# 서비스 간 통신 확인 (내부 Pod에서)
kubectl exec -n ecommerce deploy/orders-v1 -c orders -- \
  curl -s http://orders.ecommerce.svc.cluster.local/status/200
```

**예상 결과:**
- `STRICT` 모드로 mTLS 활성화
- Pod 간 통신 성공

---

## 📊 모니터링 및 관찰

### Istio 프록시 로그 확인

```bash
# Ingress Gateway 로그
kubectl logs -n istio-system -l app=istio-ingressgateway --tail=50

# Orders Pod의 Sidecar 로그
kubectl logs -n ecommerce -l app=orders -c istio-proxy --tail=50
```

### Envoy Admin 인터페이스

```bash
# Port-forward to Envoy admin
kubectl port-forward -n ecommerce deploy/orders-v1 15000:15000 &

# Rate Limit 통계
curl http://localhost:15000/stats | grep rate_limit

# Circuit Breaker 통계
curl http://localhost:15000/stats | grep outlier

# 종료
pkill -f "port-forward.*15000"
```

### Istio 설정 확인

```bash
# Gateway 설정 확인
istioctl proxy-config listener -n istio-system deploy/istio-ingressgateway

# Route 설정 확인
istioctl proxy-config route -n istio-system deploy/istio-ingressgateway

# Cluster 설정 확인
istioctl proxy-config cluster -n ecommerce deploy/orders-v1
```

---

## 🔍 트러블슈팅

### 문제 1: JWT 검증 실패

**증상:** 401 Unauthorized even with valid JWT

**해결:**
```bash
# RequestAuthentication 확인
kubectl get requestauthentication -n ecommerce -o yaml

# JWT issuer와 jwksUri 확인
# values.yaml의 설정과 실제 JWT의 issuer가 일치하는지 확인
```

### 문제 2: Rate Limiting 작동 안 함

**증상:** 429 응답이 발생하지 않음

**해결:**
```bash
# EnvoyFilter 확인
kubectl get envoyfilter -n istio-system

# EnvoyFilter 상세 확인
kubectl describe envoyfilter ingress-ratelimit -n istio-system

# Ingress Gateway에 적용되었는지 확인
istioctl proxy-config listener -n istio-system deploy/istio-ingressgateway -o json | grep local_ratelimit
```

### 문제 3: Circuit Breaker 작동 안 함

**증상:** 장애 시에도 계속 503 발생

**해결:**
```bash
# DestinationRule 확인
kubectl get destinationrule -n ecommerce

# Outlier Detection 설정 확인
kubectl get destinationrule orders-circuit-breaker -n ecommerce -o yaml

# Envoy stats 확인
kubectl exec -n ecommerce deploy/orders-v1 -c istio-proxy -- \
  curl -s http://localhost:15000/stats | grep outlier_detection
```

### 문제 4: Sidecar 주입 안 됨

**증상:** Pod에 1/1 컨테이너만 실행 중

**해결:**
```bash
# Namespace 라벨 확인
kubectl get namespace ecommerce --show-labels

# istio-injection=enabled 라벨 추가
kubectl label namespace ecommerce istio-injection=enabled --overwrite

# Pod 재시작
kubectl rollout restart deployment -n ecommerce
```

---

## 📝 테스트 체크리스트

배포 후 다음 항목들을 확인하세요:

- [ ] Istio Control Plane 설치 완료
- [ ] Gateway API CRD 설치 완료
- [ ] Istio Helm Chart 배포 완료
- [ ] ecommerce 네임스페이스에 istio-injection 활성화
- [ ] 데모 서비스(orders) 배포 및 2/2 Ready
- [ ] Gateway 리소스 READY 상태
- [ ] HTTPRoute 등록 완료
- [ ] 기본 트래픽 라우팅 동작 (200 OK)
- [ ] JWT 인증 동작 (401 → 200)
- [ ] Rate Limiting 동작 (200 → 429)
- [ ] Circuit Breaker 동작 (503 → ejection)
- [ ] mTLS 활성화 (STRICT 모드)
- [ ] Envoy 통계에서 메트릭 확인

---

## 🚀 다음 단계

테스트가 성공적으로 완료되면:

1. **프로덕션 설정 조정**
   - Rate Limit 임계값 조정
   - Circuit Breaker 파라미터 튜닝
   - JWT issuer 및 jwksUri 실제 값으로 변경

2. **실제 서비스 통합**
   - `helm/services/` 디렉토리의 서비스들과 통합
   - VirtualService 및 DestinationRule 적용

3. **모니터링 설정**
   - Prometheus/Grafana 대시보드 구성
   - Istio 메트릭 수집 및 알림 설정

4. **부하 테스트**
   - K6 또는 Apache Bench로 부하 테스트
   - Circuit Breaker 및 Rate Limit 동작 검증

---

## 📚 참고 자료

- [Istio 공식 문서](https://istio.io/latest/docs/)
- [Gateway API 문서](https://gateway-api.sigs.k8s.io/)
- [Envoy Rate Limiting](https://www.envoyproxy.io/docs/envoy/latest/configuration/http/http_filters/local_rate_limit_filter)
- [Circuit Breaking](https://istio.io/latest/docs/tasks/traffic-management/circuit-breaking/)
- [istio-gateway-demo.md](../../../istio-gateway-demo.md) - 원본 요구사항

---

**작성일:** 2025-01-18
**작성자:** c4ang Platform Team
