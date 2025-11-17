# 🔍 로그 필터링 가이드

## 개요

E-Commerce 마이크로서비스의 로그 수집에서 불필요한 헬스체크 로그를 자동으로 필터링하고, 중요한 5xx 에러는 항상 수집하도록 구성되었습니다.

## ✅ 수집되는 로그

### 1. **5xx 서버 에러 (최우선)**
```
status=500
status=502
status=503
status=504
HTTP/1.1 500 Internal Server Error
HTTP/1.1 502 Bad Gateway
HTTP/1.1 503 Service Unavailable
HTTP/1.1 504 Gateway Timeout
```
**⚠️ 헬스체크 엔드포인트에서 발생한 5xx 에러도 무조건 수집됩니다.**

### 2. **애플리케이션 로그**
- ERROR 레벨 로그
- WARN 레벨 로그
- INFO 레벨 로그
- Exception 및 Stack Trace
- 비즈니스 로직 로그

### 3. **Access 로그 (5xx 제외)**
- 4xx 클라이언트 에러
- 2xx 성공 응답
- 3xx 리다이렉션

## ❌ 필터링되는 로그 (수집 안됨)

### 1. **헬스체크 엔드포인트 (200 OK만)**
```
GET /health ... 200 OK
GET /healthz ... 200
POST /livez ... 200
GET /readyz ... 200
GET /ping ... 200
```

### 2. **Istio Envoy 프록시 헬스체크**
```
envoy ... health ... 200
```

## 🔄 필터링 동작 순서

```
1. ecommerce 네임스페이스 로그만 대상
   ↓
2. 5xx 에러 체크
   → 있으면 → 무조건 수집 (다음 단계 스킵)
   → 없으면 → 다음 단계 진행
   ↓
3. 헬스체크 로그 (200 OK) 체크
   → 있으면 → 드롭 (수집 안함)
   → 없으면 → 다음 단계 진행
   ↓
4. Istio 프록시 헬스체크 체크
   → 있으면 → 드롭 (수집 안함)
   → 없으면 → 수집
```

## 📊 예상 로그 감소량

### 변경 전
```
총 로그: 100,000 lines/min
- 헬스체크 로그: 80,000 lines/min (80%)
- 애플리케이션 로그: 15,000 lines/min (15%)
- 5xx 에러: 5,000 lines/min (5%)
```

### 변경 후
```
총 로그: 20,000 lines/min (80% 감소)
- 헬스체크 로그: 0 lines/min (필터링됨)
- 애플리케이션 로그: 15,000 lines/min (유지)
- 5xx 에러: 5,000 lines/min (유지)
```

**💰 스토리지 비용 절감: 약 80% (S3 저장 용량 기준)**

## 🧪 테스트 방법

### 1. 헬스체크 로그가 필터링되는지 확인
```bash
# 헬스체크 요청 생성
kubectl exec -it -n ecommerce deployment/customer-api -- \
  curl -X GET http://localhost:8080/health

# Loki에서 확인 (결과 없어야 정상)
# Grafana Explore → Loki
# Query: {namespace="ecommerce", pod=~"customer.*"} |~ "health.*200"
```

### 2. 5xx 에러가 수집되는지 확인
```bash
# 의도적으로 5xx 에러 생성
kubectl exec -it -n ecommerce deployment/customer-api -- \
  curl -X GET http://localhost:8080/api/test-500

# Loki에서 확인 (결과 있어야 정상)
# Grafana Explore → Loki
# Query: {namespace="ecommerce", pod=~"customer.*"} |~ "(?i)(status[=:\\s]*(5[0-9]{2})|HTTP/[0-9.]* 5[0-9]{2})"
```

### 3. 헬스체크 5xx 에러도 수집되는지 확인
```bash
# 헬스체크 엔드포인트에서 5xx 에러 생성 (테스트 필요)
# 예: health 엔드포인트가 일시적으로 500 반환

# Loki에서 확인 (결과 있어야 정상)
# Query: {namespace="ecommerce"} |~ "health.*5[0-9]{2}"
```

## 🔧 설정 파일 위치

### Alloy ConfigMap
```
helm/management-base/monitoring/templates/alloy-configmap.yaml
```

핵심 설정:
```yaml
loki.process "filter_healthcheck" {
  stage.match {
    selector = "{namespace=\"ecommerce\"}"
    
    # 5xx 에러는 항상 수집
    stage.match {
      pipeline_name = "keep_5xx_errors"
      selector      = "{} |~ \"(?i)(status[=:\\s]*(5[0-9]{2})|HTTP/[0-9.]* 5[0-9]{2})\""
      action        = "keep"
    }

    # 헬스체크 로그 드롭 (200 OK)
    stage.drop {
      expression = "(?i)(GET|POST).*(health|healthz|healthcheck|livez|readyz|ping).*?(200|OK)"
    }

    # Istio 프록시 헬스체크 드롭
    stage.drop {
      expression = "(?i)envoy.*health.*200"
    }
  }
}
```

## 📈 모니터링 메트릭

### Alloy에서 드롭된 로그 확인
```promql
# 드롭된 로그 수
sum(rate(loki_process_dropped_lines_total{reason="healthcheck"}[5m]))

# 드롭 비율
sum(rate(loki_process_dropped_lines_total{reason="healthcheck"}[5m])) 
/ 
sum(rate(loki_process_lines_total[5m])) * 100
```

## 🔄 필터링 규칙 수정

### 추가 엔드포인트 필터링
```yaml
stage.drop {
  expression = "(?i)(GET|POST).*(health|healthz|metrics|status|ping).*?(200|OK)"
}
```

### 특정 서비스만 필터링
```yaml
stage.match {
  selector = "{namespace=\"ecommerce\", pod=~\"customer.*\"}"
  # 필터링 규칙
}
```

### 필터링 비활성화 (전체 로그 수집)
```yaml
# loki.process "filter_healthcheck" 전체 블록 주석 처리
# forward_to를 직접 loki.write로 변경

loki.source.kubernetes "pods" {
  targets    = discovery.relabel.logs.output
  forward_to = [loki.write.default.receiver]  # 필터 우회
}
```

## 🚨 문제 해결

### 5xx 에러가 수집되지 않을 때
```bash
# Alloy 로그 확인
kubectl logs -n monitoring daemonset/alloy -f | grep -i "5[0-9][0-9]"

# ConfigMap 확인
kubectl get configmap -n monitoring alloy-config -o yaml | grep -A 5 "keep_5xx"

# Alloy 재시작
kubectl rollout restart daemonset/alloy -n monitoring
```

### 헬스체크 로그가 여전히 수집될 때
```bash
# 로그 패턴 확인
kubectl logs -n ecommerce deployment/customer-api | grep health

# Alloy 필터 통계 확인
kubectl exec -it -n monitoring daemonset/alloy -- \
  wget -qO- http://localhost:12345/metrics | grep loki_process_dropped

# ConfigMap 다시 확인
kubectl describe configmap -n monitoring alloy-config
```

### 정상 로그까지 드롭될 때
```bash
# 필터 정규식 테스트
# regex101.com 에서 테스트

# Alloy 로그에서 드롭 이유 확인
kubectl logs -n monitoring daemonset/alloy | grep "drop_counter_reason"
```

## 📚 참고 자료

- [Grafana Alloy - Processing Logs](https://grafana.com/docs/alloy/latest/reference/components/loki.process/)
- [Loki LogQL](https://grafana.com/docs/loki/latest/logql/)
- [정규표현식 테스트](https://regex101.com/)

