# ✅ Step 1 완료: MSK + EKS + kafka-client 기본 통신 테스트 성공!

## 🎉 완료된 작업

- [x] EKS 클러스터 연결 설정 완료
- [x] MSK Bootstrap Brokers Secret 생성 완료
- [x] kafka-client Pod 배포 완료 (Confluent 이미지 사용)
- [x] MSK 연결 테스트 성공
- [x] 테스트 토픽 생성 성공 (`test-topic`)
- [x] Producer/Consumer 통신 테스트 성공

---

## 📊 테스트 결과

### MSK 클러스터 정보
- **Bootstrap Brokers**: `b-1.c4kafka.l9hkqg.c2.kafka.ap-northeast-2.amazonaws.com:9092,b-2.c4kafka.l9hkqg.c2.kafka.ap-northeast-2.amazonaws.com:9092,b-3.c4kafka.l9hkqg.c2.kafka.ap-northeast-2.amazonaws.com:9092`
- **클러스터 이름**: `c4-kafka`
- **Kafka 버전**: `3.7.x.kraft` (KRaft 모드)
- **브로커 수**: 3개

### 생성된 토픽
- `__amazon_msk_canary` (MSK 시스템 토픽)
- `__consumer_offsets` (Kafka 시스템 토픽)
- `test-topic` (테스트 토픽)
  - Partitions: 3
  - Replication Factor: 3
  - Compression: snappy

---

## 🔧 사용된 명령어 (참고)

### Pod 접속 및 기본 명령어
```bash
# Pod 이름 가져오기
POD_NAME=$(kubectl get pods -n kafka -l app=kafka-client --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}')
MSK_BROKERS=$(terraform output -raw msk_bootstrap_brokers)

# 토픽 목록 확인
kubectl exec -n kafka $POD_NAME -- kafka-topics --bootstrap-server $MSK_BROKERS --list

# 토픽 생성
kubectl exec -n kafka $POD_NAME -- kafka-topics --bootstrap-server $MSK_BROKERS \
  --create --topic <TOPIC_NAME> --partitions 3 --replication-factor 3

# Producer로 메시지 전송
echo "Hello Kafka!" | kubectl exec -i -n kafka $POD_NAME -- \
  kafka-console-producer --bootstrap-server $MSK_BROKERS --topic test-topic

# Consumer로 메시지 수신
kubectl exec -n kafka $POD_NAME -- kafka-console-consumer \
  --bootstrap-server $MSK_BROKERS --topic test-topic --from-beginning
```

---

## 🎯 다음 단계: Step 2

이제 **Step 2: Consumer Deployment + HPA (CPU 기준)**로 진행합니다.

### Step 2 목표
1. Kafka Consumer Deployment 생성
2. CPU 기반 HPA 설정
3. Kafka 부하 생성 및 Pod 스케일링 확인

### Step 2 준비사항
- [ ] Consumer Deployment 매니페스트 작성
- [ ] HPA 설정 추가
- [ ] 부하 생성 스크립트 준비
- [ ] 모니터링 대시보드 설정 (선택사항)

---

## 📝 참고사항

### 이미지 변경 이력
- 초기: `apache/kafka:3.6.0` (존재하지 않음)
- 변경: `confluentinc/cp-kafka:7.5.0` (사용 중)
- 대안: `bitnami/kafka:3.7.0` (ImagePullBackOff 발생)

### 명령어 차이점
- Confluent 이미지: `kafka-topics` (`.sh` 없음)
- Apache Kafka 표준: `kafka-topics.sh` (`.sh` 있음)

### Pod 상태 확인
```bash
kubectl get pods -n kafka -l app=kafka-client
kubectl logs -n kafka -l app=kafka-client
kubectl describe pod -n kafka -l app=kafka-client
```

---

## ✅ Step 1 체크리스트 완료

- [x] EKS 클러스터 연결 확인 (`kubectl get nodes`)
- [x] MSK Bootstrap Brokers Secret 생성 완료
- [x] kafka-client Pod 배포 및 Running 상태 확인
- [x] MSK 연결 테스트 성공 (토픽 목록 확인)
- [x] 테스트 토픽 생성 성공
- [x] Producer/Consumer 통신 테스트 성공
- [x] Kafka 지표 확인 완료 (토픽 상세 정보)

**Step 1 완료! 🎉**

