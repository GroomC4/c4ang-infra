# Terraform 재생성 후 K8s 설정 변경 체크리스트

## 개요

AWS 리소스를 Terraform으로 재생성한 후, 새로운 엔드포인트로 K8s 설정을 업데이트해야 합니다.

## 변경이 필요한 파일

### 1. 메인 설정 파일 (필수)

**파일:** `/config/prod/external-services.yaml`

이 파일이 모든 AWS 엔드포인트의 중앙 설정입니다:

| 리소스 | 현재 엔드포인트 | Terraform Output |
|--------|----------------|------------------|
| customer-db | c4-customer-db.cfkm648uqlug.ap-northeast-2.rds.amazonaws.com | `terraform output domain_rds_endpoints` |
| product-db | c4-product-db.cfkm648uqlug.ap-northeast-2.rds.amazonaws.com | ↑ |
| order-db | c4-order-db.cfkm648uqlug.ap-northeast-2.rds.amazonaws.com | ↑ |
| store-db | c4-store-db.cfkm648uqlug.ap-northeast-2.rds.amazonaws.com | ↑ |
| saga-db | c4-saga-db.cfkm648uqlug.ap-northeast-2.rds.amazonaws.com | ↑ |
| payment-db | c4-payment-db.cfkm648uqlug.ap-northeast-2.rds.amazonaws.com | ↑ |
| cache-redis | c4-cache-redis.97pni3.0001.apn2.cache.amazonaws.com | `terraform output elasticache_endpoint` |
| session-redis | c4-session-redis.97pni3.0001.apn2.cache.amazonaws.com | `terraform output session_redis_endpoint` |
| kafka-broker-1 | b-1.c4kafka.l9hkqg.c2.kafka.ap-northeast-2.amazonaws.com | `terraform output msk_bootstrap_brokers` |
| kafka-broker-2 | b-2.c4kafka.l9hkqg.c2.kafka.ap-northeast-2.amazonaws.com | ↑ |
| kafka-broker-3 | b-3.c4kafka.l9hkqg.c2.kafka.ap-northeast-2.amazonaws.com | ↑ |

### 2. MSK 설정 파일들

MSK bootstrap servers가 하드코딩된 파일들:

```
/config/prod/kafka/values.yaml
/config/prod/schema-registry/values.yaml
/helm-charts/ecommerce-apps/values-prod.yaml
```

현재 값:
```
b-1.c4kafka.l9hkqg.c2.kafka.ap-northeast-2.amazonaws.com:9092,
b-2.c4kafka.l9hkqg.c2.kafka.ap-northeast-2.amazonaws.com:9092,
b-3.c4kafka.l9hkqg.c2.kafka.ap-northeast-2.amazonaws.com:9092
```

## 업데이트 절차

### Step 1: Terraform Output 확인

```bash
cd /Users/castle/Workspace/c4ang-infra/external-services/terraform/production

# RDS 엔드포인트
terraform output domain_rds_endpoints

# ElastiCache 엔드포인트
terraform output elasticache_endpoint
terraform output session_redis_endpoint

# MSK Bootstrap Servers
terraform output msk_bootstrap_brokers
```

### Step 2: external-services.yaml 업데이트

```bash
vim /Users/castle/Workspace/c4ang-infra/config/prod/external-services.yaml

# 또는 sed 사용
# RDS 예시:
sed -i '' 's/cfkm648uqlug/NEW_RDS_ID/g' config/prod/external-services.yaml

# ElastiCache 예시:
sed -i '' 's/97pni3/NEW_CACHE_ID/g' config/prod/external-services.yaml

# MSK 예시:
sed -i '' 's/l9hkqg/NEW_MSK_ID/g' config/prod/external-services.yaml
```

### Step 3: MSK 설정 업데이트

```bash
# kafka values
sed -i '' 's/l9hkqg/NEW_MSK_ID/g' config/prod/kafka/values.yaml

# schema-registry values
sed -i '' 's/l9hkqg/NEW_MSK_ID/g' config/prod/schema-registry/values.yaml

# ecommerce-apps values
sed -i '' 's/l9hkqg/NEW_MSK_ID/g' helm-charts/ecommerce-apps/values-prod.yaml
```

### Step 4: K8s ExternalName 서비스 재적용

```bash
# Helm으로 external-services 재배포
cd /Users/castle/Workspace/c4ang-infra
helm upgrade --install external-services ./helm-charts/external-services \
  -n ecommerce \
  -f config/prod/external-services.yaml
```

### Step 5: ArgoCD Sync

```bash
# 모든 애플리케이션 동기화
argocd app sync customer-service-dev --force
argocd app sync store-service-dev --force
argocd app sync product-service-dev --force
argocd app sync order-service-dev --force
argocd app sync payment-service-dev --force
argocd app sync saga-tracker-dev --force
```

## 주의사항

1. **RDS 비밀번호**: Terraform에서 새로 생성되므로 K8s Secret도 업데이트 필요
   - `terraform output domain_rds_credentials` 확인
   - Secret 업데이트: `kubectl create secret generic db-credentials ...`

2. **스냅샷 복원**: 기존 데이터가 필요하면 RDS 스냅샷에서 복원
   - 스냅샷 목록: `aws rds describe-db-snapshots --query 'DBSnapshots[*].[DBSnapshotIdentifier,Status]'`

3. **Kafka 토픽**: MSK 재생성 시 토픽도 재생성됨
   - 토픽 목록은 애플리케이션이 자동 생성 (auto.create.topics.enable=true)

## 자동화 스크립트

재생성 후 설정 업데이트를 자동화하는 스크립트:

```bash
#!/bin/bash
# /scripts/cost-control/update-endpoints-after-recreation.sh

cd /Users/castle/Workspace/c4ang-infra/external-services/terraform/production

# Terraform output에서 새 엔드포인트 추출
RDS_ENDPOINTS=$(terraform output -json domain_rds_endpoints)
MSK_BROKERS=$(terraform output -raw msk_bootstrap_brokers)
CACHE_ENDPOINT=$(terraform output -raw elasticache_endpoint)

echo "New MSK Brokers: $MSK_BROKERS"
echo "New Cache Endpoint: $CACHE_ENDPOINT"
echo "New RDS Endpoints: $RDS_ENDPOINTS"

# TODO: sed로 설정 파일 자동 업데이트
```

---

## 현재 상태 (2025-12-08)

- [x] RDS 스냅샷 백업 완료 (7개)
- [x] Terraform plan 검증 완료 (151개 리소스)
- [x] K8s 설정 변경 필요 사항 문서화
- [ ] 기존 AWS 리소스 삭제
- [ ] Terraform apply 실행
- [ ] 새 엔드포인트로 K8s 설정 업데이트
- [ ] ArgoCD 동기화
