# Kafka 브로커 장애 테스트 - 처음부터 실행 가이드

## 목적
브로커에 부하를 주어 강제 삭제하고, 자동 재생되는지 확인하며 Producer/Consumer 자동 재연결을 검증합니다.

## 사전 준비

### 1. Kotlin 설치 확인
```bash
kotlinc -version
```

설치되어 있지 않다면:
```bash
brew install kotlin
```

### 2. k3d 클러스터 및 Kafka 상태 확인
```bash
cd /Users/sanga/Desktop/c4/code/c4ang-infra/environments/local
export KUBECONFIG=$(pwd)/kubeconfig/config

# 클러스터 상태 확인
kubectl get nodes

# Kafka 브로커 상태 확인
kubectl get pods -n kafka -l strimzi.io/cluster=c4-kafka

# 토픽 확인
kubectl get kafkatopic broker-failure-test -n kafka
```

토픽이 없으면 생성:
```bash
kubectl apply -f - <<EOF
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaTopic
metadata:
  name: broker-failure-test
  namespace: kafka
  labels:
    strimzi.io/cluster: c4-kafka
spec:
  partitions: 1
  replicas: 1
  config:
    retention.ms: 3600000
EOF
```

## 실행 순서

### 0단계: Kafka 포트 포워딩 (터미널 0) - 필수!

로컬에서 실행하기 위해 Kafka 서비스를 포트 포워딩해야 합니다.

```bash
cd /Users/sanga/Desktop/c4/code/c4ang-infra/environments/local
export KUBECONFIG=$(pwd)/kubeconfig/config

# 방법 1: 전용 스크립트 사용
cd scripts/kafka-broker-failure-test
./start-kafka-port-forward.sh

# 방법 2: 직접 실행
kubectl port-forward -n kafka svc/c4-kafka-kafka-bootstrap 9092:9092

# 방법 3: 백그라운드 실행
kubectl port-forward -n kafka svc/c4-kafka-kafka-bootstrap 9092:9092 > /tmp/kafka-port-forward.log 2>&1 &
echo $! > /tmp/kafka-port-forward.pid
```

**중요:** 이 포트 포워딩은 Consumer와 Producer 실행 중 계속 유지되어야 합니다!

### 1단계: Consumer 실행 (터미널 1)

```bash
cd /Users/sanga/Desktop/c4/code/c4ang-infra/environments/local/scripts/kafka-broker-failure-test
./run-consumer.sh
```

**예상 출력:**
```
==========================================
Kafka Test Consumer
==========================================
Bootstrap Servers: c4-kafka-kafka-bootstrap.kafka:9092
Topic: broker-failure-test
Consumer Group: broker-failure-test-group
Report Interval: 5s
==========================================

✅ Topic 'broker-failure-test' exists

Starting consumer...
Press Ctrl+C to stop

[2025-12-01 14:50:00.000] [CONSUMER] 🚀 Starting Kafka Test Consumer
[2025-12-01 14:50:00.001] [CONSUMER] ✅ Subscribed to topic: broker-failure-test
[2025-12-01 14:50:05.000] [CONSUMER] 📊 STATUS REPORT
[2025-12-01 14:50:05.001] [CONSUMER]   Expected Next ID: 1
[2025-12-01 14:50:05.002] [CONSUMER]   Received: 0
...
```

**확인 사항:**
- ✅ "Starting Kafka Test Consumer" 메시지 확인
- ✅ "Subscribed to topic" 메시지 확인
- ✅ 5초마다 상태 리포트 출력

### 2단계: Producer 실행 (터미널 2)

```bash
cd /Users/sanga/Desktop/c4/code/c4ang-infra/environments/local/scripts/kafka-broker-failure-test

# 기본 속도 (1초 간격 = 초당 1개)
./run-producer.sh

# 부하 증가 (0.1초 간격 = 초당 10개)
MESSAGE_INTERVAL_MS=100 ./run-producer.sh

# 더 큰 부하 (0.05초 간격 = 초당 20개)
MESSAGE_INTERVAL_MS=50 ./run-producer.sh
```

**예상 출력:**
```
==========================================
Kafka Test Producer
==========================================
Bootstrap Servers: c4-kafka-kafka-bootstrap.kafka:9092
Topic: broker-failure-test
Message Interval: 1000ms
Max Retries: 5
==========================================

✅ Topic 'broker-failure-test' exists

Starting producer...
Press Ctrl+C to stop

[2025-12-01 14:50:10.000] [PRODUCER] 🚀 Starting Kafka Test Producer
[2025-12-01 14:50:11.000] [PRODUCER] ✅ Sent message #1 -> partition=0, offset=0
[2025-12-01 14:50:12.000] [PRODUCER] ✅ Sent message #2 -> partition=0, offset=1
...
```

**확인 사항:**
- ✅ "Starting Kafka Test Producer" 메시지 확인
- ✅ "Sent message #1, #2, #3..." 메시지 확인
- ✅ Consumer 터미널에서 메시지 수신 확인

### 3단계: Grafana 대시보드 준비 (터미널 3)

```bash
cd /Users/sanga/Desktop/c4/code/c4ang-infra/environments/local
export KUBECONFIG=$(pwd)/kubeconfig/config
kubectl port-forward -n monitoring svc/grafana 3000:3000
```

**브라우저에서:**
1. http://localhost:3000 접속
2. 로그인: `admin` / `admin`
3. **Dashboards** 메뉴 클릭
4. **Kafka Broker Failure Test Dashboard** 선택

**확인할 지표:**
- Broker Status (Up/Down)
- Messages In/sec (시간별 그래프)
- Consumer Lag (시간별 그래프 + 현재 값)

### 4단계: 정상 동작 확인 (30초~1분 대기)

**확인 사항:**
- ✅ Producer가 메시지를 계속 전송하는지
- ✅ Consumer가 메시지를 계속 수신하는지
- ✅ ID 연속성이 유지되는지 (Gap 없음)
- ✅ Grafana 대시보드에서 Messages In/sec가 정상인지
- ✅ Consumer Lag이 0에 가까운지

### 5단계: 브로커 강제 삭제 (터미널 4)

```bash
cd /Users/sanga/Desktop/c4/code/c4ang-infra/environments/local
export KUBECONFIG=$(pwd)/kubeconfig/config

# 브로커 파드 확인
kubectl get pods -n kafka -l strimzi.io/cluster=c4-kafka

# 브로커 강제 삭제
kubectl delete pod -n kafka $(kubectl get pods -n kafka -l strimzi.io/cluster=c4-kafka -o jsonpath='{.items[0].metadata.name}') --force --grace-period=0

# 브로커 재기동 관찰
watch -n 1 kubectl get pods -n kafka -l strimzi.io/cluster=c4-kafka
```

**예상 동작:**
1. 브로커 파드가 `Terminating` 상태로 변경
2. Strimzi Operator가 새 파드 생성 시작
3. 새 파드가 `Running` 상태로 전환 (약 30초~1분)

### 6단계: 관찰 (모든 터미널 + Grafana)

#### Producer 로그 (터미널 2)에서 확인:
- ❌ 브로커 삭제 시: `FAILED to send message` 에러 발생
- ⏳ 자동 재시도: 계속 재시도 시도
- ✅ 브로커 재기동 후: `Sent message` 정상 전송 재개

**예상 로그:**
```
[14:01:00.000] [PRODUCER] ✅ Sent message #60 -> partition=0, offset=59
[14:01:01.000] [PRODUCER] ❌ FAILED to send message #61: Connection refused
[14:01:02.000] [PRODUCER] ❌ FAILED to send message #61: Connection refused
[14:01:03.000] [PRODUCER] ❌ FAILED to send message #61: Connection refused
[14:01:30.000] [PRODUCER] ✅ Sent message #61 -> partition=0, offset=60
[14:01:31.000] [PRODUCER] ✅ Sent message #62 -> partition=0, offset=61
```

#### Consumer 로그 (터미널 1)에서 확인:
- ⏳ 브로커 삭제 시: 메시지 읽기 중단 또는 에러
- ✅ 브로커 재기동 후: 메시지 읽기 재개
- ⚠️ Gap 체크: ID 연속성 확인

**예상 로그:**
```
[14:00:59.000] [CONSUMER] 📨 Received message #59 -> partition=0, offset=58
[14:01:00.000] [CONSUMER] ⏳ No messages received for 5.0s...
[14:01:00.000] [CONSUMER] ❌ Error polling messages: Connection refused
[14:01:30.000] [CONSUMER] 📨 Received message #60 -> partition=0, offset=59
[14:01:31.000] [CONSUMER] 📨 Received message #61 -> partition=0, offset=60
```

#### Grafana 대시보드에서 확인:

**1. Broker Status:**
- 정상: `Up` (녹색)
- 브로커 삭제 시: `Down` (빨간색) 또는 사라짐
- 재기동 후: `Up` (녹색)으로 복구

**2. Messages In/sec:**
- 정상: 일정한 값 (예: 1.0 msg/sec)
- 브로커 삭제 시: 0으로 떨어짐
- 재기동 후: 정상 값으로 복구

**3. Consumer Lag:**
- 정상: 0에 가까움
- 브로커 삭제 시: 증가 시작
- 재기동 후: 감소하여 0으로 수렴

### 7단계: 메시지 유실/중복 검증

#### Consumer 로그에서 최종 확인:
Consumer 터미널에서 5초마다 출력되는 상태 리포트 확인:

**검증 기준:**
- ✅ **메시지 유실 없음**: Gap Count = 0
- ✅ **메시지 중복 없음**: Duplicate Count = 0
- ✅ **ID 연속성**: Expected Next ID = 마지막 수신 ID + 1

**예상 최종 리포트:**
```
[14:05:00.000] [CONSUMER] 📊 STATUS REPORT
[14:05:00.001] [CONSUMER]   Expected Next ID: 301
[14:05:00.002] [CONSUMER]   Received: 300
[14:05:00.003] [CONSUMER]   Duplicates: 0
[14:05:00.004] [CONSUMER]   Gaps: 0
[14:05:00.005] [CONSUMER]   Gap Count: 0 messages
[14:05:00.006] [CONSUMER]   Duplicate Rate: 0.00%
```

### 8단계: 테스트 종료

```bash
# Producer 중지: 터미널 2에서 Ctrl+C
# Consumer 중지: 터미널 1에서 Ctrl+C
# Grafana 포트 포워딩 중지: 터미널 3에서 Ctrl+C
# 브로커 모니터링 중지: 터미널 4에서 Ctrl+C
```

## 예상 결과

### ✅ 정상 동작 시:
- Producer: 브로커 재기동 후 자동 재연결 및 전송 재개
- Consumer: 브로커 재기동 후 자동 재연결 및 수신 재개
- 메시지 유실 없음: Gap Count = 0
- 메시지 중복 없음: Duplicate Count = 0
- Grafana 대시보드: 모든 지표가 정상으로 복구

### ❌ 문제 발생 시:
- 메시지 유실: Consumer 로그에서 Gap 발견
- 메시지 중복: Consumer 로그에서 Duplicate 발견
- Producer 재연결 실패: 계속된 에러 로그
- Consumer 재연결 실패: 계속된 에러 로그

## 트러블슈팅

### Consumer가 메시지를 읽지 못하는 경우:
1. Consumer Group이 올바르게 설정되었는지 확인
2. 토픽이 존재하는지 확인: `kubectl get kafkatopic -n kafka`
3. Kafka Exporter가 정상 작동하는지 확인

### Producer가 메시지를 보내지 못하는 경우:
1. 브로커가 정상 작동하는지 확인: `kubectl get pods -n kafka`
2. 네트워크 연결 확인
3. Kafka 클러스터 상태 확인: `kubectl get kafka -n kafka`

### 의존성 다운로드 실패:
```bash
cd /Users/sanga/Desktop/c4/code/c4ang-infra/environments/local/scripts/kafka-broker-failure-test
rm -rf lib
./download-deps.sh
```

## 빠른 참조

### 필요한 4개 터미널:
1. **터미널 1**: Consumer 실행
2. **터미널 2**: Producer 실행
3. **터미널 3**: Grafana 포트 포워딩
4. **터미널 4**: 브로커 삭제 및 모니터링

### 핵심 명령어:
```bash
# Consumer 실행
cd /Users/sanga/Desktop/c4/code/c4ang-infra/environments/local/scripts/kafka-broker-failure-test
./run-consumer.sh

# Producer 실행 (부하 증가)
MESSAGE_INTERVAL_MS=100 ./run-producer.sh

# Grafana 포트 포워딩
kubectl port-forward -n monitoring svc/grafana 3000:3000

# 브로커 강제 삭제
kubectl delete pod -n kafka $(kubectl get pods -n kafka -l strimzi.io/cluster=c4-kafka -o jsonpath='{.items[0].metadata.name}') --force --grace-period=0
```

