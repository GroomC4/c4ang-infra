# Istio Distributed Tracing with Tempo

## 현재 상태

### 완료된 작업
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

## 해결 방법 (시도 필요)

### 방법 1: IstioOperator로 재설치
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

### 방법 2: Zipkin 프로토콜 사용
OpenTelemetry 대신 Zipkin을 사용하면 더 안정적일 수 있습니다:

```yaml
extensionProviders:
- name: tempo
  zipkin:
    service: tempo.monitoring.svc.cluster.local
    port: 9411
```

### 방법 3: EnvoyFilter로 직접 주입
```yaml
apiVersion: networking.istio.io/v1alpha3
kind: EnvoyFilter
metadata:
  name: tracing-config
  namespace: istio-system
spec:
  configPatches:
  - applyTo: HTTP_CONNECTION_MANAGER
    match:
      context: SIDECAR_INBOUND
    patch:
      operation: MERGE
      value:
        tracing:
          provider:
            name: envoy.tracers.opentelemetry
            typed_config:
              "@type": type.googleapis.com/envoy.config.trace.v3.OpenTelemetryConfig
              grpc_service:
                envoy_grpc:
                  cluster_name: outbound|4317||tempo.monitoring.svc.cluster.local
```

## 참고 자료

- [Istio Distributed Tracing](https://istio.io/latest/docs/tasks/observability/distributed-tracing/)
- [Istio Telemetry API](https://istio.io/latest/docs/reference/config/telemetry/)
- [Tempo with Istio](https://grafana.com/docs/tempo/latest/setup/istio/)
- [Istio 1.28 Release Notes](https://istio.io/latest/news/releases/1.28.x/)

## 다음 단계

1. IstioOperator 방식으로 Istio 재설치 시도
2. 또는 Zipkin 프로토콜로 전환
3. 또는 EnvoyFilter로 직접 tracing 설정 주입
4. 트레이스 수집 확인 후 Grafana에서 시각화
