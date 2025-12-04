# 1단계 체크리스트: MSK + EKS + kafka-client 기본 통신 테스트

## 🎯 목표
MSK + EKS + kafka-client로 기본 통신/토픽/지표 확인이 정상 작동하는지 검증

---

## ✅ 사전 준비

### 1. Terraform 테스트 통과 확인
```bash
cd external-services/terraform/production
./scripts/test-terraform.sh
```

**확인 사항:**
- [ ] 포맷 확인 통과
- [ ] 구문 검증 통과
- [ ] 실행 계획 확인 완료

---

## 🚀 Step 1: MSK 배포

### 1.1 terraform.tfvars 설정

```bash
# terraform.tfvars 파일 확인/수정
cat terraform.tfvars | grep -E "create_msk|msk_"

# MSK 설정 추가 (없는 경우)
cat >> terraform.tfvars <<EOF
create_msk = true
msk_instance_type = "kafka.t3.small"
msk_kafka_version = "3.7.0"
msk_ebs_volume_size = 100
msk_use_kraft = true
EOF
```

### 1.2 MSK 배포

```bash
# 변경사항 확인
terraform plan | grep -A 5 "aws_msk_cluster"

# 배포 (15-20분 소요)
terraform apply

# 배포 완료 확인
terraform output msk_cluster_arn
```

**확인 사항:**
- [ ] MSK 클러스터 생성 완료
- [ ] Bootstrap Brokers 출력 확인
- [ ] 클러스터 상태가 "ACTIVE"

---

## 🔧 Step 2: kafka-client 배포

### 2.1 MSK 연결 정보 확인

```bash
# Bootstrap Brokers 저장
export MSK_BROKERS=$(terraform output -raw msk_bootstrap_brokers)
echo "MSK Brokers: $MSK_BROKERS"

# 출력 예시 확인
# b-1.c4-dev-kafka.xxxxx.c2.kafka.ap-northeast-2.amazonaws.com:9092,b-2.c4-dev-kafka.xxxxx.c2.kafka.ap-northeast-2.amazonaws.com:9092
```

**확인 사항:**
- [ ] MSK_BROKERS 변수에 값이 설정됨
- [ ] 브로커 주소가 올바른 형식

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
kubectl get secret -n kafka msk-bootstrap-brokers -o yaml
```

**확인 사항:**
- [ ] kafka namespace 생성됨
- [ ] Secret 생성됨
- [ ] Secret에 bootstrap-brokers 값이 올바르게 저장됨

### 2.3 kafka-client Pod 배포

```bash
# kafka-client 배포
kubectl apply -f k8s/msk-kafka-client.yaml

# Pod 상태 확인
kubectl get pods -n kafka -l app=kafka-client

# Pod 로그 확인
kubectl logs -n kafka -l app=kafka-client --tail=50
```

**확인 사항:**
- [ ] Pod가 Running 상태
- [ ] 로그에 MSK Bootstrap Brokers 출력됨
- [ ] 에러 메시지 없음

---

## 📝 Step 3: MSK 연결 테스트

### 3.1 브로커 연결 테스트

```bash
KAFKA_CLIENT_POD=$(kubectl get pod -n kafka -l app=kafka-client -o jsonpath='{.items[0].metadata.name}')
MSK_BROKERS=$(kubectl get secret -n kafka msk-bootstrap-brokers -o jsonpath='{.data.bootstrap-brokers}' | base64 -d)

# 브로커 API 버전 확인
kubectl exec -n kafka "$KAFKA_CLIENT_POD" -- \
  /opt/kafka/bin/kafka-broker-api-versions.sh \
  --bootstrap-server "$MSK_BROKERS"
```

**예상 출력:**
```
b-1.c4-dev-kafka.xxxxx.c2.kafka.ap-northeast-2.amazonaws.com:9092 (id: 1 rack: null) -> (
  Produce(0): 0 to 9 [usable: 9],
  Fetch(1): 0 to 13 [usable: 13],
  ...
)
```

**확인 사항:**
- [ ] 브로커 연결 성공
- [ ] API 버전 정보 출력됨
- [ ] 에러 없음

---

## 🎯 Step 4: 토픽 생성 및 확인

### 4.1 토픽 생성

```bash
cd k8s
chmod +x create-msk-topics.sh

# 토픽 생성
./create-msk-topics.sh "$MSK_BROKERS"
```

**확인 사항:**
- [ ] 토픽 생성 스크립트 실행 성공
- [ ] 토픽 목록에 생성된 토픽들이 보임

### 4.2 토픽 목록 확인

```bash
kubectl exec -n kafka "$KAFKA_CLIENT_POD" -- \
  /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server "$MSK_BROKERS" \
  --list
```

**예상 출력:**
```
order.created
order.canceled
payment.completed
test-topic
...
```

**확인 사항:**
- [ ] 토픽 목록이 출력됨
- [ ] 생성한 토픽들이 모두 보임

### 4.3 토픽 상세 정보 확인

```bash
# 특정 토픽 상세 정보
kubectl exec -n kafka "$KAFKA_CLIENT_POD" -- \
  /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server "$MSK_BROKERS" \
  --describe \
  --topic test-topic
```

**확인 사항:**
- [ ] 파티션 정보 확인
- [ ] 복제 팩터 확인
- [ ] Leader/ISR 정보 확인

---

## 📊 Step 5: 메시지 전송/수신 테스트

### 5.1 Producer로 메시지 전송

```bash
# 별도 터미널에서 실행
kubectl exec -n kafka -it "$KAFKA_CLIENT_POD" -- \
  /opt/kafka/bin/kafka-console-producer.sh \
  --bootstrap-server "$MSK_BROKERS" \
  --topic test-topic

# 메시지 입력
Hello MSK!
This is a test message
Test message 123
# Ctrl+D로 종료
```

**확인 사항:**
- [ ] Producer가 정상적으로 시작됨
- [ ] 메시지 입력 가능
- [ ] 에러 없음

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

**확인 사항:**
- [ ] Consumer가 정상적으로 시작됨
- [ ] 전송한 메시지들이 모두 수신됨
- [ ] 메시지 순서가 올바름

---

## 📈 Step 6: Kafka 지표 확인

### 6.1 Consumer Group 확인

```bash
# Consumer Group 목록
kubectl exec -n kafka "$KAFKA_CLIENT_POD" -- \
  /opt/kafka/bin/kafka-consumer-groups.sh \
  --bootstrap-server "$MSK_BROKERS" \
  --list

# Consumer Group 상세 정보
kubectl exec -n kafka "$KAFKA_CLIENT_POD" -- \
  /opt/kafka/bin/kafka-consumer-groups.sh \
  --bootstrap-server "$MSK_BROKERS" \
  --describe \
  --group console-consumer-<ID>
```

**확인 사항:**
- [ ] Consumer Group 목록 출력
- [ ] Lag 정보 확인 가능

### 6.2 토픽 오프셋 확인

```bash
# 토픽의 파티션별 오프셋 확인
kubectl exec -n kafka "$KAFKA_CLIENT_POD" -- \
  /opt/kafka/bin/kafka-run-class.sh \
  kafka.tools.GetOffsetShell \
  --broker-list "$MSK_BROKERS" \
  --topic test-topic \
  --time -1
```

**확인 사항:**
- [ ] 각 파티션의 오프셋 정보 확인
- [ ] 메시지가 올바르게 저장됨

### 6.3 AWS CloudWatch 지표 확인 (선택사항)

```bash
# MSK 클러스터 ARN 확인
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
```

---

## ✅ 최종 확인 체크리스트

1단계 완료 기준:

- [ ] MSK 클러스터 배포 완료 및 ACTIVE 상태
- [ ] MSK Bootstrap Brokers 확인
- [ ] kafka-client Pod 실행 중
- [ ] MSK 연결 테스트 성공 (kafka-broker-api-versions.sh)
- [ ] 토픽 생성 완료 (최소 5개 이상)
- [ ] Producer/Consumer 테스트 성공
- [ ] Consumer Group 확인 가능
- [ ] 토픽 오프셋 확인 가능

---

## 🐛 문제 해결

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

### kafka-client Pod 오류
```bash
# Pod 로그 확인
kubectl logs -n kafka -l app=kafka-client

# Secret 확인
kubectl get secret -n kafka msk-bootstrap-brokers -o yaml

# Pod 재시작
kubectl delete pod -n kafka -l app=kafka-client
```

### 토픽 생성 실패
```bash
# 브로커 수 확인
terraform output -json | jq -r '.msk_cluster_arn.value' | \
  xargs -I {} aws kafka describe-cluster --cluster-arn {} \
  --query 'ClusterInfo.NumberOfBrokerNodes'

# replication-factor를 브로커 수에 맞게 조정
```

---

## 📝 테스트 결과 기록

1단계 완료 후 다음 정보를 기록하세요:

```
✅ 1단계 완료 일시: _______________
✅ MSK 클러스터 ARN: _______________
✅ Bootstrap Brokers: _______________
✅ 생성된 토픽 수: _______________
✅ 테스트 메시지 수: _______________
✅ 문제 발생 여부: [ ] 없음 [ ] 있음 (상세: _______________)
```

---

## 🎯 다음 단계

1단계가 성공적으로 완료되면:
- ✅ **2단계 코드 작성 시작**
- Consumer Deployment + HPA 코드 작성
- Kafka 부하 생성 스크립트 작성

**1단계 완료 후 알려주시면 2단계 코드를 작성하겠습니다!** 🚀

