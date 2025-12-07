# GitOps에서 Helm과 ArgoCD 역할 분리 가이드

## 개요

이 문서는 K8s + MSA 환경에서 Helm과 ArgoCD의 역할을 어떻게 분리하고 관리해야 하는지에 대한 가이드입니다.

## 역할 정의

### Helm의 역할: "어떻게 배포할 것인가" (템플릿)

| 담당 영역 | 설명 |
|----------|------|
| K8s 리소스 템플릿 | Deployment, Service, ConfigMap 등의 구조 정의 |
| 환경 무관한 기본값 | 포트, 프로토콜, 공통 레이블 등 |
| 스키마 정의 | values.yaml에서 사용 가능한 키 정의 |

### ArgoCD의 역할: "언제, 어디에 배포할 것인가" (오케스트레이션)

| 담당 영역 | 설명 |
|----------|------|
| 배포 대상 정의 | 어떤 클러스터, 네임스페이스에 배포할지 |
| 동기화 정책 | 자동/수동 동기화, self-heal 등 |
| 환경별 values 병합 | Multi-source를 통한 환경별 설정 주입 |

### Config Files의 역할: "무엇을 배포할 것인가" (환경별 값)

| 담당 영역 | 설명 |
|----------|------|
| 이미지 정보 | ECR 주소, 태그 버전 |
| 인프라 연결 정보 | DB 호스트, Redis 호스트, Kafka 브로커 등 |
| 환경별 리소스 설정 | replica 수, CPU/메모리 제한 등 |
| 시크릿 (참조) | DB 자격증명 등 (실제 값은 Secret Manager 권장) |

---

## 디렉토리 구조

```
c4ang-infra/
├── charts/services/{service}/
│   ├── templates/              # K8s 리소스 템플릿
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   ├── configmap.yaml
│   │   └── ...
│   ├── Chart.yaml              # 차트 메타데이터
│   └── values.yaml             # 환경 무관한 기본값만
│
├── config/
│   ├── dev/                    # 개발 환경 (K3D)
│   │   ├── customer-service.yaml
│   │   └── ...
│   └── prod/                   # 프로덕션 환경 (EKS)
│       ├── customer-service.yaml
│       ├── external-services.yaml
│       └── ...
│
└── docs/
    └── GITOPS-HELM-ARGOCD-GUIDE.md
```

---

## Values 병합 순서

ArgoCD의 Multi-source Application에서 `valueFiles`는 순서대로 병합됩니다:

```yaml
# ArgoCD ApplicationSet
sources:
- ref: values
  repoURL: https://github.com/GroomC4/c4ang-infra.git
- helm:
    valueFiles:
    - values.yaml                           # 1순위: 차트 기본값
    - $values/config/prod/{{.name}}.yaml   # 2순위: 환경별 오버라이드 (최종 우선)
```

**우선순위** (낮음 → 높음):
```
Chart values.yaml → config/{env}/*.yaml → inline values → parameters
```

나중에 지정된 파일이 이전 파일의 값을 **완전히 덮어씁니다**.

---

## 설정 분리 원칙

### Chart values.yaml에 포함해야 할 것

```yaml
# charts/services/customer-service/values.yaml

# 서비스 기본 설정 (환경 무관)
fullnameOverride: customer-api

service:
  type: ClusterIP
  port: 80
  targetPort: 8081

# Istio 공통 설정
istio:
  enabled: true
  timeout: 30s
  retries:
    attempts: 3

# 환경별로 달라지는 설정은 비워둠
image:
  repository: ""
  tag: ""
config: {}
secrets: {}
```

### config/prod/*.yaml에 포함해야 할 것

```yaml
# config/prod/customer-service.yaml

# 이미지 정보
image:
  repository: 963403601423.dkr.ecr.ap-northeast-2.amazonaws.com/c4ang-customer-service
  tag: "v1.2.0"

# 리소스 및 스케일링
replicaCount: 3
resources:
  requests:
    memory: 1Gi
    cpu: 500m
  limits:
    memory: 2Gi
    cpu: 1000m

# 환경변수 (Spring Boot 네이밍 규칙 사용)
config:
  SERVER_PORT: "8081"
  SPRING_PROFILES_ACTIVE: "prod"
  SPRING_DATA_REDIS_HOST: "cache-redis"
  SPRING_DATA_REDIS_PORT: "6379"
  SPRING_KAFKA_BOOTSTRAP_SERVERS: "b-1.c4kafka..."

# 시크릿 (임시, 향후 AWS Secrets Manager로 이관)
secrets:
  DB_USERNAME: "appuser"
  DB_PASSWORD: "..."
```

---

## 환경변수 네이밍 규칙

Spring Boot 애플리케이션에서 환경변수를 통해 설정을 주입받을 때의 변환 규칙:

| application.yml 경로 | 환경변수 이름 |
|---------------------|--------------|
| `spring.data.redis.host` | `SPRING_DATA_REDIS_HOST` |
| `spring.datasource.url` | `SPRING_DATASOURCE_URL` |
| `spring.kafka.bootstrap-servers` | `SPRING_KAFKA_BOOTSTRAP_SERVERS` |

**규칙**:
- `.` → `_`
- `-` → `_`
- 모두 대문자

---

## ExternalName 서비스 패턴

AWS 리소스와 내부 서비스 간의 결합도를 낮추기 위해 ExternalName 서비스를 사용합니다:

```yaml
# external-services.yaml에서 정의
apiVersion: v1
kind: Service
metadata:
  name: cache-redis
  namespace: ecommerce
spec:
  type: ExternalName
  externalName: c4-cache-redis.97pni3.0001.apn2.cache.amazonaws.com
```

**장점**:
- 애플리케이션 코드에서 `cache-redis:6379`로 일관되게 접근
- AWS 리소스 엔드포인트 변경 시 ExternalName만 수정
- 환경 간 설정 일관성 유지

---

## 체크리스트

### Chart 작성 시
- [ ] `values.yaml`에 환경 의존적 값(DB URL, Redis 호스트 등)이 없는가?
- [ ] 모든 환경에서 동일한 값만 기본값으로 설정했는가?
- [ ] `config: {}`와 `secrets: {}`를 빈 객체로 정의했는가?

### Config 작성 시
- [ ] Spring Boot 환경변수 네이밍 규칙을 따르는가?
- [ ] 모든 필수 환경변수가 정의되어 있는가?
- [ ] ExternalName 서비스 이름과 일치하는가?

### 배포 전
- [ ] `helm template` 명령으로 로컬 테스트 완료?
- [ ] ArgoCD에서 diff 확인?

---

## 참고 자료

- [ArgoCD Best Practices](https://argo-cd.readthedocs.io/en/stable/user-guide/best_practices/)
- [Using Helm Hierarchies in ArgoCD - Codefresh](https://codefresh.io/blog/helm-values-argocd/)
- [3 Patterns for Deploying Helm Charts with ArgoCD - Red Hat](https://developers.redhat.com/articles/2023/05/25/3-patterns-deploying-helm-charts-argocd)
- [GitOps Repository Patterns - Cloudogu](https://github.com/cloudogu/gitops-patterns)
