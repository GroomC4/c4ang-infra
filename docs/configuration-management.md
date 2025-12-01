# 서비스 설정 관리 구조

이 문서는 Helm 차트의 환경 변수 및 설정 관리 구조를 설명합니다.

## 개요

모든 서비스는 다음 패턴을 사용하여 환경 변수를 관리합니다:

- **ConfigMap**: 비민감한 애플리케이션 설정
- **Secret**: 민감한 데이터 (비밀번호, 인증 정보 등)
- **envFrom**: ConfigMap과 Secret을 환경 변수로 일괄 주입

## 파일 구조

```
charts/services/<service-name>/
├── templates/
│   ├── configmap.yaml    # 비민감 설정 → ConfigMap
│   ├── secret.yaml       # 민감 설정 → Secret
│   └── rollout.yaml      # envFrom으로 설정 주입
└── values.yaml           # 기본값 (prod 환경)

config/
├── dev/
│   └── <service-name>.yaml   # k3d 개발 환경 오버라이드
└── prod/
    └── <service-name>.yaml   # 프로덕션 환경 오버라이드
```

## Values 구조

### 기본 values.yaml (charts/services/<service-name>/values.yaml)

```yaml
# 이미지 설정 - 환경별 config 파일에서 설정
image:
  repository: ""  # config/dev/*.yaml 또는 config/prod/*.yaml에서 설정
  pullPolicy: IfNotPresent
  tag: ""         # config/dev/*.yaml 또는 config/prod/*.yaml에서 설정

# 비민감 애플리케이션 설정 (ConfigMap으로 주입)
config:
  SERVER_PORT: "8081"
  SPRING_PROFILES_ACTIVE: "prod"
  SPRING_DATASOURCE_MASTER_URL: "jdbc:postgresql://..."
  SPRING_DATASOURCE_REPLICA_URL: "jdbc:postgresql://..."
  SPRING_DATA_REDIS_HOST: "redis-master"
  SPRING_DATA_REDIS_PORT: "6379"

# 민감 데이터 (Secret으로 주입)
secrets:
  SPRING_DATASOURCE_MASTER_USERNAME: ""
  SPRING_DATASOURCE_MASTER_PASSWORD: ""
  SPRING_DATASOURCE_REPLICA_USERNAME: ""
  SPRING_DATASOURCE_REPLICA_PASSWORD: ""
  SPRING_REDIS_PASSWORD: ""
  SPRING_REDISSON_PASSWORD: ""

# 추가 환경 변수 (선택적, env로 직접 주입)
extraEnv: []
```

### 환경별 오버라이드 (config/dev/<service-name>.yaml)

```yaml
# 이미지 설정
image:
  repository: 963403601423.dkr.ecr.ap-northeast-2.amazonaws.com/c4ang-<service-name>
  pullPolicy: IfNotPresent
  tag: "v1.0.0"

# ECR 이미지 pull을 위한 secret
imagePullSecrets:
  - name: ecr-secret

# 개발 환경용 설정
config:
  SPRING_PROFILES_ACTIVE: "dev"
  SPRING_DATASOURCE_MASTER_URL: "jdbc:postgresql://<service>-db:5432/<service>_db"
  SPRING_DATASOURCE_REPLICA_URL: "jdbc:postgresql://<service>-db:5432/<service>_db"
  SPRING_DATA_REDIS_HOST: "cache-redis"
  SPRING_KAFKA_BOOTSTRAP_SERVERS: "kafka:9092"

# 개발 환경용 비밀번호
secrets:
  SPRING_DATASOURCE_MASTER_USERNAME: "postgres"
  SPRING_DATASOURCE_MASTER_PASSWORD: "postgres"
```

## 환경 변수 분류

### ConfigMap (config)에 포함되는 설정

| 변수명 | 설명 |
|--------|------|
| SERVER_PORT | Spring Boot 서버 포트 |
| SPRING_PROFILES_ACTIVE | 활성 프로파일 (dev, prod) |
| SPRING_DATASOURCE_MASTER_URL | 마스터 DB JDBC URL |
| SPRING_DATASOURCE_REPLICA_URL | 레플리카 DB JDBC URL |
| SPRING_DATA_REDIS_HOST | Redis 호스트 |
| SPRING_DATA_REDIS_PORT | Redis 포트 |
| SPRING_REDISSON_ADDRESS | Redisson 주소 |
| SPRING_KAFKA_BOOTSTRAP_SERVERS | Kafka 브로커 주소 |
| SPRING_KAFKA_PRODUCER_BOOTSTRAP_SERVERS | Kafka 프로듀서 브로커 |
| SPRING_KAFKA_CONSUMER_BOOTSTRAP_SERVERS | Kafka 컨슈머 브로커 |

### Secret (secrets)에 포함되는 설정

| 변수명 | 설명 |
|--------|------|
| SPRING_DATASOURCE_MASTER_USERNAME | 마스터 DB 사용자명 |
| SPRING_DATASOURCE_MASTER_PASSWORD | 마스터 DB 비밀번호 |
| SPRING_DATASOURCE_REPLICA_USERNAME | 레플리카 DB 사용자명 |
| SPRING_DATASOURCE_REPLICA_PASSWORD | 레플리카 DB 비밀번호 |
| SPRING_REDIS_PASSWORD | Redis 비밀번호 |
| SPRING_REDISSON_PASSWORD | Redisson 비밀번호 |

## ConfigMap/Secret 변경 감지

Rollout은 ConfigMap 또는 Secret이 변경될 때 자동으로 재배포됩니다.

### checksum annotation

```yaml
# rollout.yaml
template:
  metadata:
    annotations:
      checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
      {{- if .Values.secrets }}
      checksum/secret: {{ include (print $.Template.BasePath "/secret.yaml") . | sha256sum }}
      {{- end }}
```

이 annotation은 ConfigMap/Secret 내용이 변경되면 해시값이 변경되어 Rollout이 새로운 ReplicaSet을 생성합니다.

## envFrom 주입

환경 변수는 `envFrom`을 통해 일괄 주입됩니다:

```yaml
# rollout.yaml
containers:
  - name: {{ .Chart.Name }}
    envFrom:
      - configMapRef:
          name: {{ include "<service>.fullname" . }}-config
      {{- if .Values.secrets }}
      - secretRef:
          name: {{ include "<service>.fullname" . }}-secret
      {{- end }}
    {{- if .Values.extraEnv }}
    env:
      {{- toYaml .Values.extraEnv | nindent 12 }}
    {{- end }}
```

## ArgoCD에서의 장점

1. **변경 추적 용이**: ConfigMap/Secret이 별도 리소스로 관리되어 ArgoCD UI에서 변경 사항 확인 가능
2. **선택적 동기화**: 특정 리소스만 동기화 가능
3. **롤백 용이**: 이전 버전의 설정으로 쉽게 롤백
4. **명확한 diff**: values.yaml 변경 시 실제 ConfigMap/Secret의 diff 확인 가능

## 사용 예시

### 환경 변수 추가

1. 비민감 설정: `values.yaml` 또는 환경별 config 파일의 `config:` 섹션에 추가
2. 민감 설정: `values.yaml` 또는 환경별 config 파일의 `secrets:` 섹션에 추가
3. 특수 케이스 (valueFrom 등): `extraEnv:` 섹션 사용

### k3d 개발 환경 배포

```bash
# ArgoCD ApplicationSet이 config/dev/<service>.yaml을 자동으로 병합
# Multiple Sources 패턴 사용
```

### 프로덕션 환경 배포

```bash
# ArgoCD ApplicationSet이 config/prod/<service>.yaml을 자동으로 병합
# 프로덕션용 이미지 태그와 설정이 적용됨
```

## 적용된 서비스 목록

- customer-service
- order-service
- store-service
- payment-service
- product-service
- recommendation-service
- saga-tracker
