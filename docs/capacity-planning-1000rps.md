# C4ang 트래픽 처리 능력 확장 계획

## 목표 수치

| 지표 | 목표값 | 비고 |
|------|--------|------|
| API RPS (피크) | 1,000 | 초당 API 요청 처리 |
| 이벤트 처리량 | 800 events/sec | Kafka Consumer 처리 |
| MAU | ~500만 | 월간 활성 사용자 |
| DAU | ~90만 | 일간 활성 사용자 |
| 피크 동시접속 | ~5만 | 최대 동시 사용자 |

---

## 현재 상태 분석

### 인프라 현황

| 구성 요소 | 현재 설정 | 처리 능력 |
|----------|----------|----------|
| EKS 노드 (high-traffic) | 2× t3.large | ~720 RPS |
| Pod (서비스당) | 2 replicas | - |
| Kafka 파티션 | 3개/topic | ~600 events/sec |
| DB Connection Pool | 10개/서비스 | 50개 총 |
| Consumer Concurrency | 1~3 | 불균일 |

### 현재 처리 능력

```
API RPS:        ~480 (평상시) / ~1,200 (HPA 확장)
이벤트 처리:    ~600 events/sec
완료 주문:      ~100 주문/sec
```

---

## 변경 필요 리소스

### 1. Kubernetes 설정 (c4ang-infra)

#### 1.1 Pod Replicas 증가

| 파일 | 항목 | 현재 | 변경 |
|------|------|------|------|
| `config/prod/customer-service.yaml` | replicaCount | 2 | **3** |
| `config/prod/order-service.yaml` | replicaCount | 2 | **3** |
| `config/prod/payment-service.yaml` | replicaCount | 2 | **3** |
| `config/prod/product-service.yaml` | replicaCount | 2 | **3** |
| `config/prod/store-service.yaml` | replicaCount | 2 | 2 (유지) |

#### 1.2 노드 그룹 확장

| 파일 | 항목 | 현재 | 변경 |
|------|------|------|------|
| `external-services/terraform/production/variables.tf` | high_traffic.desired_size | 2 | **3** |
| | high_traffic.max_size | 5 | 5 (유지) |

---

### 2. Application 설정 (각 서비스 레포지토리)

#### 2.1 DB Connection Pool 증가

| 서비스 | 파일 | 현재 | 변경 |
|--------|------|------|------|
| c4ang-customer-service | `customer-api/src/main/resources/application-prod.yml` | 10 | **15** |
| c4ang-order-service | `order-api/src/main/resources/application-prod.yml` | 10 | **15** |
| c4ang-payment-service | `payment-api/src/main/resources/application-prod.yml` | 10 | **15** |
| c4ang-product-service | `product-api/src/main/resources/application-prod.yml` | 10 | **15** |
| c4ang-store-service | `store-api/src/main/resources/application-prod.yml` | 10 | 10 (유지) |

**변경 내용:**
```yaml
spring:
  datasource:
    master:
      hikari:
        maximum-pool-size: 15  # 10 → 15
        minimum-idle: 8        # 5 → 8
    replica:
      hikari:
        maximum-pool-size: 15  # 10 → 15
        minimum-idle: 8        # 5 → 8
```

#### 2.2 Kafka Consumer Concurrency 통일

| 서비스 | 파일 | 현재 | 변경 |
|--------|------|------|------|
| c4ang-order-service | `KafkaConsumerConfig.kt` | 3 | 3 (유지) |
| c4ang-payment-service | `KafkaConsumerConfig.kt` | 1 | **3** |
| c4ang-product-service | `KafkaConsumerConfig.kt` | 1 | **3** |

**변경 내용 (payment-service 예시):**
```kotlin
// KafkaConsumerConfig.kt
@Bean
fun kafkaListenerContainerFactory(): ConcurrentKafkaListenerContainerFactory<String, Any> {
    val factory = ConcurrentKafkaListenerContainerFactory<String, Any>()
    factory.consumerFactory = consumerFactory()
    factory.containerProperties.ackMode = ContainerProperties.AckMode.MANUAL
    factory.setConcurrency(3)  // 추가
    return factory
}
```

---

## 변경 파일 목록

### c4ang-infra (5개 파일)

```
config/prod/customer-service.yaml    - replicaCount: 3
config/prod/order-service.yaml       - replicaCount: 3
config/prod/payment-service.yaml     - replicaCount: 3
config/prod/product-service.yaml     - replicaCount: 3
external-services/terraform/production/variables.tf - desired_size: 3
```

### c4ang-customer-service (1개 파일)

```
customer-api/src/main/resources/application-prod.yml - hikari pool: 15
```

### c4ang-order-service (1개 파일)

```
order-api/src/main/resources/application-prod.yml - hikari pool: 15
```

### c4ang-payment-service (2개 파일)

```
payment-api/src/main/resources/application-prod.yml - hikari pool: 15
payment-api/src/main/kotlin/.../KafkaConsumerConfig.kt - concurrency: 3
```

### c4ang-product-service (2개 파일)

```
product-api/src/main/resources/application-prod.yml - hikari pool: 15
product-api/src/main/kotlin/.../KafkaConsumerConfig.kt - concurrency: 3
```

**총 11개 파일 변경**

---

## 변경 후 예상 수치

### 처리 능력

| 지표 | 현재 | 변경 후 | 목표 | 달성 |
|------|------|---------|------|------|
| API RPS (평상시) | ~480 | ~720 | - | - |
| API RPS (피크) | ~1,200 | ~1,500 | 1,000 | ✅ |
| 이벤트 처리량 | ~600 | ~1,200 | 800 | ✅ |
| 완료 주문/sec | ~100 | ~200 | - | - |

### 사용자 수용량

| 지표 | 현재 | 변경 후 |
|------|------|---------|
| MAU | ~250만 | **~500만** |
| DAU | ~45만 | **~90만** |
| 피크 동시접속 | ~2.5만 | **~5만** |
| 월 주문 수 | ~12만 | **~25만** |

---

## 비용 영향

### 월간 예상 비용

| 항목 | 현재 | 변경 후 | 차이 |
|------|------|---------|------|
| EKS 노드 (high-traffic) | 2× t3.large | 3× t3.large | +$60 |
| Pod 리소스 | 10 pods | 14 pods | - |
| **월 예상 비용** | ~$150 | **~$210** | **+$60** |

※ 온디맨드 기준, 실제 사용량에 따라 변동

---

## 배포 순서

### Phase 1: 인프라 확장 (c4ang-infra)

1. 노드 그룹 확장 (Terraform)
   ```bash
   cd external-services/terraform/production
   terraform plan
   terraform apply
   ```

2. Pod Replicas 증가 (ArgoCD 자동 배포)
   - config/prod/*.yaml 변경 후 push
   - ArgoCD sync 대기

### Phase 2: 애플리케이션 설정 (각 서비스)

1. Connection Pool 증가
   - application-prod.yml 수정
   - 서비스별 순차 배포

2. Consumer Concurrency 증가
   - KafkaConsumerConfig.kt 수정
   - payment-service, product-service 배포

### Phase 3: 검증

1. 부하 테스트 수행
   ```bash
   # k6 또는 locust 사용
   k6 run --vus 100 --duration 5m load-test.js
   ```

2. 모니터링 확인
   - Grafana 대시보드
   - Kafka Consumer Lag
   - DB Connection 사용량

---

## 롤백 계획

### 문제 발생 시

1. **Pod 장애**: HPA가 자동 복구, replicaCount 원복
2. **노드 부족**: desired_size 원복 (2)
3. **DB Connection 고갈**: pool size 원복 (10)
4. **Consumer 지연**: concurrency 원복 (1)

### 롤백 명령어

```bash
# Terraform 롤백
cd external-services/terraform/production
terraform apply -var="high_traffic_desired_size=2"

# ArgoCD 롤백
argocd app rollback <app-name>
```

---

## 향후 확장 계획

### 1,000 RPS 이상 필요 시

| 조치 | 효과 | 비용 영향 |
|------|------|----------|
| Kafka 파티션 6개로 증가 | 이벤트 처리 2배 | 없음 |
| RDS db.t3.small 업그레이드 | DB 병목 해소 | +$30/월 |
| Redis 클러스터 모드 | 캐시 확장 | +$50/월 |
| 노드 그룹 max_size 10 | 대규모 확장 | 사용량 기반 |

### 예상 확장 경로

```
현재 (500만 MAU) → Phase 2 (1000만 MAU) → Phase 3 (2000만 MAU)
     ↓                    ↓                      ↓
   $210/월              $350/월               $600/월
```

---

## 문서 정보

- **작성일**: 2025-12-10
- **버전**: 1.0
- **작성**: Claude Code
- **대상 환경**: AWS EKS Production
