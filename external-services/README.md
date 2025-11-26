# External Services

MSA 서비스가 의존하는 외부 데이터 서비스를 관리합니다.
ArgoCD로 애플리케이션을 배포하기 **전에** 이 서비스들이 먼저 실행되어야 합니다.

## 디렉토리 구조

```
external-services/
├── local/                    # 로컬 개발 환경 (Docker Compose)
│   ├── docker-compose.yaml   # PostgreSQL, Redis, Kafka
│   └── .env.example          # 환경 변수 예시
│
├── aws/                      # AWS 프로덕션 환경 (Terraform)
│   ├── main.tf               # 메인 설정
│   ├── variables.tf          # 변수 정의
│   ├── outputs.tf            # 출력값
│   └── terraform.tfvars.example
│
└── README.md
```

## 외부 서비스 목록

| 서비스 | 로컬 환경 | AWS 환경 | 용도 |
|-------|----------|---------|------|
| PostgreSQL (5개) | Docker | RDS PostgreSQL | 서비스별 DB |
| Redis (2개) | Docker | ElastiCache | 캐시, 세션 |
| Kafka | Docker (Strimzi) | MSK | 이벤트 스트리밍 |

### 서비스별 데이터베이스

| 서비스 | 데이터베이스 | 포트 (로컬) |
|-------|------------|------------|
| customer-service | customer_db | 5432 |
| product-service | product_db | 5433 |
| order-service | order_db | 5434 |
| store-service | store_db | 5435 |
| saga-tracker | saga_db | 5436 |

### Redis 인스턴스

| 용도 | 인스턴스 | 포트 (로컬) |
|-----|---------|------------|
| 캐시 | cache-redis | 6379 |
| 세션 | session-redis | 6380 |

## 사용법

### 로컬 환경 (Docker Compose)

```bash
cd external-services/local

# 환경 변수 설정
cp .env.example .env

# 서비스 시작
docker-compose up -d

# 상태 확인
docker-compose ps

# 로그 확인
docker-compose logs -f

# 서비스 중지
docker-compose down

# 볼륨 포함 삭제 (데이터 초기화)
docker-compose down -v
```

### AWS 환경 (Terraform)

```bash
cd external-services/aws

# 초기화
terraform init

# 계획 확인
terraform plan

# 적용
terraform apply

# 삭제
terraform destroy
```

## K8s에서 외부 서비스 접근

외부 서비스에 접근하기 위해 ExternalName Service를 사용합니다.
`charts/external-services/` Helm 차트를 참고하세요.

```yaml
# 예시: customer-db ExternalName Service
apiVersion: v1
kind: Service
metadata:
  name: customer-db
  namespace: ecommerce
spec:
  type: ExternalName
  externalName: customer-db.local  # 로컬
  # externalName: customer-db.xxx.rds.amazonaws.com  # AWS
```

## 배포 순서

1. **External Services 시작** (이 디렉토리)
   ```bash
   # 로컬
   cd external-services/local && docker-compose up -d

   # AWS
   cd external-services/aws && terraform apply
   ```

2. **ExternalName Services 배포**
   ```bash
   helm upgrade --install external-services charts/external-services \
     -f config/local/external-services.yaml \
     -n ecommerce --create-namespace
   ```

3. **ArgoCD로 애플리케이션 배포**
   ```bash
   ./scripts/platform/argocd.sh
   ```
