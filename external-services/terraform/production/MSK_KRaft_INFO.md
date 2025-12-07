# MSK KRaft 모드 정보

## 📋 KRaft vs Zookeeper

### KRaft 모드 (권장) ✅

**장점:**
- ✅ **Zookeeper 불필요**: 별도의 Zookeeper 클러스터 관리 불필요
- ✅ **확장성 향상**: 클러스터당 더 많은 브로커 지원 (수천 개까지)
- ✅ **운영 복잡성 감소**: 메타데이터 관리가 Kafka 내부에서 처리됨
- ✅ **성능 향상**: 메타데이터 변경 시 더 빠른 처리
- ✅ **미래 지향적**: Apache Kafka의 표준 방향

**요구사항:**
- Kafka 버전 3.7 이상 필요
- MSK가 자동으로 KRaft 모드로 설정됨

### Zookeeper 모드 (레거시)

**단점:**
- ❌ Zookeeper 클러스터 관리 필요
- ❌ 확장성 제한 (수백 개 브로커)
- ❌ 운영 복잡성 증가
- ❌ Kafka 4.0부터 제거 예정

---

## 🔧 현재 설정

### 기본값: KRaft 모드 사용

```hcl
# variables.tf
variable "msk_kafka_version" {
  default = "3.7.0"  # KRaft 모드 지원
}

variable "msk_use_kraft" {
  default = true  # KRaft 모드 사용
}
```

### Zookeeper 모드로 변경하려면

```hcl
# terraform.tfvars
msk_kafka_version = "3.6.0"  # 또는 이전 버전
msk_use_kraft = false
```

---

## 🚀 KRaft 모드 사용 시

### Security Group

KRaft 모드에서는 **Zookeeper 포트(2181)가 필요 없습니다**.

```hcl
# msk.tf에서 자동으로 처리됨
# msk_use_kraft = true일 때 Zookeeper 포트 제외
```

### 연결 정보

KRaft 모드와 Zookeeper 모드 모두 동일한 방식으로 연결:

```bash
# Bootstrap Brokers는 동일
terraform output msk_bootstrap_brokers
```

### 토픽 생성/관리

KRaft 모드에서도 기존 Kafka 명령어와 동일하게 사용:

```bash
# 토픽 생성
kafka-topics.sh --bootstrap-server $MSK_BROKERS --create --topic test-topic

# Consumer Group 관리
kafka-consumer-groups.sh --bootstrap-server $MSK_BROKERS --list
```

---

## 📊 비교표

| 항목 | KRaft 모드 | Zookeeper 모드 |
|------|-----------|---------------|
| Kafka 버전 | 3.7+ | 3.6 이하 |
| Zookeeper 필요 | ❌ 없음 | ✅ 필요 |
| 최대 브로커 수 | 수천 개 | 수백 개 |
| 메타데이터 관리 | Kafka 내부 | Zookeeper |
| 운영 복잡성 | 낮음 | 높음 |
| 성능 | 빠름 | 상대적으로 느림 |
| 미래 호환성 | ✅ 유지 | ❌ 4.0에서 제거 예정 |

---

## ✅ 권장사항

1. **신규 클러스터**: 반드시 KRaft 모드 사용 (Kafka 3.7+)
2. **기존 클러스터**: 마이그레이션 계획 수립
3. **프로덕션**: KRaft 모드 + Kafka 3.7 이상 사용

---

## 🔍 확인 방법

### MSK 클러스터 모드 확인

```bash
# AWS CLI로 확인
aws kafka describe-cluster \
  --cluster-arn $(terraform output -raw msk_cluster_arn) \
  --query 'ClusterInfo.CurrentVersion' \
  --output text

# Kafka 3.7 이상이면 KRaft 모드
```

### Terraform 출력 확인

```bash
terraform output msk_connection_info
# kraft_mode: true/false 확인
```

---

## 📚 참고 자료

- [AWS MSK KRaft 모드 발표](https://aws.amazon.com/ko/about-aws/whats-new/2024/05/amazon-msk-kraft-mode-apache-kafka-clusters/)
- [Apache Kafka KRaft 문서](https://kafka.apache.org/documentation/#kraft)
- [MSK KRaft 모드 가이드](https://docs.aws.amazon.com/msk/latest/developerguide/kraft.html)

