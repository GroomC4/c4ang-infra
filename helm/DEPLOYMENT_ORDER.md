# Kafka 인프라 배포 순서

## 배포 순서

### 1️⃣ Strimzi Operator + Kafka Cluster 배포
```bash
./helm/setup-eks-kafka.sh
```
- Strimzi Operator 설치
- Kafka Cluster (`c4-kafka`) 배포
- Kafka Client Pod 생성

**참고**: `kafka-cluster.yaml`은 `setup-eks-kafka.sh`에 이미 포함되어 있습니다.
별도로 apply할 필요는 없습니다. (다른 설정이 필요하면 수정 후 apply)

### 2️⃣ Kafka Topics 배포 (선택사항)
```bash
helm upgrade --install kafka-topics ./helm/kafka-topics -n kafka
```
- `values.yaml`에 정의된 모든 토픽 생성
- `tracking-log` 토픽도 여기서 생성 가능

### 3️⃣ Kafka Connect + S3 Sink Connector 배포
```bash
cd helm/kafka-connect
./setup-kafka-connect.sh
```
- ✅ ECR 레지스트리 생성 (없는 경우)
- ✅ Docker 이미지 빌드 및 푸시
- ✅ values.yaml 자동 업데이트
- ✅ IAM Trust Policy 확인 및 업데이트
- ✅ **Helm으로 Kafka Connect 배포** (이미 포함됨!)
- ✅ S3 Sink Connector 자동 배포

**중요**: `setup-kafka-connect.sh`는 이미 Helm 배포를 포함하고 있으므로
별도로 `helm upgrade --install`을 실행할 필요가 없습니다.

## 전체 배포 스크립트 예시

```bash
#!/bin/bash
set -euo pipefail

# 1. Kafka Operator + Cluster
echo "📌 [1/3] Kafka Operator + Cluster 배포 중..."
./helm/setup-eks-kafka.sh

# 2. Kafka Topics (선택사항)
echo "📌 [2/3] Kafka Topics 배포 중..."
helm upgrade --install kafka-topics ./helm/kafka-topics -n kafka

# 3. Kafka Connect + S3 Sink Connector
echo "📌 [3/3] Kafka Connect + S3 Sink Connector 배포 중..."
cd helm/kafka-connect
./setup-kafka-connect.sh
```

## 확인 명령어

```bash
# Kafka Cluster 상태
kubectl get kafka -n kafka

# Kafka Pods
kubectl get pods -n kafka

# Kafka Topics
kubectl get kafkatopic -n kafka

# Kafka Connect
kubectl get kafkaconnect -n kafka
kubectl get pods -n kafka -l strimzi.io/name=c4-kafka-connect-connect

# S3 Sink Connector
kubectl get kafkaconnector -n kafka
```

