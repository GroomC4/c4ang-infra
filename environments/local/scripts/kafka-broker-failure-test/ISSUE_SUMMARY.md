# Kafka Broker Failure Test - 문제 요약

## 🎯 핵심 문제

### 1. Grafana 대시보드에서 오프셋 메트릭이 중복으로 표시됨
- **증상**: Current Offset, Oldest Offset, Offset Gap 등이 파티션별로 여러 값이 표시됨 (예: 490, 490, 490)
- **원인**: Prometheus에서 같은 메트릭이 여러 `job`으로 중복 수집됨
  - `job="kubernetes-pods"`
  - `job="kubernetes-service-endpoints"`
  - `job="kafka-exporter"`
  - `job="prometheus.scrape.pod_metrics"`
- **해결 시도**: 모든 쿼리에 `job="kafka-exporter"` 필터 추가
- **현재 상태**: ❌ 여전히 문제 발생

### 2. 대시보드 파일과 실제 Grafana 대시보드 불일치
- **증상**: 파일에는 8개 패널만 정의되어 있지만, 실제로는 12개 이상의 패널이 표시됨
- **원인**: Grafana에서 수동으로 추가한 패널들이 있음
- **해결 시도**: 
  - UID 변경 (`kafka-broker-failure-test-clean`)
  - ConfigMap 삭제 후 재생성
  - Grafana 재시작
- **현재 상태**: ❌ 여전히 문제 발생

### 3. "Current Consumer Lag" 값이 비정상적으로 높음
- **증상**: "1.96 K" (1960)로 표시됨
- **예상 값**: 약 490 (파티션 0의 current_offset)
- **원인 추정**: 여전히 중복 수집 또는 수동 추가 패널의 쿼리 문제

## 📁 관련 파일

### 대시보드 파일
- `c4ang-infra/charts/monitoring/dashboards/kafka-broker-failure-test-dashboard.json`
  - UID: `kafka-broker-failure-test-clean`
  - 모든 쿼리에 `job="kafka-exporter"` 필터 포함
  - 모든 오프셋 메트릭에 `sum()` 사용

### ConfigMap
- `kafka-broker-failure-test-dashboard` (네임스페이스: `monitoring`)
- 라벨: `grafana_dashboard=1`

### Kafka Exporter 설정
- `c4ang-infra/environments/local/scripts/deploy-kafka-exporter.sh`
- Kafka Exporter가 `job="kafka-exporter"`로 메트릭 노출

## 🔍 확인 필요 사항

### 1. Prometheus 메트릭 확인
```bash
# job 필터 사용 시 메트릭 개수 확인
kubectl exec -n monitoring deployment/prometheus -- \
  wget -qO- 'http://localhost:9090/api/v1/query?query=kafka_topic_partition_current_offset{topic="broker-failure-test",job="kafka-exporter"}' | \
  python3 -c "import sys, json; data=json.load(sys.stdin); print(f'메트릭 개수: {len(data[\"data\"][\"result\"])}')"

# sum() 결과 확인
kubectl exec -n monitoring deployment/prometheus -- \
  wget -qO- 'http://localhost:9090/api/v1/query?query=sum(kafka_topic_partition_current_offset{topic="broker-failure-test",job="kafka-exporter"})' | \
  python3 -c "import sys, json; data=json.load(sys.stdin); print(f'sum() 결과: {data[\"data\"][\"result\"][0][\"value\"][1] if data[\"data\"][\"result\"] else \"No data\"}')"
```

### 2. Grafana 대시보드 실제 쿼리 확인
- Grafana UI에서 각 패널의 쿼리를 직접 확인
- 수동으로 추가된 패널이 있는지 확인
- 각 패널의 `job` 필터 적용 여부 확인

### 3. Kafka Exporter 메트릭 수집 확인
```bash
# Kafka Exporter 메트릭 직접 확인
kubectl exec -n kafka $(kubectl get pods -n kafka -l app=kafka-exporter -o jsonpath='{.items[0].metadata.name}') -- \
  wget -qO- http://localhost:9308/metrics | grep kafka_topic_partition_current_offset | grep broker-failure-test
```

## 🛠️ 시도한 해결 방법

1. ✅ 모든 쿼리에 `job="kafka-exporter"` 필터 추가
2. ✅ 모든 오프셋 메트릭에 `sum()` 사용
3. ✅ 대시보드 UID 변경
4. ✅ ConfigMap 삭제 후 재생성
5. ✅ Grafana 재시작
6. ❌ 여전히 문제 발생

## 📊 현재 대시보드 구성 (파일 기준)

1. Broker Status (State Timeline) - y=0, w=24
2. Alive Brokers (Stat) - y=6, x=0, w=6
3. Current Offset (Stat) - y=6, x=6, w=6
4. Messages In/sec (Stat) - y=6, x=12, w=6
5. Total Lag (Stat) - y=6, x=18, w=6
6. Oldest Offset (Stat) - y=10, x=0, w=6
7. Offset Gap (Stat) - y=10, x=6, w=6
8. Lag Trend (Graph) - y=14, w=24

## ⚠️ 알려진 이슈

1. **Prometheus 중복 수집**: 같은 메트릭이 여러 job으로 수집됨
2. **Grafana 수동 패널**: UI에서 수동으로 추가한 패널이 파일과 동기화되지 않음
3. **메트릭 값 불일치**: Prometheus 쿼리 결과와 Grafana 표시 값이 다름

## 🎯 다음 단계 제안

1. Grafana에서 대시보드를 완전히 삭제하고 파일에서 다시 import
2. Prometheus scrape 설정 확인하여 중복 수집 원인 파악
3. Kafka Exporter 메트릭 레이블 확인 (`job` 레이블이 올바르게 설정되었는지)
4. Grafana 대시보드의 실제 쿼리와 파일의 쿼리 비교

