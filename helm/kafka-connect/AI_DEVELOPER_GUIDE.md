# Kafka Connect S3 Sink Connector - AI 개발자 가이드

## 📋 목차
1. [개요](#개요)
2. [아키텍처 및 데이터 흐름](#아키텍처-및-데이터-흐름)
3. [데이터 저장 위치 및 형식](#데이터-저장-위치-및-형식)
4. [테스트 명령어](#테스트-명령어)
5. [설정 변경 방법](#설정-변경-방법)
6. [모니터링 및 확인](#모니터링-및-확인)
7. [문제 해결](#문제-해결)

---

## 개요

이 시스템은 **Kafka의 `tracking.log` 토픽**에서 메시지를 읽어서 **AWS S3 버킷(`c4-tracking-log`)**에 자동으로 저장하는 파이프라인입니다.

### 주요 구성 요소
- **Kafka Topic**: `tracking.log` (Kafka에 저장)
- **Kafka Connect**: Kafka 메시지를 S3로 전송하는 커넥터
- **S3 Sink Connector**: Confluent의 S3 Sink Connector 플러그인
- **S3 Bucket**: `c4-tracking-log` (최종 저장소)

---

## 아키텍처 및 데이터 흐름

```
애플리케이션 → Kafka Topic (tracking.log) → Kafka Connect → S3 Sink Connector → S3 Bucket (c4-tracking-log)
```

### 데이터 흐름 상세

1. **애플리케이션에서 메시지 발행**
   - Kafka의 `tracking.log` 토픽에 JSON 메시지 발행
   - Key: String 형식
   - Value: JSON 형식 (Schema 없음)

2. **Kafka Connect가 메시지 수집**
   - `tracking.log` 토픽에서 메시지를 읽음
   - `flushSize: 1` 설정으로 메시지 1개마다 즉시 S3에 저장

3. **S3에 저장**
   - S3 버킷: `c4-tracking-log`
   - 리전: `ap-northeast-2` (서울)
   - 파일 형식: JSON
   - 파일명: 자동 생성 (토픽명, 파티션, 오프셋 기반)

---

## 데이터 저장 위치 및 형식

### S3 버킷 정보

- **버킷 이름**: `c4-tracking-log`
- **리전**: `ap-northeast-2` (서울)
- **AWS 계정 ID**: `963403601423`

### S3 파일 경로 구조

S3 Sink Connector는 다음과 같은 경로 구조로 파일을 저장합니다:

```
s3://c4-tracking-log/
  └── topics/
      └── tracking.log/
          └── partition=0/
              └── tracking.log+0+0000000000.json
              └── tracking.log+0+0000000001.json
              └── ...
```

**파일명 형식**: `{topic}+{partition}+{offset}.json`

예시:
- `tracking.log+0+0000000000.json` (첫 번째 메시지)
- `tracking.log+0+0000000001.json` (두 번째 메시지)

### 데이터 형식

#### Kafka 메시지 형식

**Key**: String (예: `"user-123"` 또는 `null`)

**Value**: JSON 객체 (Schema 없음)

예시:
```json
{
  "userId": "user-123",
  "eventType": "page_view",
  "timestamp": "2024-01-15T10:30:00Z",
  "page": "/products/123",
  "userAgent": "Mozilla/5.0...",
  "ipAddress": "192.168.1.1"
}
```

#### S3 저장 파일 형식

각 JSON 파일은 **한 줄에 하나의 JSON 객체**로 저장됩니다 (JSON Lines 형식).

예시 (`tracking.log+0+0000000000.json`):
```json
{"userId":"user-123","eventType":"page_view","timestamp":"2024-01-15T10:30:00Z","page":"/products/123","userAgent":"Mozilla/5.0...","ipAddress":"192.168.1.1"}
```

**중요**: 
- 각 파일은 **한 줄에 하나의 JSON 객체**입니다
- 여러 메시지가 하나의 파일에 저장될 수 있습니다 (현재는 `flushSize: 1`로 1개씩 저장)
- 파일을 읽을 때는 **줄 단위로 파싱**해야 합니다

---

## 테스트 명령어

### 1. Kafka Topic 확인

```bash
# tracking.log 토픽이 존재하는지 확인
kubectl get kafkatopic tracking.log -n kafka

# 토픽 상세 정보 확인
kubectl describe kafkatopic tracking.log -n kafka
```

### 2. Kafka에 테스트 메시지 발행

```bash
# Kafka Client Pod에 접속
kubectl exec -it kafka-client -n kafka -- bash

# tracking.log 토픽에 메시지 발행
/opt/kafka/bin/kafka-console-producer.sh \
  --bootstrap-server c4-kafka-kafka-bootstrap.kafka:9092 \
  --topic tracking.log

# 메시지 입력 예시 (한 줄씩 입력):
{"userId":"user-123","eventType":"page_view","timestamp":"2024-01-15T10:30:00Z","page":"/products/123"}
{"userId":"user-456","eventType":"click","timestamp":"2024-01-15T10:31:00Z","element":"add-to-cart-button"}
```

### 3. Kafka에서 메시지 확인 (Consumer)

```bash
# Kafka Client Pod에서
/opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server c4-kafka-kafka-bootstrap.kafka:9092 \
  --topic tracking.log \
  --from-beginning
```

### 4. Kafka Connect 상태 확인

```bash
# Kafka Connect 파드 상태
kubectl get pods -n kafka -l strimzi.io/name=c4-kafka-connect-connect

# Kafka Connect 상태
kubectl get kafkaconnect -n kafka

# S3 Sink Connector 상태
kubectl get kafkaconnector s3-sink-connector -n kafka

# Connector 상세 정보
kubectl describe kafkaconnector s3-sink-connector -n kafka
```

### 5. Kafka Connect 로그 확인

```bash
# 최근 로그 확인
kubectl logs -n kafka -l strimzi.io/name=c4-kafka-connect-connect --tail=100

# 실시간 로그 확인
kubectl logs -n kafka -l strimzi.io/name=c4-kafka-connect-connect -f
```

### 6. S3에 저장된 파일 확인

```bash
# AWS CLI로 S3 파일 목록 확인
aws s3 ls s3://c4-tracking-log/topics/tracking.log/partition=0/ --recursive

# 특정 파일 다운로드
aws s3 cp s3://c4-tracking-log/topics/tracking.log/partition=0/tracking.log+0+0000000000.json ./test.json

# 파일 내용 확인
aws s3 cp s3://c4-tracking-log/topics/tracking.log/partition=0/tracking.log+0+0000000000.json - | cat

# 최근 파일 확인 (시간순 정렬)
aws s3 ls s3://c4-tracking-log/topics/tracking.log/partition=0/ --recursive | sort -k1,2
```

### 7. 전체 테스트 플로우

```bash
# 1. Kafka에 메시지 발행
kubectl exec -it kafka-client -n kafka -- \
  /opt/kafka/bin/kafka-console-producer.sh \
  --bootstrap-server c4-kafka-kafka-bootstrap.kafka:9092 \
  --topic tracking.log <<EOF
{"userId":"test-user","eventType":"test","timestamp":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","test":"true"}
EOF

# 2. 잠시 대기 (S3 저장까지 시간 필요)
sleep 10

# 3. S3에서 최신 파일 확인
aws s3 ls s3://c4-tracking-log/topics/tracking.log/partition=0/ --recursive | tail -1

# 4. 최신 파일 내용 확인
LATEST_FILE=$(aws s3 ls s3://c4-tracking-log/topics/tracking.log/partition=0/ --recursive | tail -1 | awk '{print $4}')
aws s3 cp s3://c4-tracking-log/$LATEST_FILE - | cat
```

---

## 설정 변경 방법

### 주요 설정 파일 위치

#### 1. Kafka Connect 설정: `helm/kafka-connect/values.yaml`

```yaml
connector:
  enabled: true
  name: s3-sink-connector
  config:
    # Kafka 토픽 이름 (변경 가능)
    topics: tracking.log
    
    # S3 버킷 이름 (변경 가능)
    s3BucketName: c4-tracking-log
    
    # S3 리전 (변경 가능)
    s3Region: ap-northeast-2
    
    # 파일 저장 빈도 (1 = 메시지 1개마다 저장)
    flushSize: 1
    
    # 파일 형식 (JSON, Avro 등)
    formatClass: io.confluent.connect.s3.format.json.JsonFormat
```

**변경 후 적용 방법:**
```bash
cd helm/kafka-connect
helm upgrade kafka-connect ./helm/kafka-connect -n kafka
```

#### 2. Kafka Topic 설정: `helm/kafka-topics/values.yaml`

```yaml
topics:
  - name: tracking.log
    partitions: 1        # 파티션 수 변경 가능
    retentionMs: 604800000  # 보관 기간 (밀리초, 7일)
```

**변경 후 적용 방법:**
```bash
helm upgrade kafka-topics ./helm/kafka-topics -n kafka
```

#### 3. IAM 정책: `helm/kafka-connect/s3-sink-policy.json`

S3 접근 권한을 변경하려면 이 파일을 수정한 후, AWS IAM 콘솔에서 수동으로 적용해야 합니다.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "S3WriteAccess",
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:AbortMultipartUpload",
        "s3:ListMultipartUploadParts"
      ],
      "Resource": "arn:aws:s3:::c4-tracking-log/*"
    }
  ]
}
```

### 자주 변경하는 설정

#### S3 저장 빈도 변경

`flushSize`를 변경하면 여러 메시지를 하나의 파일로 묶어서 저장할 수 있습니다.

```yaml
# values.yaml에서
flushSize: 10  # 10개 메시지마다 하나의 파일로 저장
```

**장점**: 파일 수 감소, S3 API 호출 감소  
**단점**: 실시간성 감소

#### 다른 토픽으로 변경

```yaml
# values.yaml에서
topics: your-new-topic-name
```

**주의**: 새 토픽이 Kafka에 존재해야 합니다.

#### S3 버킷 변경

```yaml
# values.yaml에서
s3BucketName: your-new-bucket-name
```

**주의**: 
1. 새 버킷이 존재해야 합니다
2. IAM 정책도 새 버킷에 대한 권한이 필요합니다
3. `s3-sink-policy.json`도 수정해야 합니다

---

## 모니터링 및 확인

### 1. 실시간 상태 확인

```bash
# 모든 리소스 상태 한 번에 확인
watch -n 2 'kubectl get pods,kafkaconnect,kafkaconnector -n kafka'
```

### 2. 메시지 처리량 확인

```bash
# Kafka Connect 로그에서 처리된 메시지 수 확인
kubectl logs -n kafka -l strimzi.io/name=c4-kafka-connect-connect --tail=100 | grep -i "committed\|flushed"

# S3에 저장된 파일 수 확인
aws s3 ls s3://c4-tracking-log/topics/tracking.log/partition=0/ --recursive | wc -l
```

### 3. 지연 시간 확인

```bash
# Kafka Connect 로그에서 지연 시간 확인
kubectl logs -n kafka -l strimzi.io/name=c4-kafka-connect-connect --tail=100 | grep -i "lag\|delay"
```

### 4. S3 저장 확인 스크립트

```bash
#!/bin/bash
# check-s3-uploads.sh

echo "=== S3 저장 상태 확인 ==="
echo

# 최근 5개 파일 확인
echo "최근 저장된 파일 (5개):"
aws s3 ls s3://c4-tracking-log/topics/tracking.log/partition=0/ --recursive | tail -5

echo
echo "총 파일 수:"
aws s3 ls s3://c4-tracking-log/topics/tracking.log/partition=0/ --recursive | wc -l

echo
echo "최신 파일 내용 (마지막 3줄):"
LATEST_FILE=$(aws s3 ls s3://c4-tracking-log/topics/tracking.log/partition=0/ --recursive | tail -1 | awk '{print $4}')
if [ -n "$LATEST_FILE" ]; then
  aws s3 cp s3://c4-tracking-log/$LATEST_FILE - | tail -3
fi
```

---

## 문제 해결

### 1. 메시지가 S3에 저장되지 않음

**확인 사항:**

```bash
# 1. Kafka Connect 파드가 실행 중인지 확인
kubectl get pods -n kafka -l strimzi.io/name=c4-kafka-connect-connect

# 2. Connector 상태 확인
kubectl get kafkaconnector s3-sink-connector -n kafka

# 3. 로그 확인
kubectl logs -n kafka -l strimzi.io/name=c4-kafka-connect-connect --tail=100

# 4. S3 권한 확인 (IAM 역할이 올바르게 설정되었는지)
kubectl describe pod -n kafka -l strimzi.io/name=c4-kafka-connect-connect | grep -i "role\|iam"
```

**일반적인 원인:**
- Connector가 `FAILED` 상태
- S3 권한 문제
- 토픽이 존재하지 않음

### 2. Connector가 FAILED 상태

```bash
# 상세 오류 확인
kubectl describe kafkaconnector s3-sink-connector -n kafka

# 로그에서 오류 메시지 확인
kubectl logs -n kafka -l strimzi.io/name=c4-kafka-connect-connect --tail=200 | grep -i error
```

**일반적인 해결 방법:**

```bash
# Connector 재시작
kubectl delete kafkaconnector s3-sink-connector -n kafka
# Helm으로 다시 배포하면 자동으로 재생성됨
helm upgrade kafka-connect ./helm/kafka-connect -n kafka
```

### 3. S3 권한 오류

**확인:**
```bash
# IAM 역할 확인
kubectl describe pod -n kafka -l strimzi.io/name=c4-kafka-connect-connect | grep "eks.amazonaws.com/role-arn"

# AWS CLI로 권한 테스트 (수동)
aws s3 ls s3://c4-tracking-log/
```

**해결:**
- IAM 역할에 S3 권한이 있는지 확인
- `helm/kafka-connect/s3-sink-policy.json` 파일 확인
- AWS 콘솔에서 IAM 역할 정책 확인

### 4. 토픽이 존재하지 않음

```bash
# 토픽 목록 확인
kubectl get kafkatopic -n kafka

# 토픽 생성 (필요시)
cat <<EOF | kubectl apply -f -
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaTopic
metadata:
  name: tracking.log
  namespace: kafka
  labels:
    strimzi.io/cluster: c4-kafka
spec:
  partitions: 1
  replicas: 1
EOF
```

### 5. 데이터 형식 오류

**문제**: JSON 파싱 오류

**확인:**
```bash
# Kafka에서 메시지 확인
kubectl exec -it kafka-client -n kafka -- \
  /opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server c4-kafka-kafka-bootstrap.kafka:9092 \
  --topic tracking.log \
  --from-beginning \
  --max-messages 5
```

**해결:**
- 메시지가 유효한 JSON 형식인지 확인
- `valueConverterSchemasEnable: false` 설정 확인

---

## 유용한 명령어 모음

### 빠른 상태 확인

```bash
# 모든 상태 한 번에 확인
echo "=== Kafka Connect 상태 ==="
kubectl get pods,kafkaconnect,kafkaconnector -n kafka

echo -e "\n=== 최근 로그 (10줄) ==="
kubectl logs -n kafka -l strimzi.io/name=c4-kafka-connect-connect --tail=10

echo -e "\n=== S3 최근 파일 (5개) ==="
aws s3 ls s3://c4-tracking-log/topics/tracking.log/partition=0/ --recursive | tail -5
```

### 데이터 검증

```bash
# S3에서 최신 파일 다운로드 및 검증
LATEST_FILE=$(aws s3 ls s3://c4-tracking-log/topics/tracking.log/partition=0/ --recursive | tail -1 | awk '{print $4}')
aws s3 cp s3://c4-tracking-log/$LATEST_FILE - | jq .  # jq로 JSON 포맷팅
```

---

## 참고 자료

- **Kafka Connect 문서**: `helm/kafka-connect/README.md`
- **배포 순서**: `helm/DEPLOYMENT_ORDER.md`
- **빠른 시작**: `helm/kafka-connect/QUICKSTART.md`
- **Confluent S3 Sink Connector 문서**: https://docs.confluent.io/kafka-connect-s3-sink/current/

---

## 문의 및 지원

문제가 발생하면 다음을 확인하세요:
1. `kubectl logs`로 로그 확인
2. `kubectl describe`로 리소스 상태 확인
3. S3 버킷 권한 확인
4. Kafka 토픽 존재 여부 확인

