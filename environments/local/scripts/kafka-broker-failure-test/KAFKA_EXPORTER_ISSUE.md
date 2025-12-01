# Kafka Exporter 연결 문제 분석

## 현재 상황

### ✅ 정상 작동 중인 부분
- **Producer**: 정상 작동 중 (메시지 전송 성공)
- **Consumer**: 정상 작동 중 (메시지 수신 성공)
- **포트 포워딩**: 정상 작동 중 (localhost:9092, 9093, 9094)
- **Kafka 클러스터**: 정상 작동 중 (브로커 0, 1, 2 모두 Running)

### ❌ 문제가 있는 부분
- **Kafka Exporter**: 연결 실패로 인해 메트릭 수집 불가
- **Grafana 대시보드**: Kafka Exporter 메트릭이 없어서 데이터 표시 안됨

## 문제 증상

### Kafka Exporter 로그 에러
```
Error Init Kafka Client: kafka: client has run out of available brokers to talk to: 
dial tcp: address c4-kafka-dual-role-0.c4-kafka-kafka-brokers.kafka.svc.cluster.local:9092,c4-kafka-dual-role-1...: too many colons in address
```

또는

```
Cannot get consumer group: dial tcp [::1]:9092: connect: connection refused
Cannot get consumer group: dial tcp [::1]:9093: connect: connection refused
Cannot get consumer group: dial tcp [::1]:9094: connect: connection refused
```

## 핵심 문제

### 1. 브로커 advertised.listeners 설정 충돌
- **현재 설정**: 브로커의 `advertised.listeners`가 `localhost:9092`, `localhost:9093`, `localhost:9094`로 설정됨
- **문제**: Kafka Exporter가 클러스터 내부에서 실행되므로 `localhost`로는 연결할 수 없음
- **영향**: Kafka Exporter가 브로커로부터 받은 메타데이터에서 `localhost` 주소를 받아서 연결 실패

### 2. Kafka Exporter 인자 형식 문제
- **현재 설정**: `--kafka.server=서버1,서버2,서버3` (쉼표로 구분)
- **문제**: Kafka Exporter가 쉼표로 구분된 여러 서버를 인식하지 못함
- **해결 시도**: 여러 개의 `--kafka.server` 인자로 분리했지만 여전히 문제 발생 가능

## 관련 파일 목록

### 1. Kafka 클러스터 설정
**파일**: `c4ang-infra/charts/kafka-cluster/kafka-cluster.yaml`
- **라인**: 32-46
- **내용**: 브로커의 `advertised.listeners` 설정
- **현재 설정**:
  ```yaml
  configuration:
    brokers:
      - broker: 0
        advertisedHost: localhost
        advertisedPort: 9092
      - broker: 1
        advertisedHost: localhost
        advertisedPort: 9093
      - broker: 2
        advertisedHost: localhost
        advertisedPort: 9094
  ```

### 2. Kafka Exporter 배포 스크립트
**파일**: `c4ang-infra/environments/local/scripts/deploy-kafka-exporter.sh`
- **라인**: 75-81
- **내용**: Kafka Exporter의 `--kafka.server` 인자 설정
- **현재 설정**:
  ```bash
  args:
    - --kafka.server=c4-kafka-dual-role-0.c4-kafka-kafka-brokers.kafka.svc.cluster.local:9092
    - --kafka.server=c4-kafka-dual-role-1.c4-kafka-kafka-brokers.kafka.svc.cluster.local:9092
    - --kafka.server=c4-kafka-dual-role-2.c4-kafka-kafka-brokers.kafka.svc.cluster.local:9092
  ```

### 3. Producer 스크립트
**파일**: `c4ang-infra/environments/local/scripts/kafka-broker-failure-test/kafka-test-producer.py`
- **라인**: 15, 91-108
- **내용**: Producer의 bootstrap 서버 설정
- **현재 설정**: `BOOTSTRAP_SERVERS = 'localhost:9092,localhost:9093,localhost:9094'`

### 4. Consumer 스크립트
**파일**: `c4ang-infra/environments/local/scripts/kafka-broker-failure-test/kafka-test-consumer.py`
- **라인**: 16, 99-109
- **내용**: Consumer의 bootstrap 서버 설정
- **현재 설정**: `BOOTSTRAP_SERVERS = 'localhost:9092,localhost:9093,localhost:9094'`

### 5. Producer 실행 스크립트
**파일**: `c4ang-infra/environments/local/scripts/kafka-broker-failure-test/run-producer.sh`
- **라인**: 15-17
- **내용**: 환경 변수 설정
- **현재 설정**: `KAFKA_BOOTSTRAP_SERVERS="localhost:9092,localhost:9093,localhost:9094"`

### 6. Consumer 실행 스크립트
**파일**: `c4ang-infra/environments/local/scripts/kafka-broker-failure-test/run-consumer.sh`
- **라인**: 15-17
- **내용**: 환경 변수 설정
- **현재 설정**: `KAFKA_BOOTSTRAP_SERVERS="localhost:9092,localhost:9093,localhost:9094"`

### 7. 포트 포워딩 스크립트
**파일**: `c4ang-infra/environments/local/scripts/kafka-broker-failure-test/start-kafka-port-forward.sh`
- **라인**: 36-46
- **내용**: 각 브로커 Pod에 포트 포워딩 설정
- **현재 설정**: 
  - 브로커 0: `localhost:9092` → `c4-kafka-dual-role-0:9092`
  - 브로커 1: `localhost:9093` → `c4-kafka-dual-role-1:9092`
  - 브로커 2: `localhost:9094` → `c4-kafka-dual-role-2:9092`

## 기술적 배경

### Kafka advertised.listeners 동작 방식
1. 클라이언트가 bootstrap 서버에 연결
2. 브로커가 메타데이터를 반환할 때 `advertised.listeners`에 설정된 주소를 사용
3. 클라이언트는 반환된 주소로 리다이렉트되어 연결

### 문제의 핵심
- **Producer/Consumer**: 로컬에서 실행되므로 `localhost`로 advertised된 브로커에 연결 가능 (포트 포워딩 사용)
- **Kafka Exporter**: 클러스터 내부에서 실행되므로 `localhost`로 advertised된 브로커에 연결 불가능

## 해결 방안 고려사항

### 옵션 1: 브로커 advertised.listeners를 내부 서비스 이름으로 설정
- **장점**: Kafka Exporter 연결 가능
- **단점**: Producer/Consumer가 브로커로부터 받은 메타데이터에서 내부 서비스 이름을 받아서 연결 실패 가능

### 옵션 2: 브로커 advertised.listeners를 localhost로 유지하고 Kafka Exporter만 조정
- **장점**: Producer/Consumer는 정상 작동
- **단점**: Kafka Exporter가 브로커로부터 받은 메타데이터에서 localhost 주소를 받아서 연결 실패

### 옵션 3: 브로커 advertised.listeners를 이중으로 설정 (불가능)
- Strimzi에서는 브로커별로 하나의 advertised.listeners만 설정 가능

### 옵션 4: Kafka Exporter가 브로커 메타데이터를 무시하고 직접 연결
- Kafka Exporter의 `--kafka.server` 인자를 올바르게 설정하여 브로커 메타데이터를 무시하고 직접 연결

## 확인 필요 사항

1. Kafka Exporter가 브로커로부터 받은 메타데이터를 어떻게 처리하는지
2. Kafka Exporter의 `--kafka.server` 인자가 브로커 메타데이터를 무시하는지
3. 브로커의 advertised.listeners를 내부 서비스 이름으로 설정했을 때 Producer/Consumer 동작 여부

## 현재 브로커 설정 확인 명령어

```bash
# 브로커 0의 advertised.listeners 확인
kubectl exec -n kafka c4-kafka-dual-role-0 -- cat /tmp/strimzi.properties | grep "PLAIN-9092.*advertised"

# 브로커 2의 advertised.listeners 확인
kubectl exec -n kafka c4-kafka-dual-role-2 -- cat /tmp/strimzi.properties | grep "PLAIN-9092.*advertised"

# Kafka Exporter 로그 확인
kubectl logs -n kafka -l app=kafka-exporter --tail=50
```

## 현재 Kafka Exporter Deployment 설정 확인

```bash
kubectl get deployment kafka-exporter -n kafka -o yaml | grep -A 10 "args:"
```

