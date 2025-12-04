# MSK 빠른 시작 가이드

## 🎯 목표

MSK + EKS + kafka-client로 기본 통신/토픽/지표 확인

---

## ⚡ 빠른 시작 (5분)

### 1. MSK 배포

```bash
cd external-services/terraform

# 변수 설정
cat >> terraform.tfvars <<EOF
create_msk = true
msk_instance_type = "kafka.t3.small"
msk_kafka_version = "3.6.0"
msk_ebs_volume_size = 100
EOF

# 배포 (15-20분 소요)
terraform init
terraform apply
```

### 2. MSK 연결 정보 확인

```bash
# Bootstrap Brokers 저장
export MSK_BROKERS=$(terraform output -raw msk_bootstrap_brokers)
echo "MSK Brokers: $MSK_BROKERS"
```

### 3. kafka-client 배포

```bash
# Secret 생성
kubectl create namespace kafka --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic msk-bootstrap-brokers \
  --from-literal=bootstrap-brokers="$MSK_BROKERS" \
  -n kafka

# kafka-client 배포
kubectl apply -f k8s/msk-kafka-client.yaml

# Pod 준비 대기
kubectl wait --for=condition=ready pod -l app=kafka-client -n kafka --timeout=60s
```

### 4. 연결 테스트

```bash
KAFKA_CLIENT_POD=$(kubectl get pod -n kafka -l app=kafka-client -o jsonpath='{.items[0].metadata.name}')

# 연결 테스트
kubectl exec -n kafka "$KAFKA_CLIENT_POD" -- \
  /opt/kafka/bin/kafka-broker-api-versions.sh \
  --bootstrap-server "$MSK_BROKERS"
```

### 5. 토픽 생성

```bash
cd k8s
chmod +x create-msk-topics.sh
./create-msk-topics.sh "$MSK_BROKERS"
```

### 6. 메시지 테스트

```bash
# Producer (터미널 1)
kubectl exec -n kafka -it "$KAFKA_CLIENT_POD" -- \
  /opt/kafka/bin/kafka-console-producer.sh \
  --bootstrap-server "$MSK_BROKERS" \
  --topic test-topic

# Consumer (터미널 2)
kubectl exec -n kafka -it "$KAFKA_CLIENT_POD" -- \
  /opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server "$MSK_BROKERS" \
  --topic test-topic \
  --from-beginning
```

---

## ✅ 확인 체크리스트

- [ ] MSK 클러스터 배포 완료 (`terraform output msk_bootstrap_brokers`)
- [ ] kafka-client Pod 실행 중 (`kubectl get pods -n kafka`)
- [ ] MSK 연결 성공 (kafka-broker-api-versions.sh 성공)
- [ ] 토픽 생성 완료 (`kafka-topics.sh --list`)
- [ ] Producer/Consumer 테스트 성공

---

## 📚 상세 가이드

더 자세한 내용은 [`k8s/msk-test-guide.md`](./k8s/msk-test-guide.md)를 참고하세요.

---

## 🔧 문제 해결

### MSK 연결 실패
```bash
# 보안 그룹 확인
terraform output msk_security_group_id
terraform output eks_node_security_group_id
```

### kafka-client Pod 오류
```bash
# 로그 확인
kubectl logs -n kafka -l app=kafka-client

# Secret 확인
kubectl get secret -n kafka msk-bootstrap-brokers -o yaml
```

---

## 🎯 다음 단계

1단계 완료 후:
- **2단계:** Consumer Deployment + HPA(CPU 기준) → Kafka 부하 걸어서 Pod 스케일 확인
- **3단계:** Karpenter 붙여서 Pod Pending → 노드 자동 신설까지 체인 완성  
- **4단계:** KEDA 도입해서 Kafka Lag 기반 스케일링으로 고도화

