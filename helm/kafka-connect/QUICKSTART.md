# Kafka Connect with S3 Sink Connector - 빠른 시작 가이드

## 한 번에 배포하기

EKS 환경에서 Kafka Connect와 S3 Sink Connector를 한 번에 배포하는 방법입니다.

### 필수 요구사항

- EKS 클러스터 실행 중
- Strimzi Operator 설치됨
- Kafka 클러스터 (`c4-kafka`) 설치됨
- AWS CLI, Docker, kubectl, helm 설치됨
- ECR 접근 권한

### 자동 배포 (권장) ⭐

```bash
cd helm/kafka-connect
./setup-kafka-connect.sh
```

이 스크립트는 다음을 자동으로 수행합니다:

1. ✅ ECR 레지스트리 생성 (없는 경우)
2. ✅ Docker 이미지 빌드 (S3 Sink Connector 포함, linux/amd64)
3. ✅ ECR에 이미지 푸시
4. ✅ values.yaml 자동 업데이트
5. ✅ Helm으로 Kafka Connect + KafkaConnector 배포
6. ✅ 상태 확인

### 배포 확인

```bash
# Kafka Connect 파드 확인
kubectl get pods -n kafka -l strimzi.io/name=c4-kafka-connect-connect

# Kafka Connect 상태 확인
kubectl get kafkaconnect -n kafka

# S3 Sink Connector 상태 확인
kubectl get kafkaconnector -n kafka

# 로그 확인
kubectl logs -n kafka -l strimzi.io/name=c4-kafka-connect-connect --tail=50
```

### 환경 변수로 설정 변경

```bash
# 기본값 변경
export KAFKA_NS="kafka"
export AWS_REGION="ap-northeast-2"
export AWS_ACCOUNT_ID="963403601423"
export IMAGE_NAME="kafka-connect-s3"
export IMAGE_TAG="latest"

# 스크립트 실행
./setup-kafka-connect.sh
```

### 수동 배포

자동 스크립트를 사용하지 않는 경우:

```bash
# 1. 이미지 빌드 및 푸시
cd helm/kafka-connect
./build-and-push.sh

# 2. Helm 배포
cd ../..
helm upgrade --install kafka-connect ./helm/kafka-connect -n kafka
```

## 문제 해결

### 이미지 Pull 실패

ECR 이미지를 pull할 수 없는 경우:
1. ECR 레지스트리가 올바른지 확인
2. EKS 노드 그룹에 ECR 접근 권한 확인
3. 이미지가 linux/amd64 플랫폼으로 빌드되었는지 확인

### Connector가 준비되지 않음

```bash
kubectl describe kafkaconnector s3-sink-connector -n kafka
```

오류 메시지를 확인하고 필요한 설정을 수정합니다.

## 재배포 시

EKS 환경을 다시 올리는 경우:

```bash
cd helm/kafka-connect
./setup-kafka-connect.sh
```

스크립트가 모든 것을 자동으로 처리합니다:
- ECR 레지스트리는 이미 존재하면 재사용
- 이미지는 새로 빌드되어 푸시
- Helm으로 자동 배포

## 제거

```bash
# Helm 제거
helm uninstall kafka-connect -n kafka

# ECR 이미지 제거 (선택사항)
aws ecr delete-repository --repository-name kafka-connect-s3 --region ap-northeast-2 --force
```

