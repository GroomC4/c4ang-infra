# 로컬 개발 환경 설정 가이드

이 문서는 k3d 기반 로컬 개발 환경에서 외부 데이터 서비스(PostgreSQL, Redis, Kafka, Schema Registry)를 docker-compose로 실행하고, Kubernetes ExternalName 서비스를 통해 연결하는 방법을 설명합니다.

## 아키텍처 개요

```
┌─────────────────────────────────────────────────────────────────┐
│                        로컬 개발 환경                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────┐    ┌─────────────────────────────┐ │
│  │       k3d 클러스터        │    │     Docker Compose          │ │
│  │                         │    │                             │ │
│  │  ┌───────────────────┐  │    │  ┌─────────────────────┐    │ │
│  │  │  Domain Services  │  │    │  │  PostgreSQL DBs     │    │ │
│  │  │  - customer       │  │    │  │  - customer-db:5432 │    │ │
│  │  │  - product        │  │    │  │  - product-db:5433  │    │ │
│  │  │  - order          │──┼────┼──│  - order-db:5434    │    │ │
│  │  │  - store          │  │    │  │  - store-db:5435    │    │ │
│  │  │  - saga-tracker   │  │    │  │  - saga-db:5436     │    │ │
│  │  │  - payment        │  │    │  │  - payment-db:5437  │    │ │
│  │  │  - recommendation │  │    │  │  - recommendation   │    │ │
│  │  └───────────────────┘  │    │  │    -db:5438         │    │ │
│  │           │             │    │  └─────────────────────┘    │ │
│  │           │             │    │                             │ │
│  │  ┌───────────────────┐  │    │  ┌─────────────────────┐    │ │
│  │  │ ExternalName Svc  │  │    │  │  Redis              │    │ │
│  │  │ - customer-db     │──┼────┼──│  - cache:6379       │    │ │
│  │  │ - cache-redis     │  │    │  │  - session:6380     │    │ │
│  │  │ - kafka           │  │    │  └─────────────────────┘    │ │
│  │  │ - schema-registry │  │    │                             │ │
│  │  └───────────────────┘  │    │  ┌─────────────────────┐    │ │
│  │                         │    │  │  Kafka & Registry   │    │ │
│  └─────────────────────────┘    │  │  - kafka:9092/9094  │    │ │
│                                 │  │  - schema-reg:8081  │    │ │
│                                 │  └─────────────────────┘    │ │
│                                 └─────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

## 사전 요구사항

- Docker Desktop
- k3d
- kubectl
- Helm

## 빠른 시작

### 1. 외부 데이터 서비스 실행

```bash
cd external-services/docker

# 전체 서비스 실행
./start.sh

# Kafka UI 포함 실행 (localhost:8080)
./start.sh --ui

# DB만 실행
./start.sh --db-only

# 상태 확인
./start.sh --status

# 서비스 종료
./stop.sh

# 서비스 종료 + 볼륨 삭제 (데이터 초기화)
./stop.sh --clean
```

### 2. k3d 클러스터 생성

```bash
./scripts/bootstrap/create-cluster.sh
```

### 3. ExternalName 서비스 배포

```bash
helm upgrade --install external-services ./charts/external-services \
  -f config/local/external-services.yaml \
  -n ecommerce --create-namespace
```

## 서비스 포트 매핑

### PostgreSQL 데이터베이스

| 서비스 | 호스트 포트 | 컨테이너 포트 | 데이터베이스명 |
|--------|------------|--------------|---------------|
| customer-db | 5432 | 5432 | customer_db |
| product-db | 5433 | 5432 | product_db |
| order-db | 5434 | 5432 | order_db |
| store-db | 5435 | 5432 | store_db |
| saga-db | 5436 | 5432 | saga_db |
| payment-db | 5437 | 5432 | payment_db |
| recommendation-db | 5438 | 5432 | recommendation_db |

### Redis

| 서비스 | 호스트 포트 | 용도 |
|--------|------------|------|
| cache-redis | 6379 | 애플리케이션 캐시 |
| session-redis | 6380 | 세션 저장소 |

### Kafka & Schema Registry

| 서비스 | 포트 | 설명 |
|--------|------|------|
| kafka | 9092 | 내부 통신 (클러스터 내) |
| kafka | 9094 | 외부 통신 (로컬 테스트) |
| schema-registry | 8081 | Avro 스키마 관리 |
| kafka-ui | 8080 | Kafka UI (--ui 옵션) |

## ExternalName 서비스 연결 방식

k3d 클러스터 내 Pod에서 docker-compose 서비스에 접근할 때는 Kubernetes ExternalName 서비스를 통해 연결합니다.

### ExternalName 서비스 동작 원리

```yaml
# charts/external-services/templates/postgresql-services.yaml
apiVersion: v1
kind: Service
metadata:
  name: customer-db
  namespace: ecommerce
spec:
  type: ExternalName
  externalName: host.docker.internal  # Docker Desktop 호스트
  ports:
    - port: 5432
      targetPort: 5432
```

### 도메인 서비스 연결 설정

로컬 환경의 도메인 서비스는 ExternalName 서비스 이름을 사용합니다:

```yaml
# config/local/customer-service.yaml
env:
  - name: SPRING_DATASOURCE_MASTER_URL
    value: "jdbc:postgresql://customer-db:5432/customer_db"
  - name: SPRING_REDIS_HOST
    value: "cache-redis"
  - name: SPRING_KAFKA_BOOTSTRAP_SERVERS
    value: "kafka:9092"
```

## 환경별 설정

### 로컬 환경 (k3d + docker-compose)

- `config/local/external-services.yaml`: ExternalName → `host.docker.internal`
- `config/local/*-service.yaml`: 각 도메인 서비스 설정

### 프로덕션 환경 (EKS + AWS 관리형 서비스)

- `config/prod/external-services.yaml`: ExternalName → AWS RDS/ElastiCache 엔드포인트
- `config/prod/*-service.yaml`: 프로덕션 도메인 서비스 설정

## DB 스키마 초기화

각 DB의 초기 스키마는 `external-services/docker/init-scripts/` 디렉토리에 SQL 파일로 관리됩니다.

```
external-services/docker/init-scripts/
├── customer-db/
│   └── 01-init-schema.sql
├── product-db/
│   └── 01-init-schema.sql
├── order-db/
│   └── .gitkeep
├── store-db/
│   └── 01-init-schema.sql
├── saga-db/
│   └── .gitkeep
├── payment-db/
│   └── .gitkeep
└── recommendation-db/
    └── .gitkeep
```

PostgreSQL 컨테이너 시작 시 `/docker-entrypoint-initdb.d/` 디렉토리의 SQL 파일이 자동 실행됩니다.

## 트러블슈팅

### docker-compose 서비스 연결 실패

1. docker-compose 서비스가 실행 중인지 확인:
   ```bash
   cd external-services/docker && ./start.sh --status
   ```

2. ExternalName 서비스가 배포되었는지 확인:
   ```bash
   kubectl get svc -n ecommerce
   ```

3. `host.docker.internal` DNS 해석 확인:
   ```bash
   kubectl run -it --rm debug --image=busybox -- nslookup host.docker.internal
   ```

### Kafka 연결 문제

- k3d 클러스터 내에서는 `kafka:9092` 사용
- 로컬 호스트에서 직접 테스트 시 `localhost:9094` 사용

### 데이터 초기화

```bash
cd external-services/docker
./stop.sh --clean  # 볼륨 삭제
./start.sh         # 재시작 (스키마 재적용)
```

## 관련 파일

- `external-services/docker/docker-compose.yaml`: Docker Compose 설정
- `external-services/docker/start.sh`: 서비스 시작 스크립트
- `external-services/docker/stop.sh`: 서비스 종료 스크립트
- `charts/external-services/`: ExternalName 서비스 Helm 차트
- `config/local/`: 로컬 환경 설정
- `config/prod/`: 프로덕션 환경 설정
