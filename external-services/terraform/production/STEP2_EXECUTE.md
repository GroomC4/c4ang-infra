# Step 2 실행 가이드: Consumer Deployment + HPA (CPU 기준)

## 🎯 목표

1. Kafka Consumer Deployment 생성
2. CPU 기반 HPA 설정
3. Kafka 부하 생성 및 Pod 스케일링 확인

---

## 📋 사전 준비

### Step 1 완료 확인
- [x] MSK 클러스터 배포 완료
- [x] EKS 클러스터 연결 완료
- [x] kafka-client Pod 배포 완료
- [x] 테스트 토픽 생성 완료 (`test-topic`)

---

## 🚀 Step 2.1: Consumer Deployment + HPA 배포

### 1. Consumer Deployment 및 HPA 배포

```bash
cd external-services/terraform/production/k8s

# Consumer Deployment + HPA 배포
kubectl apply -f kafka-consumer-hpa.yaml

# 배포 상태 확인
kubectl get deployment -n kafka kafka-consumer
kubectl get hpa -n kafka kafka-consumer-hpa
kubectl get pods -n kafka -l app=kafka-consumer
```

**예상 출력:**
```
NAME              READY   UP-TO-DATE   AVAILABLE   AGE
kafka-consumer    1/1     1            1           30s

NAME                    REFERENCE                  TARGETS   MINPODS   MAXPODS   REPLICAS   AGE
kafka-consumer-hpa      Deployment/kafka-consumer  0%/70%    1         10        1          30s

NAME                              READY   STATUS    RESTARTS   AGE
kafka-consumer-xxxxxxxxxx-xxxxx   1/1     Running   0          30s
```

### 2. Consumer 로그 확인

```bash
# Pod 이름 가져오기
POD_NAME=$(kubectl get pods -n kafka -l app=kafka-consumer -o jsonpath='{.items[0].metadata.name}')

# 로그 확인
kubectl logs -n kafka $POD_NAME -f
```

**예상 출력:**
```
Kafka Consumer 시작...
Consumer Group: hpa-test-consumer-group
Topic: test-topic
MSK Brokers: b-1.c4kafka.l9hkqg.c2.kafka.ap-northeast-2.amazonaws.com:9092,...
메시지 소비 중...
```

---

## 📊 Step 2.2: HPA 모니터링 설정

### 1. 별도 터미널에서 HPA 모니터링

```bash
# HPA 상태 실시간 모니터링
watch -n 2 'kubectl get hpa -n kafka kafka-consumer-hpa'

# 또는 Pod 수 모니터링
watch -n 2 'kubectl get pods -n kafka -l app=kafka-consumer'
```

### 2. CPU 사용률 확인

```bash
# Pod CPU 사용률 확인
kubectl top pods -n kafka -l app=kafka-consumer
```

---

## 🔥 Step 2.3: 부하 생성 및 스케일링 확인

### 1. Producer Job으로 부하 생성

```bash
cd external-services/terraform/production/k8s

# Producer Job 배포 (10,000개 메시지 전송)
kubectl apply -f kafka-producer-load.yaml

# Job 상태 확인
kubectl get jobs -n kafka kafka-producer-load
kubectl logs -n kafka -l app=kafka-producer-load -f
```

### 2. Consumer Pod 스케일링 관찰

**별도 터미널에서 실행:**

```bash
# HPA 상태 모니터링 (2초마다 업데이트)
watch -n 2 'kubectl get hpa -n kafka kafka-consumer-hpa && echo "" && kubectl get pods -n kafka -l app=kafka-consumer'
```

**예상 동작:**
1. 초기: 1개 Pod (CPU 사용률 낮음)
2. 부하 생성 후: CPU 사용률 증가
3. HPA 반응: CPU 70% 초과 시 Pod 수 증가 (최대 10개)
4. 부하 감소 후: CPU 사용률 감소
5. 스케일 다운: 60초 후 Pod 수 감소

### 3. 상세 모니터링

```bash
# HPA 상세 정보
kubectl describe hpa -n kafka kafka-consumer-hpa

# Consumer Pod 상세 정보
kubectl describe pods -n kafka -l app=kafka-consumer

# Consumer Group 상태 확인
POD_NAME=$(kubectl get pods -n kafka -l app=kafka-client --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}')
MSK_BROKERS=$(cd .. && terraform output -raw msk_bootstrap_brokers)

kubectl exec -n kafka $POD_NAME -- kafka-consumer-groups \
  --bootstrap-server $MSK_BROKERS \
  --describe \
  --group hpa-test-consumer-group
```

---

## 📈 Step 2.4: 스케일링 결과 확인

### 1. HPA 이벤트 확인

```bash
# HPA 이벤트 확인
kubectl describe hpa -n kafka kafka-consumer-hpa | grep -A 20 "Events:"
```

**예상 출력:**
```
Events:
  Type    Reason             Age   From                       Message
  ----    ------             ----   ----                       -------
  Normal  SuccessfulRescale  2m    horizontal-pod-autoscaler  New size: 3; reason: cpu resource utilization (percentage of request) above target
  Normal  SuccessfulRescale  1m    horizontal-pod-autoscaler  New size: 5; reason: cpu resource utilization (percentage of request) above target
```

### 2. Pod 스케일링 히스토리

```bash
# Pod 생성 시간 확인
kubectl get pods -n kafka -l app=kafka-consumer --sort-by=.metadata.creationTimestamp
```

### 3. Consumer Group Lag 확인

```bash
POD_NAME=$(kubectl get pods -n kafka -l app=kafka-client --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}')
MSK_BROKERS=$(cd .. && terraform output -raw msk_bootstrap_brokers)

# Consumer Group Lag 확인
kubectl exec -n kafka $POD_NAME -- kafka-consumer-groups \
  --bootstrap-server $MSK_BROKERS \
  --describe \
  --group hpa-test-consumer-group \
  | grep -E "TOPIC|LAG|CURRENT-OFFSET"
```

---

## ✅ Step 2 완료 체크리스트

- [ ] Consumer Deployment 배포 완료
- [ ] HPA 설정 완료 및 활성화 확인
- [ ] 초기 Pod 1개 실행 확인
- [ ] Producer Job으로 부하 생성
- [ ] CPU 사용률 증가 확인
- [ ] HPA가 Pod 스케일 아웃 확인 (최소 2개 이상)
- [ ] 부하 감소 후 스케일 다운 확인
- [ ] Consumer Group Lag 확인

---

## 🎯 다음 단계: Step 3

Step 2가 완료되면 다음 단계로 진행:

**Step 3: Karpenter 통합**
- Karpenter 설치 및 설정
- Pod Pending 시 노드 자동 생성 확인
- 스케일링 체인 완성 (Pod → Node)

---

## 🆘 문제 해결

### HPA가 스케일링하지 않는 경우

```bash
# 1. Metrics Server 확인
kubectl get deployment metrics-server -n kube-system

# 2. CPU 메트릭 확인
kubectl top pods -n kafka -l app=kafka-consumer

# 3. HPA 상세 정보 확인
kubectl describe hpa -n kafka kafka-consumer-hpa
```

### Consumer가 메시지를 소비하지 않는 경우

```bash
# 1. Consumer 로그 확인
kubectl logs -n kafka -l app=kafka-consumer --tail=50

# 2. 토픽에 메시지가 있는지 확인
POD_NAME=$(kubectl get pods -n kafka -l app=kafka-client --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}')
MSK_BROKERS=$(cd .. && terraform output -raw msk_bootstrap_brokers)

kubectl exec -n kafka $POD_NAME -- kafka-run-class kafka.tools.GetOffsetShell \
  --broker-list $MSK_BROKERS \
  --topic test-topic \
  --time -1
```

---

## 📝 참고사항

### HPA 설정 설명

- **minReplicas**: 1 (최소 Pod 수)
- **maxReplicas**: 10 (최대 Pod 수)
- **target CPU**: 70% (CPU 사용률 70% 이상 시 스케일 아웃)
- **scaleUp**: 즉시 반응 (최대 100% 증가 또는 2개 Pod씩)
- **scaleDown**: 60초 안정화 시간 후 최대 50% 감소

### 부하 생성 옵션

`kafka-producer-load.yaml`의 `MESSAGE_COUNT`를 조정하여 부하 강도 변경:
- `1000`: 가벼운 부하
- `10000`: 중간 부하 (기본값)
- `100000`: 높은 부하

