# Kafka Broker 장애 테스트 가이드

## 목적
Kafka 브로커가 강제로 삭제되고 자동 재기동될 때, Producer와 Consumer의 동작을 확인하고 메시지 유실/중복을 검증합니다.

## 테스트 시나리오

### 전체 흐름
1. **Consumer 실행**: 계속 메시지를 읽으면서 ID 연속성 체크 및 상태 출력
2. **Producer 실행**: 계속 메시지를 보내면서 에러 발생 시 자동 재시도
3. **Kafka 브로커 강제 삭제**: `kubectl delete pod`로 브로커 파드 삭제
4. **모니터링**: Grafana 대시보드에서 브로커 상태, 메시지, Lag 확인
5. **검증**: 메시지 유실/중복 여부 확인

## 실행 순서

### 1. 테스트 토픽 생성 (선택사항)
```bash
cd /Users/sanga/Desktop/c4/code/c4ang-infra/environments/local
export KUBECONFIG=$(pwd)/kubeconfig/config

# 테스트 토픽 생성
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
    retention.ms: 3600000  # 1시간
EOF
```

### 2. Consumer 실행 (터미널 1)
```bash
cd /Users/sanga/Desktop/c4/code/c4ang-infra/environments/local/scripts/kafka-broker-failure-test
./run-consumer.sh
```

Consumer는:
- 메시지를 계속 읽으면서 ID 연속성 체크
- Gap 발견 시 경고 출력
- 중복 메시지 발견 시 경고 출력
- 5초마다 상태 리포트 출력

### 3. Producer 실행 (터미널 2)
```bash
cd /Users/sanga/Desktop/c4/code/c4ang-infra/environments/local/scripts/kafka-broker-failure-test
./run-producer.sh
```

Producer는:
- 1초마다 순차적인 ID를 가진 메시지 전송
- 에러 발생 시 자동 재시도 (최대 5회)
- 전송 성공/실패 로그 출력

### 4. Grafana 대시보드 확인 (브라우저)
```bash
kubectl port-forward -n monitoring svc/grafana 3000:3000
```

브라우저에서 http://localhost:3000 접속 후:
- **Kafka Comprehensive Dashboard**: Broker 상태, Messages In/sec, Consumer Lag 확인
- **Kafka Consumer Lag Dashboard**: 실시간 Lag 모니터링

### 5. 브로커 강제 삭제 (터미널 3)
```bash
cd /Users/sanga/Desktop/c4/code/c4ang-infra/environments/local
export KUBECONFIG=$(pwd)/kubeconfig/config

# 브로커 파드 확인
kubectl get pods -n kafka -l strimzi.io/cluster=c4-kafka

# 브로커 강제 삭제
kubectl delete pod -n kafka <broker-pod-name> --force --grace-period=0

# 또는 모든 브로커 확인 후 하나 선택
kubectl get pods -n kafka | grep kafka-broker
```

### 6. 관찰 사항

#### Producer 로그에서 확인:
- 브로커 삭제 시 에러 발생 여부
- 자동 재시도 동작
- 브로커 재기동 후 정상 전송 재개

#### Consumer 로그에서 확인:
- 브로커 삭제 시 메시지 읽기 중단 여부
- 브로커 재기동 후 메시지 읽기 재개
- ID 연속성 (Gap 또는 중복)

#### Grafana 대시보드에서 확인:
- Broker Status: Down → Up 변화
- Messages In/sec: 일시적 중단 후 재개
- Consumer Lag: 증가 후 감소
- Under Replicated Partitions: 일시적 증가

### 7. 테스트 종료
```bash
# Producer 중지: Ctrl+C
# Consumer 중지: Ctrl+C

# 정리 (선택사항)
kubectl delete kafkatopic broker-failure-test -n kafka
```

## 예상 결과

### 정상 동작 시:
- ✅ Producer: 브로커 재기동 후 자동으로 재연결 및 메시지 전송 재개
- ✅ Consumer: 브로커 재기동 후 자동으로 재연결 및 메시지 읽기 재개
- ✅ 메시지 유실 없음: Consumer가 모든 메시지를 순차적으로 수신
- ✅ 메시지 중복 없음: 동일한 ID의 메시지가 중복 수신되지 않음

### 문제 발생 시:
- ❌ 메시지 유실: Consumer 로그에서 ID Gap 발견
- ❌ 메시지 중복: Consumer 로그에서 동일 ID 중복 발견
- ❌ Producer 재연결 실패: 계속된 에러 로그
- ❌ Consumer 재연결 실패: 계속된 에러 로그

## 트러블슈팅

### Consumer가 메시지를 읽지 못하는 경우:
1. Consumer Group이 올바르게 설정되었는지 확인
2. 토픽이 존재하는지 확인: `kubectl get kafkatopic -n kafka`
3. Kafka Exporter가 정상 작동하는지 확인: `kubectl get pods -n kafka | grep kafka-exporter`

### Producer가 메시지를 보내지 못하는 경우:
1. 브로커가 정상 작동하는지 확인: `kubectl get pods -n kafka`
2. 네트워크 연결 확인: `kubectl exec -it <producer-pod> -- ping c4-kafka-kafka-bootstrap.kafka`
3. Kafka 클러스터 상태 확인: `kubectl get kafka -n kafka`

