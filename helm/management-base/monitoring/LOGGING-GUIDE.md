# MSA 도메인 서비스 로그 수집 가이드

## 개요
이 문서는 Kubernetes 환경에서 MSA 도메인 서비스들의 로그를 Grafana Alloy를 통해 수집하고 Loki에 저장하여 Grafana에서 조회하는 방법을 설명합니다.

## 아키텍처

```
[Domain Services] --> [Alloy DaemonSet] --> [Loki] --> [Grafana]
                           |
                           v
                     [Prometheus]
```

## 구성 요소

### 1. Grafana Alloy
- **역할**: 로그, 메트릭, 트레이스 통합 수집 에이전트
- **배포 방식**: DaemonSet (각 노드에 하나씩 배포)
- **기능**:
  - 컨테이너 로그 수집
  - Spring Boot 로그 패턴 파싱
  - 민감한 정보 마스킹
  - Loki로 로그 전송

### 2. Loki
- **역할**: 로그 저장소
- **특징**:
  - 로그 인덱싱 및 쿼리
  - 90일 보존 정책
  - 라벨 기반 검색

### 3. Grafana
- **역할**: 로그 시각화 및 대시보드
- **대시보드**:
  - Domain Services Monitoring
  - 서비스별 로그 조회
  - 에러 추적
  - CPU 사용률 모니터링

## 배포 방법

### 1. 모니터링 스택 배포

```bash
# monitoring 네임스페이스 생성
kubectl create namespace monitoring

# Helm으로 모니터링 스택 배포
cd helm/management-base/monitoring
helm install monitoring . -n monitoring

# 배포 확인
kubectl get pods -n monitoring
```

### 2. 도메인 서비스 배포

각 도메인 서비스는 다음 레이블과 어노테이션이 자동으로 추가됩니다:

```yaml
metadata:
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "8080"
    prometheus.io/path: "/actuator/prometheus"
  labels:
    app: <service-name>
    environment: prod
    team: ecommerce
    component: backend
```

```bash
# ecommerce 네임스페이스 생성
kubectl create namespace ecommerce

# 도메인 서비스 배포
cd helm/services
for service in customer-service order-service payment-service product-service recommendation-service saga-tracker; do
  helm install $service ./$service -n ecommerce
done
```

### 3. Grafana 접속

```bash
# Grafana 포트 포워딩
kubectl port-forward -n monitoring svc/grafana 3000:3000

# 브라우저에서 접속
# URL: http://localhost:3000
# ID: admin
# PW: admin (초기 비밀번호, 변경 필요)
```

## 로그 수집 설정 상세

### Alloy 설정 구조

1. **일반 파드 로그 수집**
   - 모든 네임스페이스의 파드 로그 수집
   - 기본 JSON 파싱

2. **도메인 서비스 전용 파이프라인**
   - ecommerce 네임스페이스의 특정 서비스만 필터링
   - Spring Boot 로그 패턴 파싱
   - 추가 메타데이터 수집 (trace_id, span_id 등)

### 수집되는 레이블

- `namespace`: 네임스페이스
- `service`: 서비스 이름
- `pod`: 파드 이름
- `container`: 컨테이너 이름
- `node`: 노드 이름
- `level`: 로그 레벨 (INFO, WARN, ERROR, DEBUG)
- `environment`: 환경 (prod, dev, test)
- `version`: 서비스 버전
- `trace_id`: 분산 추적 ID
- `span_id`: 스팬 ID

## 로그 조회

### LogQL 쿼리 예시

```logql
# 특정 서비스의 모든 로그
{namespace="ecommerce", service="customer-api"}

# ERROR 레벨 로그만 조회
{namespace="ecommerce", level="ERROR"}

# 특정 서비스의 ERROR 로그
{namespace="ecommerce", service="order-api", level="ERROR"}

# 특정 텍스트 포함 로그 검색
{namespace="ecommerce"} |= "Exception"

# JSON 필드 추출
{namespace="ecommerce"} | json | userId="user123"

# 로그 레이트 계산
rate({namespace="ecommerce", service="payment-api"}[5m])
```

### Grafana 대시보드 활용

1. **Domain Services Monitoring** 대시보드 접속
2. 변수 선택:
   - `Service`: 조회할 서비스 선택
   - `Log Level`: 로그 레벨 필터링
3. 시간 범위 조정
4. 패널별 기능:
   - Logs per Service: 서비스별 로그 발생량
   - Error Count by Service: 서비스별 에러 수
   - Service Logs: 실시간 로그 스트림
   - Top Errors: 자주 발생하는 에러
   - CPU Usage by Pod: 파드별 CPU 사용률

## 트러블슈팅

### 로그가 수집되지 않는 경우

1. Alloy DaemonSet 상태 확인:
```bash
kubectl get ds -n monitoring alloy
kubectl logs -n monitoring -l app=alloy
```

2. 서비스 레이블 확인:
```bash
kubectl get pods -n ecommerce --show-labels
```

3. Loki 연결 확인:
```bash
kubectl logs -n monitoring -l app=loki
```

### 로그 파싱이 제대로 되지 않는 경우

1. 로그 포맷 확인
2. Alloy ConfigMap의 파싱 규칙 검토
3. 필요시 정규식 패턴 수정

## 모니터링 모범 사례

1. **구조화된 로그 사용**
   - JSON 형식 로그 출력
   - 일관된 필드 사용

2. **적절한 로그 레벨 설정**
   - Production: INFO 이상
   - Development: DEBUG 포함

3. **메타데이터 포함**
   - 트랜잭션 ID
   - 사용자 ID
   - 요청 ID

4. **민감한 정보 제외**
   - 비밀번호, 토큰 등 마스킹
   - 개인정보 로깅 금지

5. **로그 보존 정책**
   - 90일 기본 보존
   - 중요 로그는 별도 백업

## 추가 설정

### 알림 설정

values.yaml에서 알림 설정 활성화:

```yaml
alerting:
  enabled: true
  slack:
    enabled: true
    webhookUrl: "YOUR_SLACK_WEBHOOK_URL"
    channel: "#alerts"
```

### 외부 접근 설정

Ingress 설정 활성화:

```yaml
ingress:
  enabled: true
  className: "nginx"
  grafana:
    host: "grafana.your-domain.com"
    tls:
      enabled: true
      secretName: "grafana-tls"
```

## 참고 자료

- [Grafana Alloy Documentation](https://grafana.com/docs/alloy/)
- [Loki Documentation](https://grafana.com/docs/loki/)
- [LogQL Query Language](https://grafana.com/docs/loki/latest/logql/)
- [Grafana Dashboard Documentation](https://grafana.com/docs/grafana/)