# Istio Distributed Tracing with Tempo

## ⚠️ 현재 상태: 확인됨 - Istio 1.28.0 트레이싱 버그

**Istio 1.28.0에서 분산 트레이싱이 완전히 작동하지 않습니다.**

모든 가능한 방법(OpenTelemetry, Zipkin, EnvoyFilter)을 시도했으나 Envoy가 trace span을 생성하지 않습니다.

### 최종 테스트 결과 (2024-12-07)
```bash
# 환경
- Istio: 1.28.0 (control plane + data plane)
- Tempo: 실행 중, 4317 포트 OTLP gRPC 수신 대기
- EnvoyFilter: 전체 mesh에 적용 (workloadSelector 없음)

# 테스트
1. EnvoyFilter 적용 확인
   $ kubectl get envoyfilter -n istio-system tracing-config
   ✅ 성공: EnvoyFilter 리소스 존재

2. order-api, payment-api 재시작 (새 Envoy 설정 적용)
   ✅ 성공: Pods Running 2/2

3. Envoy config_dump 확인
   $ kubectl exec order-api -c istio-proxy -- pilot-agent request GET config_dump
   ❌ 실패: tracing provider 없음 (EnvoyFilter가 주입되지 않음)

4. 트래픽 생성 (curl-test → order-api 10회 호출)
   ✅ 성공: 요청 정상 처리

5. Tempo 클러스터 통계 확인
   $ pilot-agent request GET clusters | grep tempo | grep rq_total
   ❌ 실패: rq_total::0 (Envoy가 Tempo로 단 한 번도 요청 안 함)

6. Tempo trace 검색
   $ wget http://localhost:3200/api/search
   ❌ 실패: {"traces":[]} (trace 데이터 없음)
```

**결론: Istio 1.28.0에서 EnvoyFilter를 통한 tracing 설정 주입이 작동하지 않음**

### 시도한 모든 방법들 (모두 실패)
1. ✅ OpenTelemetry extensionProvider + Telemetry 리소스 → HTTP connection manager에 OTLP provider 생성되나 trace 전송 안됨
2. ✅ Zipkin extensionProvider (Tempo) + MeshConfig.defaultConfig.tracing → Envoy bootstrap에 Zipkin tracer 생성되나 trace 전송 안됨  
3. ✅ Zipkin extensionProvider (Jaeger) + MeshConfig.defaultConfig.tracing → 동일하게 trace 전송 안됨
4. ✅ enableTracing: true 추가 → 변화 없음
5. ✅ 명시적 B3 trace header 전송 → 변화 없음
6. ✅ proxy.istio.io/config annotation 사용 → 변화 없음
7. ✅ Telemetry 리소스 with provider 명시 → 변화 없음
8. ✅ ArgoCD 완전 중지 후 수동 설정 → 변화 없음
9. ✅ Envoy debug 로깅 활성화 → tracing 설정은 인식하나 span 생성 안됨
10. ✅ EnvoyFilter with HTTP_FILTER + workloadSelector (customer-service) → tracing provider 주입 안됨
11. ✅ EnvoyFilter with HTTP_FILTER + workloadSelector (httpbin) → tracing provider 주입 안됨
12. ✅ **EnvoyFilter without workloadSelector (전체 mesh)** → **tracing provider 주입 안됨, rq_total::0**

### 핵심 문제 (최종 확인)
- ✅ Tempo가 4317 포트에서 OTLP gRPC 수신 대기 중
- ✅ Envoy가 `outbound|4317||tempo.monitoring.svc.cluster.local` 클러스터를 가지고 있음
- ✅ EnvoyFilter가 성공적으로 적용됨 (kubectl get envoyfilter 확인)
- ❌ **EnvoyFilter가 Envoy config에 주입되지 않음** (config_dump에 tracing provider 없음)
- ❌ **Envoy가 Tempo로 단 한 번도 요청을 보내지 않음** (`rq_total::0`)
- ❌ **실제로 trace span을 생성하거나 전송하지 않음**
- ❌ Tempo에 trace 데이터 없음 (`{"traces":[]}`)

### 결론
**Istio 1.28.0에서 분산 트레이싱이 완전히 작동하지 않습니다.**

EnvoyFilter를 포함한 모든 방법을 시도했으나:
- EnvoyFilter가 Kubernetes 리소스로는 생성되지만
- Envoy의 실제 런타임 설정(config_dump)에는 반영되지 않음
- 이는 Istio 1.28.0의 **심각한 버그**로 판단됨

Istio 1.27.0에서도 동일한 문제가 발생했으며, 이는 Istio의 EnvoyFilter 처리 로직에 근본적인 문제가 있음을 시사합니다.

### 권장 해결 방법
1. **애플리케이션 레벨 계측 (권장)** - OpenTelemetry SDK를 Spring Boot 애플리케이션에 직접 통합
   - Spring Boot Actuator + Micrometer Tracing
   - OpenTelemetry Java Agent
   - 직접 Tempo로 전송 (Istio 우회)
2. **Istio 다운그레이드** - 1.23.x 또는 1.24.x로 다운그레이드 (단, 1.27.0에서도 실패했으므로 불확실)
3. **Istio 업그레이드 대기** - 1.29.x 또는 1.30.x에서 수정 기대
4. **다른 Service Mesh 고려** - Linkerd, Consul Connect 등

## 완료된 작업
1. ✅ Tempo가 OTLP gRPC (4317), HTTP (4318), Zipkin (9411) 포트에서 실행 중
2. ✅ Grafana에 Tempo 데이터소스 설정 완료
3. ✅ Istio MeshConfig에 OpenTelemetry extensionProvider 설정
4. ✅ Telemetry 리소스 생성 (100% 샘플링)
5. ✅ ProxyConfig 리소스 생성 시도
6. ✅ Grafana Istio 대시보드 추가 (Mesh, Workload, Performance, Control Plane)

### 미해결 이슈
- ❌ Envoy HTTP connection manager에 tracing provider가 활성화되지 않음
- ❌ 실제 트레이스가 Tempo로 전송되지 않음

## 문제 원인

Istio 1.28+에서는 다음 조건이 **모두** 충족되어야 Envoy가 tracing을 활성화합니다:

1. `MeshConfig.extensionProviders` 설정 ✅
2. `MeshConfig.defaultConfig.tracing.provider` 설정 ✅
3. `Telemetry` 리소스로 샘플링 정책 설정 ✅
4. **Envoy HTTP connection manager에 tracing 설정 주입** ❌

현재 1-3은 완료되었으나, 4번이 작동하지 않습니다.

## 현재 설정

### MeshConfig (istio ConfigMap)
```yaml
defaultConfig:
  tracing:
    sampling: 100.0
    custom_tags:
      service.name:
        literal:
          value: "istio-service"
    provider:
      name: "tempo"
extensionProviders:
- name: tempo
  opentelemetry:
    port: 4317
    service: tempo.monitoring.svc.cluster.local
    resource_detectors:
      environment: {}
```

### Telemetry 리소스
```yaml
apiVersion: telemetry.istio.io/v1
kind: Telemetry
metadata:
  name: mesh-default
  namespace: istio-system
spec:
  tracing:
  - providers:
    - name: tempo
    randomSamplingPercentage: 100
```

### ProxyConfig 리소스
```yaml
apiVersion: networking.istio.io/v1beta1
kind: ProxyConfig
metadata:
  name: global-tracing
  namespace: ecommerce
spec:
  selector:
    matchLabels: {}
  concurrency: 2
```

## 검증 명령어

### 1. Envoy bootstrap tracing 설정 확인
```bash
kubectl exec -n ecommerce <pod> -c istio-proxy -- \
  pilot-agent request GET config_dump | \
  jq '.configs[] | select(.["@type"] == "type.googleapis.com/envoy.admin.v3.BootstrapConfigDump") | .bootstrap.tracing'
```

**기대값:** OpenTelemetry provider 설정이 있어야 함
**실제값:** tracing 설정은 있으나 provider가 없음

### 2. HTTP connection manager tracing 확인
```bash
kubectl exec -n ecommerce <pod> -c istio-proxy -- \
  pilot-agent request GET config_dump | \
  grep -A 30 '"name": "envoy.filters.network.http_connection_manager"' | \
  grep -A 30 "tracing"
```

**기대값:** tracing 블록이 있어야 함
**실제값:** tracing 블록 없음 (이것이 핵심 문제)

### 3. Tempo 트레이스 확인
```bash
kubectl exec -n monitoring <tempo-pod> -- \
  wget -qO- 'http://localhost:3200/api/search?limit=20'
```

**기대값:** traces 배열에 데이터가 있어야 함
**실제값:** `{"traces":[],"metrics":{"completedJobs":1,"totalJobs":1}}`

### 4. Envoy 클러스터 통계 확인
```bash
kubectl exec -n ecommerce <pod> -c istio-proxy -- \
  pilot-agent request GET clusters | grep tempo
```

**실제값:** 4318 포트만 있고 4317 포트 없음

## ✅ 해결 방법: EnvoyFilter로 직접 주입 (권장)

Istio 1.28+에서는 **EnvoyFilter를 사용해 HTTP connection manager에 직접 tracing 설정을 주입**하는 것이 가장 확실한 방법입니다.

### 1단계: EnvoyFilter 적용

```bash
cd c4ang-infra
export KUBECONFIG=$(pwd)/environments/dev/kubeconfig/config

# EnvoyFilter 적용
kubectl apply -f charts/istio/envoyfilter-tracing-apply.yaml
```

### 2단계: 기존 Pod 재시작 (Envoy 설정 적용)

```bash
# customer-api 재시작
kubectl delete pod -n ecommerce -l app.kubernetes.io/name=customer-service

# 다른 서비스들도 재시작 (필요시)
kubectl delete pod -n ecommerce -l app.kubernetes.io/name=order-service
kubectl delete pod -n ecommerce -l app.kubernetes.io/name=product-service
```

### 3단계: Envoy 설정 확인

```bash
# Pod 이름 확인
POD=$(kubectl get pod -n ecommerce -l app.kubernetes.io/name=customer-service -o jsonpath='{.items[0].metadata.name}')

# HTTP connection manager에 tracing 설정 확인
kubectl exec -n ecommerce $POD -c istio-proxy -- \
  pilot-agent request GET config_dump | \
  grep -A 50 '"name": "envoy.filters.network.http_connection_manager"' | \
  grep -A 30 "tracing"
```

**기대 결과:** `envoy.tracers.opentelemetry` 설정이 보여야 함

### 4단계: 트래픽 생성 및 트레이스 확인

```bash
# 테스트 트래픽 생성
for i in {1..5}; do
  kubectl run test-trace-$i --image=curlimages/curl:latest --restart=Never -- \
    curl -s http://customer-api.ecommerce.svc.cluster.local:8081/actuator/health
done

# 10초 대기
sleep 10

# Pod 정리
for i in {1..5}; do kubectl delete pod test-trace-$i --ignore-not-found; done

# Tempo에서 트레이스 확인
TEMPO_POD=$(kubectl get pod -n monitoring -l app.kubernetes.io/name=tempo -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n monitoring $TEMPO_POD -- \
  wget -qO- 'http://localhost:3200/api/search?limit=20'
```

**기대 결과:** `{"traces":[...]}`에 트레이스 데이터가 있어야 함

### 5단계: Grafana에서 확인

1. Grafana 접속: `http://172.16.24.53:3000`
2. Explore 메뉴 선택
3. 데이터소스: Tempo 선택
4. Query type: Search 선택
5. Service Name: `istio-service` 또는 `customer-service` 검색
6. Run query 클릭

**기대 결과:** 서비스 간 트레이스가 시각화되어 표시됨

## 설정 설명

### EnvoyFilter가 하는 일

1. **SIDECAR_INBOUND**: 서비스로 들어오는 모든 HTTP 요청에 대해 tracing 활성화
2. **SIDECAR_OUTBOUND**: 서비스에서 나가는 모든 HTTP 요청에 대해 tracing 활성화
3. **OpenTelemetry gRPC**: Tempo의 OTLP gRPC 엔드포인트(4317)로 트레이스 전송
4. **100% Sampling**: 모든 요청을 추적 (개발 환경)

### 프로덕션 환경 설정

프로덕션에서는 샘플링 비율을 낮춰야 합니다:

```yaml
random_sampling:
  value: 0.01  # 1% sampling (프로덕션 권장)
```

### 다른 방법들 (참고용)

#### 방법 A: IstioOperator로 재설치
```yaml
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
metadata:
  name: istio-controlplane
  namespace: istio-system
spec:
  meshConfig:
    extensionProviders:
    - name: tempo
      opentelemetry:
        port: 4317
        service: tempo.monitoring.svc.cluster.local
    defaultConfig:
      tracing:
        sampling: 100.0
        provider:
          name: tempo
```

적용:
```bash
istioctl install -f istio-operator.yaml
```

**단점:** Istio 전체 재설치 필요, 다운타임 발생

#### 방법 B: Zipkin 프로토콜 사용
OpenTelemetry 대신 Zipkin을 사용:

```yaml
extensionProviders:
- name: tempo
  zipkin:
    service: tempo.monitoring.svc.cluster.local
    port: 9411
```

**단점:** Zipkin 프로토콜은 OpenTelemetry보다 기능이 제한적

## 참고 자료

- [Istio Distributed Tracing](https://istio.io/latest/docs/tasks/observability/distributed-tracing/)
- [Istio Telemetry API](https://istio.io/latest/docs/reference/config/telemetry/)
- [Tempo with Istio](https://grafana.com/docs/tempo/latest/setup/istio/)
- [Istio 1.28 Release Notes](https://istio.io/latest/news/releases/1.28.x/)

## 빠른 적용 (Quick Start)

```bash
cd c4ang-infra
export KUBECONFIG=$(pwd)/environments/dev/kubeconfig/config

# 자동 적용 스크립트 실행
./scripts/apply-istio-tracing.sh
```

이 스크립트는 다음을 자동으로 수행합니다:
1. EnvoyFilter 적용
2. 모든 서비스 Pod 재시작
3. Envoy 설정 확인
4. 다음 단계 안내

## 문제 해결 (Troubleshooting)

### 트레이스가 여전히 수집되지 않는 경우

1. **Envoy 설정 재확인**
```bash
POD=$(kubectl get pod -n ecommerce -l app.kubernetes.io/name=customer-service -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n ecommerce $POD -c istio-proxy -- \
  pilot-agent request GET config_dump | \
  grep -A 50 "envoy.tracers.opentelemetry"
```

2. **Tempo 연결 확인**
```bash
kubectl exec -n ecommerce $POD -c istio-proxy -- \
  pilot-agent request GET clusters | grep tempo
```

3. **Tempo 로그 확인**
```bash
kubectl logs -n monitoring -l app.kubernetes.io/name=tempo --tail=50
```

4. **EnvoyFilter 재적용**
```bash
kubectl delete envoyfilter tracing-config -n istio-system
kubectl apply -f charts/istio/envoyfilter-tracing-apply.yaml
kubectl delete pod -n ecommerce --all
```

### 프로덕션 배포 시 주의사항

1. **샘플링 비율 조정**: `random_sampling.value`를 0.01-0.1 (1-10%)로 낮추기
2. **리소스 모니터링**: Tempo의 메모리/디스크 사용량 모니터링
3. **점진적 롤아웃**: 한 번에 모든 서비스를 재시작하지 말고 순차적으로 적용
4. **백업**: EnvoyFilter 적용 전 현재 설정 백업
