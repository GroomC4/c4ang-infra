# Istio Ambient Mesh 전환 가이드

## 1. 개요

### 1.1 Ambient Mesh란?
Istio Ambient Mesh는 sidecar 없이 서비스 메시 기능을 제공하는 새로운 데이터 플레인 모드입니다.

```
┌─────────────────────────────────────────────────────────────────┐
│                    Sidecar 모드 vs Ambient 모드                   │
├─────────────────────────────────┬───────────────────────────────┤
│          Sidecar 모드           │         Ambient 모드           │
├─────────────────────────────────┼───────────────────────────────┤
│  ┌─────────┐  ┌─────────┐      │  ┌─────────┐  ┌─────────┐    │
│  │   App   │  │ Envoy   │      │  │   App   │  │   App   │    │
│  │         │  │ Sidecar │      │  │ (only)  │  │ (only)  │    │
│  └────┬────┘  └────┬────┘      │  └────┬────┘  └────┬────┘    │
│       │            │           │       │            │          │
│       └────────────┘           │       └────────────┘          │
│            Pod                 │            Pods               │
├─────────────────────────────────┼───────────────────────────────┤
│  메모리: ~100MB/Pod            │  메모리: 0 (ztunnel 공유)      │
│  CPU: ~50m/Pod                 │  CPU: 0 (ztunnel 공유)         │
│  시작 시간: +5-10초            │  시작 시간: 변경 없음          │
└─────────────────────────────────┴───────────────────────────────┘
```

### 1.2 구성 요소

| 구성 요소 | 역할 | 배포 방식 |
|----------|------|----------|
| **ztunnel** | L4 mTLS, 기본 인가 | DaemonSet (노드당 1개) |
| **waypoint** | L7 기능 (JWT, 고급 인가, Retry 등) | Deployment (선택적) |
| **istiod** | 컨트롤 플레인 | 기존과 동일 |

## 2. Dev 환경 전환

### 2.1 사전 조건

```bash
# Istio 1.22+ 필요 (Ambient 지원)
istioctl version
# 최소 버전: 1.22.0, 권장: 1.24.0+
```

### 2.2 신규 설치 (Ambient 모드)

```bash
cd /Users/castle/Workspace/c4ang-infra

# Ambient 모드로 Istio 설치
./scripts/platform/istio.sh --ambient
```

### 2.3 기존 Sidecar에서 Ambient로 마이그레이션

```bash
# 마이그레이션 스크립트 실행
./scripts/platform/istio.sh --migrate-ambient

# 또는 수동 마이그레이션:
# 1. Istio를 Ambient 프로필로 업그레이드
istioctl install --set profile=ambient -y

# 2. 네임스페이스 레이블 변경
kubectl label namespace ecommerce istio-injection- --overwrite
kubectl label namespace ecommerce istio.io/dataplane-mode=ambient --overwrite

# 3. 서비스 재시작 (Sidecar 제거)
kubectl rollout restart rollout -n ecommerce
```

### 2.4 상태 확인

```bash
./scripts/platform/istio.sh --status

# 예상 출력:
# Istio Mode:
#   🌐 Ambient Mode (Sidecar-less)
#
# ztunnel Status:
# NAME      DESIRED   CURRENT   READY   ...
# ztunnel   2         2         2       ...
#
# Namespace Labels:
#   ecommerce: 🌐 ambient
```

## 3. ArgoCD 동기화

### 3.1 자동 동기화
config/dev/istio.yaml에 `ambient.enabled: true` 설정이 있으면 ArgoCD가 자동으로 적용합니다.

```yaml
# config/dev/istio.yaml
ambient:
  enabled: true
  waypoint:
    enabled: false  # L7 기능은 Gateway에서 처리
```

### 3.2 서비스별 Ambient 설정
각 서비스의 config/dev/{service}.yaml에 설정:

```yaml
# config/dev/customer-service.yaml
istio:
  ambient: true  # Sidecar 없이 ztunnel 사용
```

## 4. 검증 체크리스트

### 4.1 mTLS 검증

```bash
# ztunnel 로그에서 mTLS 연결 확인
kubectl logs -n istio-system -l app=ztunnel -c istio-proxy | grep "mTLS"

# 서비스 간 통신 테스트
kubectl exec -n ecommerce deploy/customer-api -- \
  curl -s http://store-api/actuator/health
```

### 4.2 Gateway 동작 확인

```bash
# Gateway는 Ambient와 무관하게 동작
curl -k https://api.ecommerce.com/api/v1/auth/customers/health

# JWT 인증 확인 (Gateway에서 처리)
curl -k -H "Authorization: Bearer $TOKEN" \
  https://api.ecommerce.com/api/v1/orders
```

### 4.3 Pod 상태 확인

```bash
# Sidecar가 없는지 확인 (컨테이너 1개만 있어야 함)
kubectl get pods -n ecommerce -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{range .spec.containers[*]}{.name}{","}{end}{"\n"}{end}'

# 예상 출력: 각 Pod에 app 컨테이너만 있음
# customer-api-xxx    customer-api,
# order-api-xxx       order-api,
```

## 5. Waypoint (L7 기능 필요시)

### 5.1 Waypoint가 필요한 경우
- 서비스 메시 내부에서 JWT 검증 필요
- Path/Method 기반 세밀한 AuthorizationPolicy
- 서비스 레벨 Retry/Timeout/CircuitBreaker

### 5.2 현재 c4ang 환경
**Waypoint 불필요** - 모든 L7 기능이 Gateway에서 처리됨:
- JWT 인증: Gateway의 RequestAuthentication
- RBAC: Gateway의 AuthorizationPolicy
- Retry/Timeout: 애플리케이션 레벨 (Feign Client)

### 5.3 Waypoint 배포 (필요시)

```bash
# Waypoint 배포
./scripts/platform/istio.sh --waypoint

# 또는 수동:
istioctl waypoint apply -n ecommerce --name ecommerce-waypoint --enroll-namespace
```

## 6. 트러블슈팅

### 6.1 mTLS 연결 실패

```bash
# ztunnel 로그 확인
kubectl logs -n istio-system -l app=ztunnel --tail=100

# PERMISSIVE 모드로 전환 (디버깅용)
kubectl apply -f - <<EOF
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata:
  name: default
  namespace: ecommerce
spec:
  mtls:
    mode: PERMISSIVE
EOF
```

### 6.2 서비스 통신 불가

```bash
# ztunnel이 트래픽을 캡처하는지 확인
kubectl logs -n istio-system -l app=ztunnel | grep "connection"

# DNS 해결 확인
kubectl exec -n ecommerce deploy/customer-api -- nslookup store-api
```

### 6.3 롤백 (Sidecar 모드로 복귀)

```bash
# 1. Namespace 레이블 변경
kubectl label namespace ecommerce istio.io/dataplane-mode-
kubectl label namespace ecommerce istio-injection=enabled --overwrite

# 2. 서비스 재시작
kubectl rollout restart rollout -n ecommerce

# 3. (선택) Sidecar 프로필로 재설치
istioctl install --set profile=minimal -y
```

## 7. 리소스 절감 효과

### 7.1 Dev 환경 (6 서비스 × 1 replica)

| 항목 | Sidecar 모드 | Ambient 모드 | 절감 |
|------|-------------|--------------|------|
| customer-api | 100MB | 0 | 100MB |
| store-api | 100MB | 0 | 100MB |
| product-api | 100MB | 0 | 100MB |
| order-api | 100MB | 0 | 100MB |
| payment-api | 100MB | 0 | 100MB |
| saga-tracker | 100MB | 0 | 100MB |
| **Sidecar 합계** | **600MB** | **0** | **600MB** |
| ztunnel (2노드) | - | 100MB | -100MB |
| **총 절감** | | | **~500MB** |

### 7.2 Pod 시작 시간
- Sidecar 모드: +5-10초 (sidecar injection 및 준비)
- Ambient 모드: 변경 없음 (즉시 시작)

## 8. 참고 자료

- [Istio Ambient Mesh 공식 문서](https://istio.io/latest/docs/ambient/)
- [Ambient 모드 FAQ](https://istio.io/latest/docs/ambient/faq/)
- [c4ang Istio 아키텍처 결정](./istio-architecture-decision.md)

---
*작성일: 2024-12-10*
*버전: 1.0*
