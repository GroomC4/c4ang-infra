# Istio Ambient Mesh 전환 기획서 (Waypoint 미사용)

## 1. 개요

### 1.1 현재 상태
- **Istio Sidecar 모드**: `istio-injection=enabled` 라벨로 각 Pod에 Envoy sidecar 주입
- **트래픽 관리**: VirtualService (Istio CRD) + HTTPRoute (Gateway API) **중복 사용**
- **mTLS**: PeerAuthentication + DestinationRule에서 `ISTIO_MUTUAL` 설정

### 1.2 전환 목표
Istio Ambient Mesh (Waypoint 미사용)로 전환하여:
- Sidecar 제거로 **리소스 효율성 향상** (메모리/CPU 절약)
- **운영 복잡도 감소** (Pod restart 없이 mesh 참여)
- Legacy VirtualService/DestinationRule 제거로 **설정 단일화**
- **Gateway API 표준**으로 통일

### 1.3 Ambient Mesh 아키텍처 (Waypoint 없음)
```
┌─────────────────────────────────────────────────────────────┐
│               Waypoint 없는 Ambient (L4 only)               │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│   ┌─────────────┐                                          │
│   │   Gateway   │  ← HTTPRoute로 L7 라우팅 (timeout/retry) │
│   │  (Ingress)  │  ← JWT 인증 (RequestAuthentication)      │
│   └──────┬──────┘  ← RBAC (AuthorizationPolicy)            │
│          │                                                  │
│   ┌──────▼──────────────────────────────────────────┐      │
│   │           ztunnel (DaemonSet)                    │      │
│   │                                                  │      │
│   │   • L4 mTLS 자동 암호화 (설정 불필요)           │      │
│   │   • TCP 레벨 라우팅                              │      │
│   │   • L4 AuthorizationPolicy                       │      │
│   └──────────────────────────────────────────────────┘      │
│                          │                                  │
│   ┌──────────────────────▼──────────────────────────┐      │
│   │                    Pods                          │      │
│   │    (No Sidecar, No Waypoint - 최소 오버헤드!)    │      │
│   └──────────────────────────────────────────────────┘      │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 1.4 Waypoint 사용하지 않는 이유
| 기능 | 처리 위치 | 비고 |
|------|-----------|------|
| HTTP 라우팅 | Ingress Gateway HTTPRoute | 이미 구현됨 |
| Timeout/Retry | Ingress Gateway HTTPRoute | 마이그레이션 필요 |
| JWT 인증 | Gateway RequestAuthentication | 이미 구현됨 |
| RBAC | Gateway AuthorizationPolicy | 이미 구현됨 |
| mTLS | ztunnel 자동 처리 | 설정 불필요 |
| Circuit Breaker | 추후 필요시 Waypoint 추가 또는 Resilience4j | 현재 비활성화 |

---

## 2. 제거 대상 (Legacy 설정)

### 2.1 VirtualService 파일 (6개) - 삭제
HTTPRoute와 **완전 중복**되므로 제거:

```
charts/services/customer-service/templates/virtualservice.yaml
charts/services/order-service/templates/virtualservice.yaml
charts/services/payment-service/templates/virtualservice.yaml
charts/services/product-service/templates/virtualservice.yaml
charts/services/store-service/templates/virtualservice.yaml
charts/services/saga-tracker/templates/virtualservice.yaml
```

**VirtualService에서 HTTPRoute로 마이그레이션할 설정:**
| 설정 | 기존 값 | HTTPRoute 대체 방법 |
|------|---------|-------------------|
| timeout | 30s | `spec.rules[].timeouts.request` (Gateway API 표준) |
| retries.attempts | 3 | Istio 어노테이션: `retry.istio.io/attempts` |
| retries.perTryTimeout | 10s | Istio 어노테이션: `retry.istio.io/per-try-timeout` |
| retries.retryOn | 5xx,reset,connect-failure,refused-stream | Istio 어노테이션: `retry.istio.io/retry-on` |

### 2.2 DestinationRule 파일 (6개) - 삭제
ztunnel이 mTLS 자동 처리하므로 제거:

```
charts/services/customer-service/templates/destinationrule.yaml
charts/services/order-service/templates/destinationrule.yaml
charts/services/payment-service/templates/destinationrule.yaml
charts/services/product-service/templates/destinationrule.yaml
charts/services/store-service/templates/destinationrule.yaml
charts/services/saga-tracker/templates/destinationrule.yaml
```

**DestinationRule 설정 처리 방안:**
| 설정 | 기존 값 | Ambient 처리 |
|------|---------|-------------|
| tls.mode: ISTIO_MUTUAL | mTLS 활성화 | ztunnel 자동 처리 (삭제) |
| connectionPool.tcp.maxConnections | 100 | L7 기능 - 추후 Waypoint 또는 서비스 레벨 |
| connectionPool.http.* | 50/100/2 | L7 기능 - 추후 Waypoint 또는 서비스 레벨 |
| outlierDetection.* | 5/10s/30s | L7 기능 - 추후 Waypoint 또는 서비스 레벨 |

### 2.3 Circuit Breaker 파일 - 삭제
현재 비활성화 상태이며, Ambient에서는 Waypoint 필요:

```
charts/istio/templates/10-destination-rule-circuit-breaker.yaml
```

---

## 3. 유지할 설정

| 파일 | 용도 | 비고 |
|------|------|------|
| `00-gateway-class.yaml` | Gateway API 컨트롤러 | 유지 |
| `01-namespace.yaml` | 네임스페이스 생성 | **라벨 수정 필요** |
| `02-peer-authentication.yaml` | mTLS 정책 | 유지 (호환성) |
| `03-gateway-main.yaml` | Ingress Gateway | 유지 |
| `04-gateway-webhook.yaml` | Webhook Gateway | 유지 |
| `05-httproute.yaml` | 서비스 라우팅 | **timeout/retry 추가** |
| `05-httproute-webhook.yaml` | Webhook 라우팅 | 유지 |
| `06-request-authentication.yaml` | JWT 검증 | 유지 |
| `07-authorization-policy.yaml` | RBAC 정책 | 유지 |
| `08-telemetry.yaml` | 메트릭 수집 | 유지 |
| `09-envoyfilter-ratelimit.yaml` | Rate Limiting | 유지 (Gateway 레벨) |
| `11-envoyfilter-auth-response.yaml` | 인증 응답 | 유지 |

---

## 4. 수정할 설정

### 4.1 Namespace 라벨 변경
`charts/istio/templates/01-namespace.yaml`:

```yaml
# Before (Sidecar 모드)
metadata:
  labels:
    istio-injection: enabled

# After (Ambient 모드)
metadata:
  labels:
    istio.io/dataplane-mode: ambient
```

### 4.2 HTTPRoute에 Timeout/Retry 추가
`charts/istio/templates/05-httproute.yaml`:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: {{ $serviceName }}-service-route
  annotations:
    # VirtualService에서 마이그레이션한 retry 설정
    retry.istio.io/attempts: "3"
    retry.istio.io/per-try-timeout: "10s"
    retry.istio.io/retry-on: "5xx,reset,connect-failure,refused-stream"
spec:
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: {{ $serviceConfig.path }}
      backendRefs:
        - name: {{ $serviceConfig.serviceName }}
          port: {{ $serviceConfig.servicePort }}
      # VirtualService에서 마이그레이션한 timeout 설정
      timeouts:
        request: 30s
```

### 4.3 values.yaml 업데이트
`charts/istio/values.yaml`:

```yaml
# 추가할 설정
ambient:
  enabled: true

# 수정할 설정
namespace:
  istioInjection: ambient  # enabled → ambient

# HTTPRoute에 timeout/retry 기본값 추가
httpRoute:
  defaults:
    timeout: 30s
    retry:
      attempts: 3
      perTryTimeout: 10s
      retryOn: "5xx,reset,connect-failure,refused-stream"
```

---

## 5. 환경별 설정

### 5.1 config/dev/istio.yaml
```yaml
ambient:
  enabled: true

namespace:
  istioInjection: ambient

# Sidecar 설정 제거됨
```

### 5.2 config/prod/istio.yaml
```yaml
ambient:
  enabled: true

namespace:
  istioInjection: ambient

# Circuit Breaker 필요시 Waypoint 추가 가능
# waypoint:
#   enabled: true
#   services:
#     - payment-api  # 결제 서비스만 L7 정책
```

---

## 6. 마이그레이션 단계

### Phase 1: 준비
- [ ] Istio 버전 확인 (1.22+ 필요)
- [ ] ztunnel, istio-cni 컴포넌트 설치 확인
- [ ] 현재 설정 백업

### Phase 2: HTTPRoute 업데이트
- [ ] `05-httproute.yaml`에 timeout/retry 설정 추가
- [ ] values.yaml에 httpRoute.defaults 추가
- [ ] 테스트 환경에서 검증

### Phase 3: Legacy 설정 제거
- [ ] VirtualService 6개 파일 삭제
- [ ] DestinationRule 6개 파일 삭제
- [ ] Circuit Breaker 파일 삭제
- [ ] 각 서비스 values.yaml에서 istio.* 설정 정리

### Phase 4: Ambient 전환
- [ ] Namespace 라벨 변경 (`istio.io/dataplane-mode: ambient`)
- [ ] Pod 재시작 (sidecar 제거)
- [ ] ztunnel 동작 확인

### Phase 5: 검증
- [ ] mTLS 확인: `istioctl authn tls-check`
- [ ] E2E 테스트 (quality-gate)
- [ ] 메트릭 수집 확인

---

## 7. 파일 변경 요약

### 삭제 (13개)
```
# VirtualService (6개)
charts/services/customer-service/templates/virtualservice.yaml
charts/services/order-service/templates/virtualservice.yaml
charts/services/payment-service/templates/virtualservice.yaml
charts/services/product-service/templates/virtualservice.yaml
charts/services/store-service/templates/virtualservice.yaml
charts/services/saga-tracker/templates/virtualservice.yaml

# DestinationRule (6개)
charts/services/customer-service/templates/destinationrule.yaml
charts/services/order-service/templates/destinationrule.yaml
charts/services/payment-service/templates/destinationrule.yaml
charts/services/product-service/templates/destinationrule.yaml
charts/services/store-service/templates/destinationrule.yaml
charts/services/saga-tracker/templates/destinationrule.yaml

# Circuit Breaker
charts/istio/templates/10-destination-rule-circuit-breaker.yaml
```

### 수정 (4개)
```
charts/istio/values.yaml                    # ambient 설정, httpRoute.defaults
charts/istio/templates/01-namespace.yaml    # 라벨 변경
charts/istio/templates/05-httproute.yaml    # timeout/retry 추가
config/dev/istio.yaml                       # ambient 활성화
config/prod/istio.yaml                      # ambient 활성화
```

---

## 8. 롤백 계획

```bash
# 1. Ambient 라벨 제거
kubectl label namespace ecommerce istio.io/dataplane-mode-

# 2. Sidecar injection 라벨 복원
kubectl label namespace ecommerce istio-injection=enabled

# 3. Pod 재시작 (sidecar 주입)
kubectl rollout restart deployment -n ecommerce

# 4. Git revert
git revert <commit-hash>
```

---

## 9. 예상 효과

### 리소스 절감
| 항목 | Sidecar 모드 | Ambient 모드 | 절감 |
|------|-------------|--------------|------|
| Pod당 메모리 | +128MB (Envoy) | 0 | 100% |
| Pod당 CPU | +100m | 0 | 100% |
| 6서비스 × 3 replica | 2.3GB 추가 | 0 | ~2.3GB |

### 운영 편의성
- Pod 재시작 없이 mesh 참여/탈퇴
- 설정 단일화 (Gateway API 표준)
- 업그레이드 간소화 (ztunnel만 업데이트)

---

## 10. 향후 고도화

### Circuit Breaker 필요시
1. **옵션 A**: 서비스 레벨에서 Resilience4j 사용 (추천)
   - Spring Boot와 자연스러운 통합
   - 서비스별 세밀한 제어 가능

2. **옵션 B**: Waypoint Proxy 추가
   ```bash
   istioctl waypoint apply --namespace ecommerce --name ecommerce-waypoint
   kubectl label service payment-api istio.io/use-waypoint=ecommerce-waypoint
   ```
   - 특정 서비스만 L7 정책 적용 가능
   - DestinationRule 재사용 가능
