# Argo Rollouts 모니터링 구현 가이드

## 개요

이 가이드는 Argo Rollouts의 메트릭을 Prometheus로 수집하고 Grafana에서 시각화하는 방법을 설명합니다.

## 아키텍처

```
Argo Rollouts Controller (port 8090)
    ↓ /metrics
Prometheus (scrape)
    ↓ query
Grafana Dashboard (visualization)
```

## 구현된 컴포넌트

### 1. Argo Rollouts 메트릭 서비스

**위치**: `helm/management-base/argo-rollouts/`

- **metrics-service.yaml**: Argo Rollouts controller의 8090 포트를 노출하는 서비스
- Prometheus annotation을 통한 자동 스크랩 설정

### 2. Prometheus 설정

**수정된 파일**:
- `helm/management-base/monitoring/templates/prometheus-rbac.yaml`
  - Argo Rollouts API 리소스 접근 권한 추가

- `helm/management-base/monitoring/templates/prometheus-configmap.yaml`
  - `argo-rollouts` job 추가 (argo-rollouts namespace 스크랩)

### 3. Grafana 대시보드

**파일**:
- `helm/management-base/monitoring/dashboards/argo-rollouts-dashboard.json`

**대시보드 패널**:
1. **Rollout Status**: 각 Rollout의 상태 (Healthy/Degraded)
2. **Rollout Replicas Status**: Available/Desired/Updated replica 추이
3. **Rollout Reconcile Duration**: Reconcile 처리 시간
4. **Rollout Reconcile Errors**: 에러율 추적
5. **Total Rollout Errors**: 전체 에러 게이지
6. **Rollout Phase**: 배포 단계 (Progressing/Healthy/Degraded)
7. **Kubernetes API Request Rate**: Controller의 K8s API 호출률

**변수**:
- `$namespace`: 네임스페이스 필터
- `$rollout`: Rollout 이름 필터

### 4. Alert 규칙

**위치**: `helm/management-base/monitoring/values.yaml`

추가된 알림 규칙:
- **RolloutFailed**: Rollout이 Degraded 상태로 5분 이상 지속
- **RolloutHighErrorRate**: Reconcile 에러율이 0.1/s 초과
- **RolloutStuck**: Rollout이 Progressing 상태로 15분 이상 지속
- **RolloutReplicaMismatch**: Healthy 상태에서 replica 수 불일치가 10분 이상 지속

## 배포 순서

### 1. Argo Rollouts 모니터링 서비스 배포

```bash
# Helm으로 배포
helm upgrade --install argo-rollouts-monitoring \
  helm/management-base/argo-rollouts \
  --namespace argo-rollouts \
  --create-namespace
```

### 2. Monitoring 스택 업그레이드

```bash
# Prometheus, Grafana, Alert 설정 업데이트
helm upgrade --install monitoring \
  helm/management-base/monitoring \
  --namespace monitoring \
  --create-namespace
```

### 3. 배포 확인

```bash
# Argo Rollouts 메트릭 서비스 확인
kubectl get svc -n argo-rollouts argo-rollouts-metrics

# Prometheus target 확인
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# 브라우저에서 http://localhost:9090/targets 접속
# "argo-rollouts" job이 UP 상태인지 확인

# Grafana 접속
kubectl port-forward -n monitoring svc/grafana 3000:3000
# 브라우저에서 http://localhost:3000 접속
# 좌측 메뉴 > Dashboards > "Argo Rollouts Monitoring" 대시보드 확인
```

## 메트릭 설명

### 주요 메트릭

| 메트릭 이름 | 설명 | 타입 |
|-----------|------|------|
| `rollout_info` | Rollout 정보 및 상태 | Gauge |
| `rollout_phase` | Rollout 단계 (Healthy, Progressing, Degraded) | Gauge |
| `rollout_info_replicas_available` | 사용 가능한 replica 수 | Gauge |
| `rollout_info_replicas_desired` | 원하는 replica 수 | Gauge |
| `rollout_info_replicas_updated` | 업데이트된 replica 수 | Gauge |
| `rollout_reconcile` | Reconcile 처리 시간 (histogram) | Histogram |
| `rollout_reconcile_error` | Reconcile 에러 카운트 | Counter |
| `controller_clientset_k8s_request_total` | K8s API 요청 총 수 | Counter |

### 레이블

- `namespace`: Rollout이 속한 네임스페이스
- `name` / `rollout`: Rollout 이름
- `phase`: Rollout 단계
- `strategy`: 배포 전략 (BlueGreen, Canary)

## 트러블슈팅

### 메트릭이 수집되지 않을 때

1. **Argo Rollouts 서비스 확인**:
   ```bash
   kubectl get svc -n argo-rollouts argo-rollouts-metrics
   kubectl describe svc -n argo-rollouts argo-rollouts-metrics
   ```

2. **Endpoint 확인**:
   ```bash
   kubectl get endpoints -n argo-rollouts argo-rollouts-metrics
   ```

3. **메트릭 엔드포인트 직접 확인**:
   ```bash
   kubectl port-forward -n argo-rollouts deployment/argo-rollouts 8090:8090
   curl http://localhost:8090/metrics
   ```

4. **Prometheus 타겟 상태 확인**:
   - Prometheus UI > Status > Targets
   - `argo-rollouts` job의 상태가 UP인지 확인
   - 에러 메시지가 있다면 로그 확인

5. **RBAC 권한 확인**:
   ```bash
   kubectl get clusterrole monitoring-prometheus -o yaml
   # argoproj.io API 그룹 권한이 있는지 확인
   ```

### 대시보드가 표시되지 않을 때

1. **ConfigMap 확인**:
   ```bash
   kubectl get configmap -n monitoring grafana-dashboard-argo-rollouts
   kubectl describe configmap -n monitoring grafana-dashboard-argo-rollouts
   ```

2. **Grafana Pod 로그 확인**:
   ```bash
   kubectl logs -n monitoring deployment/grafana
   ```

3. **대시보드 수동 임포트**:
   - Grafana UI > Dashboards > Import
   - `helm/management-base/monitoring/dashboards/argo-rollouts-dashboard.json` 내용 붙여넣기

### Alert가 동작하지 않을 때

1. **Prometheus 규칙 확인**:
   ```bash
   kubectl get configmap -n monitoring prometheus-config -o yaml | grep -A 20 "RolloutFailed"
   ```

2. **Prometheus Alert 상태 확인**:
   - Prometheus UI > Alerts
   - 규칙이 로드되었는지 확인

## 추가 커스터마이징

### 알림 채널 설정

Slack이나 이메일 알림을 활성화하려면 `values.yaml` 수정:

```yaml
alerting:
  enabled: true
  slack:
    enabled: true
    webhookUrl: "https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
    channel: "#deployments"
```

### 대시보드 커스터마이징

1. Grafana UI에서 대시보드 수정
2. 우측 상단 톱니바퀴 > JSON Model 복사
3. `helm/management-base/monitoring/dashboards/argo-rollouts-dashboard.json` 업데이트
4. Helm 재배포

### 추가 메트릭 수집

Analysis Run이나 Experiment 메트릭도 수집하려면:

```yaml
# prometheus-configmap.yaml에 추가
- job_name: 'argo-experiments'
  kubernetes_sd_configs:
    - role: pod
      namespaces:
        names:
          - argo-rollouts
  relabel_configs:
    - source_labels: [__meta_kubernetes_pod_label_app_kubernetes_io_component]
      regex: experiments-controller
      action: keep
```

## 참고 자료

- [Argo Rollouts 공식 문서](https://argo-rollouts.readthedocs.io/)
- [Argo Rollouts Metrics 문서](https://argo-rollouts.readthedocs.io/en/stable/features/controller-metrics/)
- [Prometheus 쿼리 가이드](https://prometheus.io/docs/prometheus/latest/querying/basics/)
- [Grafana 대시보드 가이드](https://grafana.com/docs/grafana/latest/dashboards/)

## 유지보수

### 메트릭 보존 기간

현재 설정: 30일 (`prometheus.retention.time: 30d`)

변경하려면 `helm/management-base/monitoring/values.yaml`:
```yaml
prometheus:
  retention:
    time: 90d  # 90일로 변경
    size: 45GB
```

### 정기 점검 항목

1. **월 1회**: 대시보드 메트릭 정확성 확인
2. **분기 1회**: Alert 규칙 튜닝 (false positive 감소)
3. **반기 1회**: 메트릭 보존 기간 및 스토리지 사용량 검토
