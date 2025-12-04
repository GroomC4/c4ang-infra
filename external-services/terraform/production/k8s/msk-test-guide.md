# MSK + EKS 기본 통신/토픽/지표 확인 가이드

## 📋 목표

1. MSK 클러스터 배포 및 연결 확인
2. kafka-client Pod로 기본 통신 테스트
3. 토픽 생성 및 확인
4. Kafka 지표 확인

---

## 🚀 Step 1: MSK 배포

### 1.1 Terraform 변수 설정

```bash
cd external-services/terraform/production

# terraform.tfvars 파일 수정 또는 생성
cat >> terraform.tfvars <<EOF
create_msk = true
msk_instance_type = "kafka.t3.small"  # 테스트용 (비용 절감)
msk_kafka_version = "3.6.0"
msk_ebs_volume_size = 100
EOF
```

### 1.2 MSK 배포

```bash
terraform init
terraform plan  # 변경사항 확인
terraform apply  # MSK 생성 (약 15-20분 소요)
```

### 1.3 MSK 연결 정보 확인

```bash
# Bootstrap Brokers 확인
terraform output msk_bootstrap_brokers

# 클러스터 ARN 확인
terraform output msk_cluster_arn
```

**출력 예시:**
```
b-1.c4-dev-kafka.xxxxx.c2.kafka.ap-northeast-2.amazonaws.com:9092,b-2.c4-dev-kafka.xxxxx.c2.kafka.ap-northeast-2.amazonaws.com:9092
```

---

## 🔧 Step 2: kafka-client Pod 배포

### 2.1 Secret 생성 (MSK Bootstrap Brokers)

```bash
# MSK Bootstrap Brokers를 Secret에 저장
MSK_BROKERS=$(terraform output -raw msk_bootstrap_brokers)

# Secret 업데이트
kubectl create namespace kafka --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic msk-bootstrap-brokers \
  --from-literal=bootstrap-brokers="$MSK_BROKERS" \
  -n kafka \
  --dry-run=client -o yaml | kubectl apply -f -
```

### 2.2 kafka-client Pod 배포

```bash
cd external-services/terraform/production/k8s
kubectl apply -f msk-kafka-client.yaml
```

### 2.3 Pod 상태 확인

```bash
kubectl get pods -n kafka -l app=kafka-client
kubectl logs -n kafka -l app=kafka-client --tail=50
```

**예상 출력:**
```
Kafka Client Pod 시작됨
MSK Bootstrap Brokers: b-1.c4-dev-kafka.xxxxx.c2.kafka.ap-northeast-2.amazonaws.com:9092,...
사용 가능한 명령어:
  # 토픽 목록 확인
  kafka-topics.sh --bootstrap-server $MSK_BOOTSTRAP_BROKERS --list
  ...
```

---

## 📝 Step 3: 기본 통신 테스트

### 3.1 MSK 연결 테스트

```bash
KAFKA_CLIENT_POD=$(kubectl get pod -n kafka -l app=kafka-client -o jsonpath='{.items[0].metadata.name}')
MSK_BROKERS=$(kubectl get secret -n kafka msk-bootstrap-brokers -o jsonpath='{.data.bootstrap-brokers}' | base64 -d)

# 브로커 연결 테스트
kubectl exec -n kafka "$KAFKA_CLIENT_POD" -- \
  /opt/kafka/bin/kafka-broker-api-versions.sh \
  --bootstrap-server "$MSK_BROKERS"
```

**성공 시 출력:**
```
b-1.c4-dev-kafka.xxxxx.c2.kafka.ap-northeast-2.amazonaws.com:9092 (id: 1 rack: null) -> (
  Produce(0): 0 to 9 [usable: 9],
  Fetch(1): 0 to 13 [usable: 13],
  ...
)
```

### 3.2 기존 토픽 확인

```bash
kubectl exec -n kafka "$KAFKA_CLIENT_POD" -- \
  /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server "$MSK_BROKERS" \
  --list
```

---

## 🎯 Step 4: 토픽 생성

### 4.1 토픽 생성 스크립트 실행

```bash
cd external-services/terraform/production/k8s
chmod +x create-msk-topics.sh

# MSK Bootstrap Brokers를 인자로 전달
./create-msk-topics.sh "$MSK_BROKERS"
```

### 4.2 수동 토픽 생성 (선택)

```bash
# 테스트 토픽 생성
kubectl exec -n kafka "$KAFKA_CLIENT_POD" -- \
  /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server "$MSK_BROKERS" \
  --create \
  --topic test-topic \
  --partitions 3 \
  --replication-factor 2

# 토픽 상세 정보 확인
kubectl exec -n kafka "$KAFKA_CLIENT_POD" -- \
  /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server "$MSK_BROKERS" \
  --describe \
  --topic test-topic
```

**예상 출력:**
```
Topic: test-topic	PartitionCount: 3	ReplicationFactor: 2	Configs: segment.ms=604800000
	Topic: test-topic	Partition: 0	Leader: 1	Replicas: 1,2	Isr: 1,2
	Topic: test-topic	Partition: 1	Leader: 2	Replicas: 2,1	Isr: 2,1
	Topic: test-topic	Partition: 2	Leader: 1	Replicas: 1,2	Isr: 1,2
```

---

## 📊 Step 5: 메시지 전송/수신 테스트

### 5.1 Producer로 메시지 전송

```bash
# 별도 터미널에서 실행
kubectl exec -n kafka -it "$KAFKA_CLIENT_POD" -- \
  /opt/kafka/bin/kafka-console-producer.sh \
  --bootstrap-server "$MSK_BROKERS" \
  --topic test-topic

# 메시지 입력 (여러 줄 입력 가능)
# Hello MSK!
# This is a test message
# Ctrl+D로 종료
```

### 5.2 Consumer로 메시지 수신

```bash
# 별도 터미널에서 실행
kubectl exec -n kafka -it "$KAFKA_CLIENT_POD" -- \
  /opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server "$MSK_BROKERS" \
  --topic test-topic \
  --from-beginning

# 전송한 메시지들이 출력됨
# Ctrl+C로 종료
```

---

## 📈 Step 6: Kafka 지표 확인

### 6.1 Consumer Group 확인

```bash
# Consumer Group 목록
kubectl exec -n kafka "$KAFKA_CLIENT_POD" -- \
  /opt/kafka/bin/kafka-consumer-groups.sh \
  --bootstrap-server "$MSK_BROKERS" \
  --list

# Consumer Group 상세 정보 (예시)
kubectl exec -n kafka "$KAFKA_CLIENT_POD" -- \
  /opt/kafka/bin/kafka-consumer-groups.sh \
  --bootstrap-server "$MSK_BROKERS" \
  --describe \
  --group console-consumer-<ID>
```

### 6.2 토픽 파티션 오프셋 확인

```bash
# 토픽의 파티션별 오프셋 확인
kubectl exec -n kafka "$KAFKA_CLIENT_POD" -- \
  /opt/kafka/bin/kafka-run-class.sh \
  kafka.tools.GetOffsetShell \
  --broker-list "$MSK_BROKERS" \
  --topic test-topic \
  --time -1  # earliest offset
```

### 6.3 AWS CloudWatch 지표 확인

```bash
# AWS CLI로 MSK 지표 확인
MSK_CLUSTER_ARN=$(terraform output -raw msk_cluster_arn)

# 브로커별 CPU 사용률
aws cloudwatch get-metric-statistics \
  --namespace AWS/Kafka \
  --metric-name CpuUser \
  --dimensions Name=Cluster Name,Value=$(echo "$MSK_CLUSTER_ARN" | cut -d'/' -f2) \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average

# 토픽별 메시지 처리량
aws cloudwatch get-metric-statistics \
  --namespace AWS/Kafka \
  --metric-name MessagesInPerSec \
  --dimensions Name=Cluster Name,Value=$(echo "$MSK_CLUSTER_ARN" | cut -d'/' -f2) \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average
```

---

## ✅ 체크리스트

- [ ] MSK 클러스터 배포 완료
- [ ] MSK Bootstrap Brokers 확인
- [ ] kafka-client Pod 배포 및 실행 확인
- [ ] MSK 연결 테스트 성공
- [ ] 토픽 생성 스크립트 실행 완료
- [ ] Producer/Consumer 테스트 성공
- [ ] Consumer Group 확인
- [ ] CloudWatch 지표 확인

---

## 🔍 문제 해결

### MSK 연결 실패

```bash
# 보안 그룹 확인
terraform output msk_security_group_id
terraform output eks_node_security_group_id

# 보안 그룹 규칙 확인
aws ec2 describe-security-groups \
  --group-ids $(terraform output -raw msk_security_group_id) \
  --query 'SecurityGroups[0].IpPermissions'
```

### kafka-client Pod가 MSK에 연결되지 않음

```bash
# Pod 로그 확인
kubectl logs -n kafka -l app=kafka-client

# Secret 확인
kubectl get secret -n kafka msk-bootstrap-brokers -o yaml

# Pod 내부에서 연결 테스트
kubectl exec -n kafka "$KAFKA_CLIENT_POD" -- \
  nc -zv <MSK_BROKER_HOST> 9092
```

### 토픽 생성 실패

```bash
# 브로커 수 확인 (replication-factor는 브로커 수 이하여야 함)
terraform output -json | jq -r '.msk_cluster_arn.value' | \
  xargs -I {} aws kafka describe-cluster --cluster-arn {} \
  --query 'ClusterInfo.NumberOfBrokerNodes'

# 토픽 생성 시 replication-factor를 브로커 수에 맞게 조정
```

---

## 📚 다음 단계

1단계 완료 후:
- ✅ **2단계:** Consumer Deployment + HPA(CPU 기준) → Kafka 부하 걸어서 Pod 스케일 확인
- ✅ **3단계:** Karpenter 붙여서 Pod Pending → 노드 자동 신설까지 체인 완성
- ✅ **4단계:** KEDA 도입해서 Kafka Lag 기반 스케일링으로 고도화

