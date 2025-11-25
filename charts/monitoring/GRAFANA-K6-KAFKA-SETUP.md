# Grafana + K6 + Kafka 메트릭 설정 가이드

## 📋 목차

1. [Grafana 배포](#1-grafana-배포)
2. [K6 설정 및 Grafana 연동](#2-k6-설정-및-grafana-연동)
3. [Kafka 메트릭 수집 설정](#3-kafka-메트릭-수집-설정)
4. [Kafka 대시보드 추가](#4-kafka-대시보드-추가)

---

## 1. Grafana 배포

### 1.1 모니터링 스택 설치

```bash
cd /Users/sanga/Desktop/c4/code/c4ang-infra/helm/management-base/monitoring

# 네임스페이스 생성
kubectl create namespace monitoring

# Helm으로 배포
helm install monitoring . -n monitoring

# 배포 확인
kubectl get pods -n monitoring -w
```

### 1.2 Grafana 접속

```bash
# 포트 포워딩
kubectl port-forward -n monitoring svc/grafana 3000:3000

# 브라우저에서 접속
# URL: http://localhost:3000
# Username: admin
# Password: admin (기본값, 프로덕션에서는 변경 필요)
```

### 1.3 데이터소스 확인

Grafana에 접속 후:
1. Configuration → Data Sources
2. 다음 데이터소스가 자동으로 설정되어 있어야 함:
   - **Prometheus**: `http://prometheus:9090`
   - **Loki**: `http://loki:3100`
   - **Tempo**: `http://tempo:3200`

---

## 2. K6 설정 및 Grafana 연동

### 2.1 K6 Cloud 연동 (권장)

K6 Cloud를 사용하면 Grafana와 자동으로 연동됩니다.

#### K6 Cloud 계정 생성 및 설정

```bash
# K6 Cloud 로그인
k6 login cloud

# 또는 토큰 설정
export K6_CLOUD_TOKEN="your-token-here"
```

#### K6 테스트 실행 (Cloud 모드)

```bash
cd /Users/sanga/Desktop/c4/code/c4ang-infra/performance-tests

# Cloud 모드로 실행
k6 run --cloud tests/load/product-service.js

# 결과는 K6 Cloud 대시보드에서 확인
# https://app.k6.io
```

### 2.2 K6 + Grafana 직접 연동 (로컬)

#### 방법 1: K6 Cloud Output을 Grafana로 전달

```bash
# K6 테스트 실행 시 결과를 Grafana로 전송
k6 run --out cloud --out json=results.json tests/load/product-service.js
```

#### 방법 2: Prometheus Remote Write 사용

K6 테스트 스크립트에 Prometheus 메트릭 수집 추가:

```javascript
// k6-prometheus-exporter 사용
import { Counter, Gauge, Rate } from 'k6/metrics';

// 커스텀 메트릭 정의
const httpRequests = new Counter('http_requests_total');
const httpDuration = new Gauge('http_request_duration_seconds');
const errorRate = new Rate('http_errors_rate');

export default function () {
  const response = http.get('https://api.example.com');
  
  httpRequests.add(1);
  httpDuration.value = response.timings.duration / 1000;
  errorRate.add(response.status >= 400);
}
```

### 2.3 K6 결과를 Prometheus로 전송

#### K6 Operator 사용 (Kubernetes)

```bash
# K6 Operator 설치
kubectl apply -f https://raw.githubusercontent.com/grafana/k6-operator/main/bundle.yaml

# K6 테스트 Job 생성
cat <<EOF | kubectl apply -f -
apiVersion: k6.io/v1alpha1
kind: K6
metadata:
  name: product-service-load-test
  namespace: monitoring
spec:
  script:
    configMap:
      name: k6-test-script
      file: product-service.js
  runner:
    image: grafana/k6:latest
    resources:
      limits:
        cpu: "1000m"
        memory: "1Gi"
EOF
```

---

## 3. Kafka 메트릭 수집 설정

### 3.1 Kafka Exporter 배포 (권장)

Kafka Exporter는 Kafka 클러스터의 메트릭을 Prometheus 형식으로 노출합니다.

#### Kafka Exporter Helm Chart 설치

```bash
# Prometheus Community Helm Repo 추가
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Kafka Exporter 설치
helm install kafka-exporter prometheus-community/kafka-exporter \
  --namespace kafka \
  --set kafka.server=c4-kafka-kafka-bootstrap.kafka:9092 \
  --set serviceMonitor.enabled=true \
  --set serviceMonitor.namespace=monitoring
```

#### 수동 배포 (Helm Chart 없을 경우)

```bash
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kafka-exporter
  namespace: kafka
spec:
  replicas: 1
  selector:
    matchLabels:
      app: kafka-exporter
  template:
    metadata:
      labels:
        app: kafka-exporter
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "9308"
    spec:
      containers:
      - name: kafka-exporter
        image: danielqsj/kafka-exporter:latest
        ports:
        - containerPort: 9308
          name: metrics
        env:
        - name: KAFKA_BROKERS
          value: "c4-kafka-kafka-bootstrap.kafka:9092"
        - name: LOG_LEVEL
          value: "info"
        resources:
          requests:
            cpu: "100m"
            memory: "128Mi"
          limits:
            cpu: "200m"
            memory: "256Mi"
---
apiVersion: v1
kind: Service
metadata:
  name: kafka-exporter
  namespace: kafka
  labels:
    app: kafka-exporter
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "9308"
spec:
  ports:
  - port: 9308
    targetPort: 9308
    name: metrics
  selector:
    app: kafka-exporter
EOF
```

### 3.2 Prometheus에 Kafka Exporter 추가

Prometheus ConfigMap에 Kafka Exporter 스크랩 설정 추가:

```bash
# Prometheus ConfigMap 편집
kubectl edit configmap prometheus-config -n monitoring
```

다음 내용 추가:

```yaml
scrape_configs:
  # ... 기존 설정 ...
  
  # Kafka Exporter
  - job_name: 'kafka-exporter'
    kubernetes_sd_configs:
      - role: endpoints
        namespaces:
          names:
            - kafka
    relabel_configs:
      - source_labels: [__meta_kubernetes_service_name]
        action: keep
        regex: kafka-exporter
      - source_labels: [__meta_kubernetes_endpoint_port_name]
        action: keep
        regex: metrics
```

또는 values.yaml에 추가:

```yaml
prometheus:
  scrapeConfigs:
    # ... 기존 설정 ...
    
    # Kafka Exporter
    - job_name: 'kafka-exporter'
      static_configs:
        - targets: ['kafka-exporter.kafka:9308']
```

### 3.3 Prometheus 재시작

```bash
# Prometheus Pod 재시작하여 새 설정 적용
kubectl rollout restart deployment prometheus -n monitoring
```

---

## 4. Kafka 대시보드 추가

### 4.1 Kafka 대시보드 다운로드

Grafana 공식 대시보드 사용:

```bash
# 대시보드 ID: 721 (Kafka Exporter)
# 또는 758 (Kafka Overview)
```

### 4.2 대시보드 JSON 파일 생성

```bash
cd /Users/sanga/Desktop/c4/code/c4ang-infra/helm/management-base/monitoring/dashboards

# Kafka 대시보드 다운로드 (또는 직접 생성)
# 대시보드 JSON 파일을 이 디렉토리에 저장
```

### 4.3 Grafana에 대시보드 추가

#### 방법 1: Grafana UI에서 추가

1. Grafana 접속: http://localhost:3000
2. **+** → **Import**
3. 대시보드 ID 입력: `721` 또는 `758`
4. **Load**
5. Prometheus 데이터소스 선택
6. **Import**

#### 방법 2: ConfigMap으로 자동 프로비저닝

대시보드 JSON 파일을 ConfigMap에 추가:

```bash
# 대시보드 파일을 dashboards 디렉토리에 추가
# 예: dashboards/kafka-dashboard.json

# Helm 업그레이드
helm upgrade monitoring . -n monitoring
```

#### 방법 3: kubectl로 직접 추가

```bash
# 대시보드 JSON을 ConfigMap으로 생성
kubectl create configmap kafka-dashboard \
  --from-file=kafka-dashboard.json=dashboards/kafka-dashboard.json \
  -n monitoring \
  --dry-run=client -o yaml | \
kubectl label --dry-run=client -f - \
  grafana_dashboard=1 \
  -o yaml | \
kubectl apply -f -
```

### 4.4 주요 Kafka 메트릭

다음 메트릭들이 대시보드에 표시됩니다:

- **Broker 메트릭**:
  - `kafka_broker_info`
  - `kafka_broker_offline_count`
  
- **Topic 메트릭**:
  - `kafka_topic_partitions`
  - `kafka_topic_partition_current_offset`
  - `kafka_topic_partition_oldest_offset`
  - `kafka_topic_partition_in_sync_replica`
  
- **Consumer Group 메트릭**:
  - `kafka_consumergroup_lag_sum`
  - `kafka_consumergroup_members`
  
- **Producer 메트릭**:
  - `kafka_producer_request_total`
  - `kafka_producer_request_duration_seconds`

---

## 5. 통합 확인

### 5.1 모든 컴포넌트 상태 확인

```bash
# Grafana
kubectl get pods -n monitoring -l app.kubernetes.io/component=grafana

# Prometheus
kubectl get pods -n monitoring -l app.kubernetes.io/component=prometheus

# Kafka Exporter
kubectl get pods -n kafka -l app=kafka-exporter

# K6 (테스트 실행 시)
kubectl get pods -n monitoring -l app=k6
```

### 5.2 메트릭 확인

```bash
# Prometheus에서 Kafka 메트릭 확인
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# 브라우저에서 http://localhost:9090 접속
# PromQL 쿼리: kafka_topic_partitions

# Grafana에서 대시보드 확인
kubectl port-forward -n monitoring svc/grafana 3000:3000
# 브라우저에서 http://localhost:3000 접속
# 대시보드 메뉴에서 Kafka 대시보드 확인
```

---

## 6. 트러블슈팅

### Kafka Exporter가 메트릭을 수집하지 않음

```bash
# Kafka Exporter 로그 확인
kubectl logs -n kafka -l app=kafka-exporter

# Kafka 연결 확인
kubectl exec -n kafka kafka-client -- \
  /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server c4-kafka-kafka-bootstrap:9092 \
  --list

# Prometheus에서 스크랩 확인
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# http://localhost:9090/targets 접속하여 kafka-exporter 타겟 상태 확인
```

### Grafana에서 Kafka 메트릭이 보이지 않음

1. Prometheus 데이터소스 연결 확인
2. 대시보드의 메트릭 이름이 실제 메트릭과 일치하는지 확인
3. Prometheus에서 직접 쿼리하여 메트릭 존재 확인:
   ```promql
   kafka_topic_partitions
   ```

### K6 결과가 Grafana에 표시되지 않음

1. K6 Cloud 연동 확인
2. Prometheus Remote Write 설정 확인
3. K6 메트릭이 Prometheus로 전송되는지 확인

---

## 7. 다음 단계

1. **알림 설정**: Kafka 메트릭 기반 알림 규칙 추가
2. **커스텀 대시보드**: 프로젝트 특화 대시보드 생성
3. **성능 테스트 자동화**: CI/CD 파이프라인에 K6 통합
4. **장기 저장**: Thanos 또는 Cortex로 장기 메트릭 저장

---

## 참고 자료

- [Grafana 공식 문서](https://grafana.com/docs/)
- [K6 공식 문서](https://k6.io/docs/)
- [Kafka Exporter GitHub](https://github.com/danielqsj/kafka-exporter)
- [Prometheus Kafka 메트릭](https://prometheus.io/docs/instrumenting/exporters/)
- [Grafana Kafka 대시보드](https://grafana.com/grafana/dashboards/?search=kafka)

