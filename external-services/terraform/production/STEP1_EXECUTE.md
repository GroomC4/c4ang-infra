# Step 1 실행 가이드: MSK + EKS + kafka-client 기본 통신 테스트

## ✅ 현재 상태

- [x] Terraform Apply 성공
- [x] MSK 클러스터 배포 완료
- [x] EKS 클러스터 배포 완료
- [x] MSK Bootstrap Brokers 확인됨

---

## 🚀 Step 1: EKS 클러스터 연결 설정

### 1.1 kubeconfig 업데이트

```bash
cd external-services/terraform/production

# EKS 클러스터 이름 확인
EKS_CLUSTER_NAME=$(terraform output -raw eks_cluster_name)
AWS_REGION=$(terraform output -raw aws_region)

# kubeconfig 업데이트
aws eks update-kubeconfig --name $EKS_CLUSTER_NAME --region $AWS_REGION

# 연결 확인
kubectl get nodes
```

**예상 출력:**
```
NAME                                          STATUS   ROLES    AGE   VERSION
ip-10-0-48-xxx.ap-northeast-2.compute.internal   Ready    <none>   5m    v1.31.x
...
```

---

## 🔐 Step 2: MSK Bootstrap Brokers Secret 생성

### 2.1 MSK Bootstrap Brokers 가져오기

```bash
# MSK Bootstrap Brokers 확인
MSK_BROKERS=$(terraform output -raw msk_bootstrap_brokers)
echo "MSK Brokers: $MSK_BROKERS"
```

**출력 예시:**
```
b-1.c4kafka.l9hkqg.c2.kafka.ap-northeast-2.amazonaws.com:9092,b-2.c4kafka.l9hkqg.c2.kafka.ap-northeast-2.amazonaws.com:9092,b-3.c4kafka.l9hkqg.c2.kafka.ap-northeast-2.amazonaws.com:9092
```

### 2.2 Secret 생성

```bash
# Namespace 생성
kubectl create namespace kafka --dry-run=client -o yaml | kubectl apply -f -

# Secret 생성
kubectl create secret generic msk-bootstrap-brokers \
  --from-literal=bootstrap-brokers="$MSK_BROKERS" \
  -n kafka \
  --dry-run=client -o yaml | kubectl apply -f -

# Secret 확인
kubectl get secret msk-bootstrap-brokers -n kafka
```

---

## 📦 Step 3: kafka-client Pod 배포

### 3.1 Secret 값으로 YAML 업데이트

```bash
cd external-services/terraform/production/k8s

# YAML 파일의 Secret 부분을 실제 값으로 업데이트
MSK_BROKERS=$(cd .. && terraform output -raw msk_bootstrap_brokers)

# YAML 파일 업데이트 (sed 사용)
sed -i.bak "s|REPLACE_WITH_MSK_BOOTSTRAP_BROKERS|$MSK_BROKERS|g" msk-kafka-client.yaml

# 확인
grep "bootstrap-brokers:" msk-kafka-client.yaml
```

### 3.2 kafka-client 배포

```bash
# 배포
kubectl apply -f msk-kafka-client.yaml

# Pod 상태 확인
kubectl get pods -n kafka -w
```

**예상 출력:**
```
NAME                           READY   STATUS    RESTARTS   AGE
kafka-client-xxxxxxxxxx-xxxxx   1/1     Running   0          30s
```

### 3.3 Pod 로그 확인

```bash
# Pod 이름 가져오기
POD_NAME=$(kubectl get pods -n kafka -l app=kafka-client -o jsonpath='{.items[0].metadata.name}')

# 로그 확인
kubectl logs -n kafka $POD_NAME
```

**예상 출력:**
```
Kafka Client Pod 시작됨
MSK Bootstrap Brokers: b-1.c4kafka.l9hkqg.c2.kafka.ap-northeast-2.amazonaws.com:9092,...
사용 가능한 명령어:
  # 토픽 목록 확인
  kafka-topics.sh --bootstrap-server $MSK_BOOTSTRAP_BROKERS --list
  ...
```

---

## 🧪 Step 4: 기본 통신 테스트

### 4.1 MSK 연결 테스트

```bash
# Pod에 접속
kubectl exec -it -n kafka $POD_NAME -- /bin/sh

# Pod 내부에서 실행:
# 토픽 목록 확인
kafka-topics.sh --bootstrap-server $MSK_BOOTSTRAP_BROKERS --list

# 기본 토픽이 없으면 빈 목록이 나옵니다 (정상)
```

### 4.2 테스트 토픽 생성

```bash
# Pod 내부에서 실행:
# 테스트 토픽 생성
kafka-topics.sh --bootstrap-server $MSK_BOOTSTRAP_BROKERS \
  --create \
  --topic test-topic \
  --partitions 3 \
  --replication-factor 3

# 토픽 목록 확인
kafka-topics.sh --bootstrap-server $MSK_BOOTSTRAP_BROKERS --list

# 토픽 상세 정보 확인
kafka-topics.sh --bootstrap-server $MSK_BOOTSTRAP_BROKERS \
  --describe \
  --topic test-topic
```

**예상 출력:**
```
Topic: test-topic	PartitionCount: 3	ReplicationFactor: 3	Configs:
	Topic: test-topic	Partition: 0	Leader: 1	Replicas: 1,2,3	Isr: 1,2,3
	Topic: test-topic	Partition: 1	Leader: 2	Replicas: 2,3,1	Isr: 2,3,1
	Topic: test-topic	Partition: 2	Leader: 3	Replicas: 3,1,2	Isr: 3,1,2
```

### 4.3 Producer/Consumer 테스트

```bash
# Pod 내부에서 실행:

# Terminal 1: Consumer 실행 (백그라운드)
kafka-console-consumer.sh \
  --bootstrap-server $MSK_BOOTSTRAP_BROKERS \
  --topic test-topic \
  --from-beginning &

# Terminal 2: Producer로 메시지 전송
echo "Hello Kafka!" | kafka-console-producer.sh \
  --bootstrap-server $MSK_BOOTSTRAP_BROKERS \
  --topic test-topic

# Consumer에서 메시지가 보여야 합니다
```

---

## 📊 Step 5: Kafka 지표 확인

### 5.1 Consumer Group 확인

```bash
# Pod 내부에서 실행:
# Consumer Group 목록
kafka-consumer-groups.sh --bootstrap-server $MSK_BOOTSTRAP_BROKERS --list

# Consumer Group 상세 정보 (있는 경우)
kafka-consumer-groups.sh --bootstrap-server $MSK_BOOTSTRAP_BROKERS \
  --describe \
  --group <GROUP_NAME>
```

### 5.2 AWS CloudWatch에서 MSK 지표 확인

```bash
# MSK 클러스터 ARN 확인
terraform output msk_cluster_arn

# AWS Console에서 확인:
# CloudWatch > Metrics > AWS/Kafka
# - BytesInPerSec
# - BytesOutPerSec
# - MessagesInPerSec
# - UnderReplicatedPartitions
```

---

## ✅ Step 1 완료 체크리스트

- [ ] EKS 클러스터 연결 확인 (`kubectl get nodes`)
- [ ] MSK Bootstrap Brokers Secret 생성 완료
- [ ] kafka-client Pod 배포 및 Running 상태 확인
- [ ] MSK 연결 테스트 성공 (토픽 목록 확인)
- [ ] 테스트 토픽 생성 성공
- [ ] Producer/Consumer 통신 테스트 성공
- [ ] Kafka 지표 확인 완료

---

## 🎯 다음 단계: Step 2

Step 1이 완료되면 다음 단계로 진행:

**Step 2: Consumer Deployment + HPA (CPU 기준)**
- Kafka Consumer Deployment 생성
- CPU 기반 HPA 설정
- Kafka 부하 생성 및 Pod 스케일링 확인

---

## 🆘 문제 해결

### Pod가 Pending 상태인 경우

```bash
# Pod 이벤트 확인
kubectl describe pod -n kafka -l app=kafka-client

# 일반적인 원인:
# - MSK Security Group이 EKS 노드에서 접근 허용 안됨
# - Secret이 제대로 생성되지 않음
```

### MSK 연결 실패

```bash
# Security Group 확인
terraform output msk_security_group_id

# EKS 노드 Security Group 확인
terraform output eks_node_security_group_id

# MSK Security Group에 EKS 노드 Security Group이 인그레스 규칙에 있는지 확인
aws ec2 describe-security-groups \
  --group-ids $(terraform output -raw msk_security_group_id) \
  --query 'SecurityGroups[0].IpPermissions'
```

