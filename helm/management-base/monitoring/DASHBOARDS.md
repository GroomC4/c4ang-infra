# 📊 E-Commerce Grafana 대시보드 가이드

## 개요

이 문서는 E-Commerce 마이크로서비스를 위한 프로덕션 레벨 Grafana 대시보드 사용 가이드입니다.

## 🎯 대시보드 목록

### 1. **E-Commerce: Production Overview** 🎯
- **UID**: `ecommerce-overview-v2`
- **용도**: 전체 시스템 상태를 한눈에 파악
- **주요 기능**:
  - 시스템 헬스 요약 (Running Pods, Total Errors, 5xx Errors, Restarts)
  - 서비스별 로그 수집 현황
  - 실시간 에러율 추이
  - 5xx 에러 상세 로그 및 서비스별 분포
  - 애플리케이션 로그 레벨별 분포
  - 서비스별 에러 통계 테이블

### 2. **E-Commerce: Service Detail** 📊
- **UID**: `ecommerce-service-detail-v2`
- **용도**: 특정 서비스의 상세 분석
- **주요 기능**:
  - **RED Metrics** (Rate, Errors, Duration)
    - Request Rate: 초당 요청 수 (2xx, 4xx, 5xx 분류)
    - Error Rate: 에러율 추이 (%)
    - Duration: 서비스 부하 (CPU 기반 추정)
  - Top 10 에러 메시지 테이블
  - 최근 에러 로그 스트림
  - HTTP 상태 코드 분포 (시계열 + 도넛 차트)
  - 모든 애플리케이션 로그 (헬스체크 제외)

### 3. **E-Commerce: Resources & Nodes** 🖥️ ⭐NEW
- **UID**: `ecommerce-resources-v1`
- **용도**: 클러스터 및 노드 리소스 모니터링
- **주요 기능**:
  - **Cluster Overview**
    - 전체 노드 수, CPU/Memory 사용률 (Gauge)
    - Pod 상태 분포 (Donut Chart)
    - 네트워크 I/O 추이
  - **Node Resources**
    - 노드별 CPU 사용률 히트맵 (Heatmap)
    - 노드별 메모리 사용률 히트맵 (Heatmap)
    - 노드별 리소스 상세 테이블 (CPU/Memory/Disk/Pods)
  - **E-Commerce Pod Resources**
    - 서비스별 CPU 사용량 (Time Series)
    - 서비스별 메모리 사용량 (Time Series)
    - Pod별 리소스 사용 현황 및 제한 (Gauge Table)
    - Pod 재시작 횟수

### 4. **E-Commerce: Logs Visual** 📝 ⭐NEW
- **UID**: `ecommerce-logs-visual-v1`
- **용도**: 시각적으로 개선된 로그 모니터링
- **주요 기능**:
  - **Log Analytics Overview**
    - 시간대별 로그 볼륨 히트맵 (Heatmap)
    - 로그 레벨 분포 (Donut Chart)
  - **Error Analysis**
    - 5xx 에러 시계열 (Bar Chart)
    - 에러 로그 통계 테이블 (Color Background)
  - **Log Streams**
    - 5xx 에러 로그 스트림
    - 전체 에러 로그 스트림 (ERROR, Exception, Fatal)
  - **Application Logs**
    - 로그 레벨별 실시간 추이 (Stacked Area)
    - 애플리케이션 로그 (헬스체크 제외)
    - 로그 레벨 필터 (ERROR, WARN, INFO)

### 5. **Redis Cache Overview** 🟥 ⭐NEW
- **UID**: `redis-cache-overview`
- **용도**: `cache-tier` 네임스페이스 Redis 클러스터 상태 모니터링
- **주요 기능**:
  - 연결 클라이언트, OPS, 메모리 사용량, 캐시 Hit Rate 실시간 스탯
  - Pod별 메모리 / OPS 추이
  - DB별 키/만료 분포 & Hits vs Misses 추세
  - 복제 상태(connected slaves, repl offset) 시각화
  - Exporter 및 Redis Pod 헬스 모니터링 테이블

## 🔧 로그 필터링 설정

### Alloy 로그 수집 정책

#### ✅ **수집되는 로그**
1. **5xx 에러는 무조건 수집**
   ```
   status=500, status=502, HTTP/1.1 500, 등
   ```

2. **애플리케이션 로그**
   - ERROR, WARN, INFO 레벨
   - 비즈니스 로직 로그
   - 예외 및 스택 트레이스

#### ❌ **필터링되는 로그** (수집 안됨)
1. **헬스체크 로그 (200 OK)**
   ```
   GET /health ... 200 OK
   GET /healthz ... 200
   POST /livez ... 200
   GET /readyz ... 200
   GET /ping ... 200
   ```

2. **Istio 프록시 헬스체크**
   ```
   envoy ... health ... 200
   ```

### 필터링 동작 순서
```
1. ecommerce 네임스페이스 로그 수집
2. 5xx 에러 체크 → 있으면 무조건 수집
3. 헬스체크 로그 (200 OK) → 드롭
4. Istio 프록시 헬스체크 → 드롭
5. 나머지 로그 → 수집
```

## 📈 대시보드 사용 가이드

### Production Overview 대시보드

#### 1️⃣ **System Health Overview 섹션**
**목적**: 시스템 전반의 상태를 빠르게 파악

- **Running Pods**: 실행 중인 Pod 수
  - 🟢 6개 이상: 정상
  - 🟡 1-5개: 일부 서비스 다운
  - 🔴 0개: 전체 서비스 다운

- **Total Errors (5m)**: 최근 5분간 전체 에러 수
  - 🟢 0-9: 정상
  - 🟡 10-49: 주의
  - 🔴 50+: 심각

- **5xx Errors (5m)**: 최근 5분간 서버 에러
  - 🟢 0: 정상
  - 🟠 1-9: 주의
  - 🔴 10+: 심각

- **Log Volume by Service**: 서비스별 로그 수집 비율
  - 모든 서비스가 균등하게 표시되는지 확인
  - 특정 서비스만 없다면 로그 수집 문제

#### 2️⃣ **Critical Errors - 5xx HTTP Status 섹션**
**목적**: 서버 에러 즉시 파악 및 대응

- **5xx Errors by Service**: 서비스별 5xx 에러 발생 추이
  - 어떤 서비스에서 에러가 발생하는지 식별
  - 에러 급증 시점 파악

- **🔴 5xx Error Logs**: 실시간 5xx 에러 로그
  - 에러 메시지, 스택 트레이스 확인
  - 근본 원인 분석

#### 3️⃣ **Application Logs 섹션**
**목적**: 애플리케이션 로그 레벨별 모니터링

- **Log Levels by Service**: ERROR, WARN, INFO 로그 추이
  - 🔴 ERROR: 즉시 대응 필요
  - 🟡 WARN: 주의 필요
  - 🔵 INFO: 정상 작동

- **Application Logs**: 선택한 서비스의 최근 로그
  - Service 변수로 필터링 가능
  - 헬스체크 로그는 자동 제외

#### 4️⃣ **Service Details 섹션**
**목적**: 서비스별 통계 테이블

- **Service Error Statistics**: 서비스별 에러 통계
  - Total Logs: 총 로그 수
  - Errors: 전체 에러 수
  - 5xx Errors: 서버 에러 수 (가장 중요)

### Service Detail 대시보드

#### 1️⃣ **RED Metrics 섹션**
**목적**: 서비스 성능 및 안정성 모니터링 (Google SRE 베스트 프랙티스)

- **Request Rate (Rate)**: 초당 요청 수
  - Total Requests: 전체 요청
  - 2xx Success: 성공 응답
  - 4xx Client Errors: 클라이언트 에러
  - 5xx Server Errors: 서버 에러

- **Error Rate (Errors)**: 에러율 (%)
  - Error Rate %: 전체 에러율
  - 5xx Error Rate %: 서버 에러율
  - 🟢 0-1%: 정상
  - 🟡 1-5%: 주의
  - 🟠 5-10%: 경고
  - 🔴 10%+: 심각

- **Service Load (Duration proxy)**: 서비스 부하
  - CPU 사용률 기반 추정
  - 응답 시간 추이 파악 가능

#### 2️⃣ **Top Errors & Exceptions 섹션**
**목적**: 가장 빈번한 에러 식별 및 우선순위 결정

- **Top 10 Error Messages**: 가장 많이 발생한 에러 메시지
  - 에러 메시지별 발생 횟수 정렬
  - 반복되는 에러 패턴 파악
  - 수정 우선순위 결정

- **Recent Error Logs**: 최근 에러 로그 스트림
  - 실시간 에러 모니터링
  - 상세 로그 확인

#### 3️⃣ **HTTP Status Code Distribution 섹션**
**목적**: HTTP 응답 상태 분석

- **HTTP Status Codes Over Time**: 시계열 그래프
  - 2xx (🟢): 성공 응답
  - 4xx (🟡): 클라이언트 에러 (잘못된 요청, 인증 실패 등)
  - 5xx (🔴): 서버 에러 (내부 오류, 타임아웃 등)

- **Status Code Distribution**: 도넛 차트
  - 전체 기간 동안의 상태 코드 비율
  - 정상 서비스는 2xx가 95% 이상

#### 4️⃣ **All Application Logs 섹션**
**목적**: 전체 애플리케이션 로그 확인

- 헬스체크, ping 로그는 자동 제외
- 시간대별 로그 검색 가능
- 로그 상세 정보 확인 가능

## 🎨 대시보드 변수 사용

### Service 변수
- **위치**: 대시보드 상단
- **기능**: 특정 서비스만 필터링
- **사용 방법**:
  1. 드롭다운에서 서비스 선택
     - customer
     - order
     - payment
     - product
     - recommendation
     - saga
  2. 모든 패널이 선택한 서비스만 표시

## 🚨 알림 설정 (향후)

현재는 `alerting.enabled: false`로 비활성화되어 있습니다.

알림을 활성화하려면:
```yaml
# values-eks-s3.yaml
alerting:
  enabled: true
```

## 🔍 문제 해결 (Troubleshooting)

### 대시보드가 보이지 않을 때
```bash
# 대시보드 ConfigMap 확인
kubectl get configmap -n monitoring | grep dashboard

# Grafana Pod 재시작
kubectl rollout restart deployment/grafana -n monitoring

# Grafana 로그 확인
kubectl logs -n monitoring deployment/grafana -f
```

### 데이터가 표시되지 않을 때
```bash
# Loki 데이터 확인
kubectl exec -it -n monitoring deployment/loki -- \
  wget -qO- 'http://localhost:3100/loki/api/v1/label/__name__/values'

# Alloy 로그 수집 확인
kubectl logs -n monitoring daemonset/alloy -f

# Prometheus 메트릭 확인
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# 브라우저에서 http://localhost:9090
```

### 5xx 에러가 수집되지 않을 때
```bash
# Alloy ConfigMap 확인
kubectl get configmap -n monitoring alloy-config -o yaml

# 테스트 로그 생성
kubectl exec -it -n ecommerce deployment/customer-api -- \
  curl -X GET http://localhost:8080/api/test-500

# Loki 쿼리로 확인
# Grafana Explore → Loki 선택
# Query: {namespace="ecommerce"} |~ "(?i)(status[=:\\s]*(5[0-9]{2})|HTTP/[0-9.]* 5[0-9]{2})"
```

## 📚 참고 자료

- [Grafana Loki 공식 문서](https://grafana.com/docs/loki/latest/)
- [RED Method (Rancher)](https://www.weave.works/blog/the-red-method-key-metrics-for-microservices-architecture/)
- [Google SRE Book - Monitoring](https://sre.google/sre-book/monitoring-distributed-systems/)
- [Grafana Best Practices](https://grafana.com/docs/grafana/latest/best-practices/)

## 📞 지원

문제가 발생하면:
1. 위 문제 해결 섹션 참고
2. Grafana UI에서 Query Inspector 사용
3. Loki/Prometheus 로그 확인
