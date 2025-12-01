# Kafka Broker 장애 테스트 실행 순서

## 전체 시나리오 요약

```
1. Consumer 실행 → 메시지 읽기 시작
2. Producer 실행 → 메시지 전송 시작
3. 정상 동작 확인 (30초~1분)
4. Kafka 브로커 강제 삭제
5. 브로커 자동 재기동 관찰
6. Producer/Consumer 자동 재연결 확인
7. 메시지 유실/중복 검증
```

## 상세 실행 순서

### 0. 사전 준비

#### 0.1 환경 변수 설정
```bash
cd /Users/sanga/Desktop/c4/code/c4ang-infra/environments/local
export KUBECONFIG=$(pwd)/kubeconfig/config
```

#### 0.2 Grafana 대시보드 준비
```bash
# Grafana 포트 포워딩 (별도 터미널)
kubectl port-forward -n monitoring svc/grafana 3000:3000
```

브라우저에서 http://localhost:3000 접속:
- Kafka Comprehensive Dashboard 열기
- Kafka Consumer Lag Dashboard 열기

#### 0.3 Kafka 클러스터 상태 확인
```bash
kubectl get pods -n kafka
kubectl get kafka -n kafka
```

### 1. Consumer 실행 (터미널 1)

```bash
cd /Users/sanga/Desktop/c4/code/c4ang-infra/environments/local/scripts/kafka-broker-failure-test
./run-consumer.sh
```

**예상 출력:**
```
[2025-12-01 14:00:00.000] [CONSUMER] 🚀 Starting Kafka Test Consumer
[2025-12-01 14:00:00.001] [CONSUMER] ✅ Subscribed to topic: broker-failure-test
[2025-12-01 14:00:05.000] [CONSUMER] 📊 STATUS REPORT
[2025-12-01 14:00:05.001] [CONSUMER]   Expected Next ID: 1
[2025-12-01 14:00:05.002] [CONSUMER]   Received: 0
...
```

**Consumer는 다음을 수행합니다:**
- 메시지를 계속 읽으면서 ID 연속성 체크
- 5초마다 상태 리포트 출력
- Gap 또는 중복 발견 시 즉시 경고

### 2. Producer 실행 (터미널 2)

```bash
cd /Users/sanga/Desktop/c4/code/c4ang-infra/environments/local/scripts/kafka-broker-failure-test
./run-producer.sh
```

**예상 출력:**
```
[2025-12-01 14:00:10.000] [PRODUCER] 🚀 Starting Kafka Test Producer
[2025-12-01 14:00:11.000] [PRODUCER] ✅ Sent message #1 -> partition=0, offset=0
[2025-12-01 14:00:12.000] [PRODUCER] ✅ Sent message #2 -> partition=0, offset=1
...
```

**Producer는 다음을 수행합니다:**
- 1초마다 순차적인 ID를 가진 메시지 전송
- 에러 발생 시 자동 재시도 (최대 5회)
- 30초마다 상태 리포트 출력

### 3. 정상 동작 확인 (30초~1분 대기)

**확인 사항:**
- ✅ Producer가 메시지를 계속 전송하는지
- ✅ Consumer가 메시지를 계속 수신하는지
- ✅ ID 연속성이 유지되는지 (Gap 없음)
- ✅ Grafana 대시보드에서 Messages In/sec가 정상인지
- ✅ Consumer Lag이 0에 가까운지

### 4. Kafka 브로커 강제 삭제 (터미널 3)

```bash
cd /Users/sanga/Desktop/c4/code/c4ang-infra/environments/local
export KUBECONFIG=$(pwd)/kubeconfig/config

# 브로커 파드 확인
kubectl get pods -n kafka -l strimzi.io/cluster=c4-kafka

# 브로커 강제 삭제
BROKER_POD=$(kubectl get pods -n kafka -l strimzi.io/cluster=c4-kafka -o jsonpath='{.items[0].metadata.name}')
echo "Deleting broker pod: $BROKER_POD"
kubectl delete pod -n kafka "$BROKER_POD" --force --grace-period=0

# 브로커 재기동 관찰
watch -n 1 kubectl get pods -n kafka
```

**또는 간단하게:**
```bash
kubectl delete pod -n kafka $(kubectl get pods -n kafka -l strimzi.io/cluster=c4-kafka -o jsonpath='{.items[0].metadata.name}') --force --grace-period=0
```

### 5. 브로커 재기동 관찰

**터미널 3에서 확인:**
```bash
# 브로커 상태 모니터링
watch -n 1 kubectl get pods -n kafka

# 또는 상세 로그 확인
kubectl get pods -n kafka -l strimzi.io/cluster=c4-kafka
kubectl logs -n kafka <broker-pod-name> --tail=50 -f
```

**예상 동작:**
1. 브로커 파드가 `Terminating` 상태로 변경
2. Strimzi Operator가 새 파드 생성 시작
3. 새 파드가 `Running` 상태로 전환 (약 30초~1분)

### 6. Producer/Consumer 로그 관찰

#### Producer 로그에서 확인할 사항:
- ❌ 브로커 삭제 시: `FAILED to send message` 에러 발생
- ⏳ 재시도: 자동으로 재시도 시도
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

#### Consumer 로그에서 확인할 사항:
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

### 7. Grafana 대시보드 확인

**브라우저에서 확인할 사항:**

#### Kafka Comprehensive Dashboard:
1. **Broker Status**: 
   - 정상: `Up` (녹색)
   - 브로커 삭제 시: `Down` (빨간색)
   - 재기동 후: `Up` (녹색)으로 복구

2. **Messages In/sec**:
   - 정상: 일정한 값
   - 브로커 삭제 시: 0으로 떨어짐
   - 재기동 후: 정상 값으로 복구

3. **Consumer Lag**:
   - 정상: 0에 가까움
   - 브로커 삭제 시: 증가 시작
   - 재기동 후: 감소하여 0으로 수렴

4. **Under Replicated Partitions**:
   - 정상: 0
   - 브로커 삭제 시: 증가 (1)
   - 재기동 후: 0으로 복구

### 8. 메시지 유실/중복 검증

#### Consumer 로그에서 최종 확인:
```bash
# Consumer 터미널에서 최종 리포트 확인
# 또는 Ctrl+C로 종료 시 자동 리포트 출력
```

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

### 9. 테스트 종료

```bash
# Producer 중지: 터미널 2에서 Ctrl+C
# Consumer 중지: 터미널 1에서 Ctrl+C
# Grafana 포트 포워딩 중지: 해당 터미널에서 Ctrl+C
```

#### 정리 (선택사항):
```bash
# 테스트 토픽 삭제
kubectl delete kafkatopic broker-failure-test -n kafka

# Consumer Group 오프셋 리셋 (다음 테스트를 위해)
# 주의: 실제 운영 환경에서는 사용하지 마세요!
```

## 예상 결과 요약

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

### Kotlin 스크립트 실행 오류:
```bash
# Kotlin이 설치되어 있는지 확인
kotlin --version

# 없으면 설치 (macOS)
brew install kotlin

# 또는 직접 실행
kotlinc -script kafka-test-producer.kt
```

