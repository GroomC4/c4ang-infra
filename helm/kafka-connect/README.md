# Kafka Connect with S3 Sink Connector

Kafka Connect와 S3 Sink Connector를 EKS에 배포하는 Helm Chart입니다.

## 개요

이 Helm Chart는 다음을 포함합니다:
- Kafka Connect (Strimzi 기반)
- S3 Sink Connector 플러그인 (커스텀 Docker 이미지)
- S3 Sink Connector 리소스

## 사전 요구사항

1. ✅ EKS 클러스터
2. ✅ Strimzi Operator 설치
3. ✅ Kafka 클러스터 설치 (`c4-kafka`)
4. ✅ AWS CLI 및 Docker 설치
5. ✅ ECR 접근 권한
6. ✅ kubectl 및 helm 설치

## 빠른 시작

### 자동화 스크립트 사용 (권장) ⭐

**전체 배포를 한 번에 자동화하는 스크립트를 실행합니다:**

```bash
cd helm/kafka-connect
./setup-kafka-connect.sh
```

이 스크립트는 다음을 **자동으로** 수행합니다:

1. ✅ **필수 도구 확인** (aws, docker, kubectl, helm)
2. ✅ **ECR 레지스트리 생성** (없는 경우)
3. ✅ **Docker 이미지 빌드** (S3 Sink Connector 포함, linux/amd64 플랫폼)
   - 이미 ECR에 이미지가 있으면 스킵 (FORCE_REBUILD=true로 강제 재빌드 가능)
4. ✅ **ECR에 이미지 푸시** (이미 있으면 스킵)
5. ✅ **values.yaml 자동 업데이트** (이미지 URL)
6. ✅ **IAM 역할 Trust Policy 확인 및 업데이트** (IRSA 설정)
   - EKS 클러스터의 OIDC Provider를 자동으로 감지
   - ServiceAccount와 IAM 역할의 trust policy를 자동으로 맞춤
7. ✅ **Helm으로 Kafka Connect 배포** (KafkaConnector 포함)
8. ✅ **상태 확인 및 대기**

**환경 변수로 설정 변경 가능:**
```bash
# 기본값 변경
export KAFKA_NS="kafka"
export AWS_REGION="ap-northeast-2"
export AWS_ACCOUNT_ID="963403601423"
export IMAGE_NAME="kafka-connect-s3"
export IMAGE_TAG="latest"
export EKS_CLUSTER_NAME="c4-eks-cluster"  # EKS 클러스터 이름 (자동 감지 실패 시)

# 이미지 강제 재빌드
export FORCE_REBUILD="true"

# 스크립트 실행
./setup-kafka-connect.sh
```

**중요 사항:**
- ✅ **IAM 역할과 권한**: EKS를 내려도 AWS IAM에 저장되므로 **그대로 유지**됩니다
- ✅ **S3 버킷**: EKS와 독립적이므로 **그대로 유지**됩니다
- ✅ **ECR 이미지**: EKS와 독립적이므로 **그대로 유지**됩니다
- ⚠️ **IAM Trust Policy**: EKS를 새로 만들면 OIDC Provider ID가 바뀔 수 있지만, **스크립트가 자동으로 업데이트**합니다

### 수동 배포

자동화 스크립트를 사용하지 않는 경우:

#### 1. Docker 이미지 빌드 및 푸시

```bash
cd helm/kafka-connect

# ECR 레지스트리 생성
aws ecr create-repository \
  --repository-name kafka-connect-s3 \
  --region ap-northeast-2

# ECR 로그인
aws ecr get-login-password --region ap-northeast-2 | \
  docker login --username AWS --password-stdin 963403601423.dkr.ecr.ap-northeast-2.amazonaws.com

# 이미지 빌드 (linux/amd64 플랫폼)
docker build --platform linux/amd64 -t kafka-connect-s3:latest -f Dockerfile .

# 이미지 태깅 및 푸시
docker tag kafka-connect-s3:latest 963403601423.dkr.ecr.ap-northeast-2.amazonaws.com/kafka-connect-s3:latest
docker push 963403601423.dkr.ecr.ap-northeast-2.amazonaws.com/kafka-connect-s3:latest
```

#### 2. values.yaml 업데이트

`values.yaml`에서 이미지 URL을 업데이트:

```yaml
image: 963403601423.dkr.ecr.ap-northeast-2.amazonaws.com/kafka-connect-s3:latest
```

#### 3. Helm 배포

```bash
cd ../..
helm upgrade --install kafka-connect ./helm/kafka-connect -n kafka
```

## 설정

### values.yaml 주요 설정

```yaml
# Namespace
namespace: kafka

# Kafka Connect 설정
replicas: 1
bootstrapServers: c4-kafka-kafka-bootstrap:9092

# Docker 이미지 (자동화 스크립트가 업데이트)
image: 963403601423.dkr.ecr.ap-northeast-2.amazonaws.com/kafka-connect-s3:latest

# ServiceAccount 설정 (IRSA)
serviceAccountName: c4-kafka-connect-connect
serviceAccountArn: arn:aws:iam::963403601423:role/eksctl-c4-eks-cluster-addon-iamserviceaccount-Role1-YQcLCkIlCmbK

# KafkaConnector 설정
connector:
  enabled: true
  name: s3-sink-connector
  cluster: c4-kafka-connect
  class: io.confluent.connect.s3.S3SinkConnector
  tasksMax: 1
  config:
    topics: tracking-log
    s3Region: ap-northeast-2
    s3BucketName: c4-tracking-log
    # ... 기타 설정
```

### S3 Sink Connector 설정

`values.yaml`의 `connector.config` 섹션에서 다음을 설정할 수 있습니다:

- **topics**: Kafka 토픽 이름
- **s3BucketName**: S3 버킷 이름
- **s3Region**: AWS 리전
- **flushSize**: S3에 쓰기 전 버퍼링할 레코드 수
- **formatClass**: 데이터 포맷 (JSON, Avro 등)

## 상태 확인

### 파드 상태 확인

```bash
kubectl get pods -n kafka -l strimzi.io/name=c4-kafka-connect-connect
```

### Kafka Connect 상태 확인

```bash
kubectl get kafkaconnect -n kafka
```

### S3 Sink Connector 상태 확인

```bash
kubectl get kafkaconnector -n kafka
kubectl describe kafkaconnector s3-sink-connector -n kafka
```

### 로그 확인

```bash
# Kafka Connect 로그
kubectl logs -n kafka -l strimzi.io/name=c4-kafka-connect-connect --tail=50

# Connector 로그 (Kafka Connect 로그에 포함됨)
kubectl logs -n kafka -l strimzi.io/name=c4-kafka-connect-connect | grep -i connector
```

## 문제 해결

### 이미지 Pull 실패

ECR 이미지를 pull할 수 없는 경우:

1. ECR 레지스트리가 존재하는지 확인:
   ```bash
   aws ecr describe-repositories --repository-names kafka-connect-s3
   ```

2. ECR 접근 권한 확인:
   ```bash
   aws ecr get-login-password --region ap-northeast-2 | \
     docker login --username AWS --password-stdin 963403601423.dkr.ecr.ap-northeast-2.amazonaws.com
   ```

3. 이미지 플랫폼 확인 (linux/amd64여야 함):
   ```bash
   docker build --platform linux/amd64 -t kafka-connect-s3:latest -f Dockerfile .
   ```

### Connector가 Ready 상태가 아님

1. Connector 상태 확인:
   ```bash
   kubectl describe kafkaconnector s3-sink-connector -n kafka
   ```

2. Kafka Connect 로그 확인:
   ```bash
   kubectl logs -n kafka -l strimzi.io/name=c4-kafka-connect-connect --tail=100
   ```

3. S3 버킷 권한 확인 (IRSA 설정 확인)

### 플러그인을 찾을 수 없음

S3 Sink Connector 플러그인이 설치되지 않은 경우:

1. Docker 이미지에 플러그인이 포함되어 있는지 확인:
   ```bash
   docker run --rm 963403601423.dkr.ecr.ap-northeast-2.amazonaws.com/kafka-connect-s3:latest \
     ls -la /opt/kafka/plugins/
   ```

2. 이미지를 다시 빌드하고 푸시:
   ```bash
   ./setup-kafka-connect.sh
   ```

## 업그레이드

### 이미지만 업데이트하는 경우

```bash
cd helm/kafka-connect
./setup-kafka-connect.sh
```

### 설정 변경 후 업데이트

```bash
# values.yaml 수정 후
helm upgrade kafka-connect ./helm/kafka-connect -n kafka
```

## EKS 재배포 시 주의사항

### 유지되는 리소스 (EKS를 내려도 그대로 유지)
- ✅ **IAM 역할 및 정책**: AWS IAM에 저장되므로 유지됨
- ✅ **S3 버킷 및 데이터**: S3는 EKS와 독립적이므로 유지됨
- ✅ **ECR 이미지**: ECR은 EKS와 독립적이므로 유지됨

### 자동으로 처리되는 것
- ✅ **IAM Trust Policy**: 스크립트가 EKS의 OIDC Provider를 자동으로 감지하고 trust policy를 업데이트
- ✅ **ECR 레지스트리**: 이미 존재하면 스킵
- ✅ **Docker 이미지**: 이미 ECR에 있으면 빌드/푸시 스킵

### EKS 재배포 후 실행 순서

1. **Kafka 클러스터 배포** (기존 스크립트 사용)
2. **Kafka Connect 배포**:
   ```bash
   cd helm/kafka-connect
   ./setup-kafka-connect.sh
   ```

스크립트가 모든 것을 자동으로 처리합니다!

## 삭제

```bash
# Helm으로 삭제
helm uninstall kafka-connect -n kafka

# KafkaConnector만 삭제
kubectl delete kafkaconnector s3-sink-connector -n kafka
```

## 파일 구조

```
helm/kafka-connect/
├── Chart.yaml                    # Helm Chart 메타데이터
├── values.yaml                   # 설정 값
├── Dockerfile                    # S3 Connector 포함 이미지 빌드
├── setup-kafka-connect.sh       # 자동화 스크립트 ⭐
├── build-and-push.sh            # 이미지 빌드/푸시 스크립트
├── templates/
│   ├── connect.yaml             # KafkaConnect 리소스
│   └── kafkaconnector.yaml      # KafkaConnector 리소스
└── README.md                    # 이 파일
```

## 참고 자료

- [Strimzi Kafka Connect 문서](https://strimzi.io/docs/latest/#kafka-connect-str)
- [Confluent S3 Sink Connector 문서](https://docs.confluent.io/kafka-connect-s3-sink/current/index.html)
- [AWS ECR 문서](https://docs.aws.amazon.com/ecr/)
