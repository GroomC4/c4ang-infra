# 다음 단계 가이드

## ✅ 현재까지 완료된 작업

- [x] MSK Terraform 코드 작성 (`msk.tf`)
- [x] S3 버킷 설정 (`c4-tracking-log` 포함)
- [x] Terraform 테스트 스크립트 (`scripts/test-terraform.sh`)
- [x] 구문 오류 수정
- [x] kafka-client 배포 매니페스트 준비

---

## 🎯 다음 단계: 1단계 - MSK + EKS 기본 통신 테스트

### Step 1: Terraform 테스트 및 배포 준비

```bash
cd external-services/terraform/production

# 1. 테스트 실행 (실제 배포 없이 검증)
./scripts/test-terraform.sh

# 2. terraform.tfvars 설정 확인/수정
# MSK 활성화 및 기본 설정 확인
cat terraform.tfvars | grep -E "create_msk|msk_"
```

### Step 2: MSK 배포 (선택사항)

**주의:** MSK는 비용이 높으므로 실제 테스트가 필요할 때만 배포하세요.

```bash
# terraform.tfvars에 추가
create_msk = true
msk_instance_type = "kafka.t3.small"  # 테스트용 (비용 절감)
msk_kafka_version = "3.7.0"  # KRaft 모드
msk_ebs_volume_size = 100

# 배포 (15-20분 소요)
terraform plan
terraform apply
```

### Step 3: MSK 연결 정보 확인

```bash
# Bootstrap Brokers 확인
terraform output msk_bootstrap_brokers

# 클러스터 ARN 확인
terraform output msk_cluster_arn
```

### Step 4: kafka-client 배포 및 테스트

```bash
# MSK Bootstrap Brokers를 Secret에 저장
MSK_BROKERS=$(terraform output -raw msk_bootstrap_brokers)

# Secret 생성
kubectl create namespace kafka --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic msk-bootstrap-brokers \
  --from-literal=bootstrap-brokers="$MSK_BROKERS" \
  -n kafka

# kafka-client 배포
kubectl apply -f k8s/msk-kafka-client.yaml

# Pod 준비 대기
kubectl wait --for=condition=ready pod -l app=kafka-client -n kafka --timeout=60s

# 연결 테스트
KAFKA_CLIENT_POD=$(kubectl get pod -n kafka -l app=kafka-client -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n kafka "$KAFKA_CLIENT_POD" -- \
  /opt/kafka/bin/kafka-broker-api-versions.sh \
  --bootstrap-server "$MSK_BROKERS"
```

### Step 5: 토픽 생성

```bash
cd k8s
chmod +x create-msk-topics.sh
./create-msk-topics.sh "$MSK_BROKERS"
```

---

## 🎯 2단계: Consumer Deployment + HPA (준비 필요)

### 필요한 작업

1. **Kafka Consumer Deployment 생성**
   - MSK에서 메시지를 소비하는 간단한 Consumer 앱
   - CPU 부하를 생성할 수 있는 설정

2. **HPA 설정**
   - CPU 기반 스케일링
   - 최소/최대 Pod 수 설정

3. **부하 생성 스크립트**
   - Kafka Producer로 대량 메시지 전송
   - Pod 스케일업 확인

### 예상 파일 구조

```
k8s/
├── kafka-consumer-deployment.yaml  # Consumer Deployment
├── kafka-consumer-hpa.yaml         # HPA 설정
└── kafka-load-generator.sh         # 부하 생성 스크립트
```

---

## 🎯 3단계: Karpenter 설정 (준비 필요)

### 필요한 작업

1. **Karpenter Terraform 모듈**
   - IAM 역할 및 정책
   - NodePool 및 NodeClass 설정

2. **테스트 시나리오**
   - Pod Pending 상태 생성
   - 노드 자동 생성 확인

### 예상 파일 구조

```
terraform/
├── karpenter.tf                    # Karpenter 리소스
└── k8s/
    └── karpenter-nodepool.yaml     # NodePool 설정
```

---

## 🎯 4단계: KEDA 설정 (준비 필요)

### 필요한 작업

1. **KEDA 설치**
   - Helm Chart로 설치
   - Kafka ScaledObject 생성

2. **Kafka Lag 기반 스케일링**
   - Consumer Group Lag 모니터링
   - Lag 증가 시 Pod 자동 스케일업

### 예상 파일 구조

```
k8s/
├── keda-install.yaml              # KEDA 설치
└── keda-scaledobject.yaml         # Kafka ScaledObject
```

---

## 📋 체크리스트

### 1단계: MSK 기본 통신 테스트
- [ ] Terraform 테스트 통과 (`./scripts/test-terraform.sh`)
- [ ] MSK 배포 (또는 기존 MSK 사용)
- [ ] MSK Bootstrap Brokers 확인
- [ ] kafka-client Pod 배포 및 실행 확인
- [ ] MSK 연결 테스트 성공
- [ ] 토픽 생성 완료
- [ ] Producer/Consumer 테스트 성공

### 2단계: Consumer + HPA (준비 필요)
- [ ] Kafka Consumer Deployment 생성
- [ ] HPA 설정 및 배포
- [ ] 부하 생성 스크립트 작성
- [ ] CPU 부하 시 Pod 스케일업 확인

### 3단계: Karpenter (준비 필요)
- [ ] Karpenter Terraform 코드 작성
- [ ] Karpenter 설치
- [ ] NodePool 및 NodeClass 설정
- [ ] Pod Pending → 노드 자동 생성 확인

### 4단계: KEDA (준비 필요)
- [ ] KEDA 설치
- [ ] Kafka ScaledObject 생성
- [ ] Kafka Lag 기반 스케일링 테스트

---

## 🚀 빠른 시작

지금 바로 시작하려면:

```bash
cd external-services/terraform/production

# 1. 테스트 실행
./scripts/test-terraform.sh

# 2. MSK 배포 (필요시)
# terraform.tfvars에 create_msk = true 추가 후
terraform plan
terraform apply

# 3. kafka-client 배포 및 테스트
# QUICKSTART_MSK.md 참고
cat QUICKSTART_MSK.md
```

---

## 📚 참고 문서

- **MSK 빠른 시작**: [`QUICKSTART_MSK.md`](./QUICKSTART_MSK.md)
- **MSK 상세 가이드**: [`k8s/msk-test-guide.md`](./k8s/msk-test-guide.md)
- **MSK KRaft 정보**: [`MSK_KRaft_INFO.md`](./MSK_KRaft_INFO.md)
- **Terraform 테스트**: [`TERRAFORM_TESTING_GUIDE.md`](./TERRAFORM_TESTING_GUIDE.md)

---

## 💡 다음 작업 제안

**권장 순서:**
1. ✅ **1단계 완료 후 2단계 진행** (디버깅 용이)
   - 1단계: MSK + EKS + kafka-client 기본 통신 테스트
   - 2단계: Consumer Deployment + HPA 코드 작성

**지금 할 수 있는 것:**
1. ✅ Terraform 테스트 실행 (`./scripts/test-terraform.sh`)
2. ✅ MSK 배포 및 기본 통신 테스트 (1단계)
   - 상세 체크리스트: [`STEP1_CHECKLIST.md`](./STEP1_CHECKLIST.md)

**1단계 완료 후:**
- 2단계 코드 작성 (Consumer Deployment + HPA)
- 3단계 코드 작성 (Karpenter)
- 4단계 코드 작성 (KEDA)

---

## 📋 1단계 체크리스트

자세한 1단계 테스트 가이드는 [`STEP1_CHECKLIST.md`](./STEP1_CHECKLIST.md)를 참고하세요.

**1단계 완료 기준:**
- [ ] MSK 클러스터 배포 완료
- [ ] kafka-client Pod로 MSK 연결 성공
- [ ] 토픽 생성 및 메시지 전송/수신 테스트 성공
- [ ] Kafka 지표 확인 가능

**1단계 완료 후 알려주시면 2단계 코드를 작성하겠습니다!** 🚀

