# 외부 리소스 의존성 관리 전략

Kubernetes 환경에서 외부 리소스(DB, Redis, Kafka 등)에 의존하는 애플리케이션을 관리하기 위한 전략을 정리한 문서입니다.

## 목차

- [개요](#개요)
- [배포 시점 전략 (ArgoCD 레벨)](#1-배포-시점-전략-argocd-레벨)
- [런타임 전략 (Pod 레벨)](#2-런타임-전략-pod-레벨)
- [애플리케이션 레벨 전략](#3-애플리케이션-레벨-전략-코드서비스메시)
- [외부 리소스 상태별 권장 전략](#외부-리소스-상태별-권장-전략)
- [프로젝트 권장 구성](#현재-프로젝트-권장-구성)
- [참고 자료](#참고-자료)

---

## 개요

외부 리소스 의존성 관리는 크게 세 가지 레이어에서 처리할 수 있습니다:

```
┌─────────────────────────────────────────────────────────┐
│  1. ArgoCD 레벨 (배포 시점)                              │
│     - Sync Wave, PreSync Hook, App-of-Apps              │
├─────────────────────────────────────────────────────────┤
│  2. Pod 레벨 (컨테이너 시작 시점)                         │
│     - Init Container, Sidecar, Probes                   │
├─────────────────────────────────────────────────────────┤
│  3. 애플리케이션 레벨 (런타임)                            │
│     - Circuit Breaker, Retry, Timeout, Fallback         │
└─────────────────────────────────────────────────────────┘
```

각 레이어는 서로 다른 시점과 목적을 가지며, 조합하여 사용하면 더 강력한 복원력을 갖출 수 있습니다.

---

## 1. 배포 시점 전략 (ArgoCD 레벨)

### 비교표

| 전략 | 적용 위치 | 장점 | 단점 | 적합한 상황 |
|------|----------|------|------|------------|
| **Sync Wave** | Application 어노테이션 | 간단, 순서 보장 | 실제 상태 체크 없음 | 내부 리소스 간 순서 |
| **PreSync Hook** | Job으로 상태 체크 | 실제 연결 확인, 명확한 실패 | Job 관리 필요, 배포 지연 | 외부 리소스 의존 |
| **App-of-Apps Health** | Application 의존성 | GitOps 네이티브 | 외부 리소스 체크 불가 | ArgoCD 앱 간 의존성 |
| **ApplicationSet RollingSync** | 점진적 배포 | 대규모 배포에 적합 | 설정 복잡 | 멀티 클러스터/환경 |

### Sync Wave

리소스에 어노테이션을 추가하여 배포 순서를 제어합니다.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: database
  annotations:
    argocd.argoproj.io/sync-wave: "0"  # 먼저 배포
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: application
  annotations:
    argocd.argoproj.io/sync-wave: "1"  # 나중에 배포
```

**주의사항**: Sync Wave는 배포 순서만 보장하며, 실제 리소스가 Ready 상태인지는 확인하지 않습니다.

### PreSync Hook

Sync 전에 Job을 실행하여 외부 리소스 상태를 확인합니다.

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: db-health-check
  annotations:
    argocd.argoproj.io/hook: PreSync
    argocd.argoproj.io/hook-delete-policy: HookSucceeded
spec:
  template:
    spec:
      containers:
      - name: check
        image: busybox
        command: ['sh', '-c', 'nc -z $DB_HOST $DB_PORT']
      restartPolicy: Never
  backoffLimit: 5
```

**장점**:
- 외부 리소스 상태를 실제로 확인
- 실패 시 Sync 자체가 중단되어 명확한 에러 표시
- 배포 로그에서 실패 원인 파악 용이

**단점**:
- Job 리소스 관리 필요
- 체크 시간만큼 배포 지연

### App-of-Apps Health Check

ArgoCD Application 간의 의존성을 Health 상태로 관리합니다.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
spec:
  # ...
  syncPolicy:
    automated:
      selfHeal: true
    # dependent-app이 Healthy일 때만 sync
```

**참고**: Custom Health Check를 argocd-cm ConfigMap에 정의하여 특정 리소스의 Health 판단 로직을 커스터마이징할 수 있습니다.

---

## 2. 런타임 전략 (Pod 레벨)

### 비교표

| 전략 | 적용 위치 | 장점 | 단점 | 적합한 상황 |
|------|----------|------|------|------------|
| **Init Container** | Pod 시작 전 | 앱 코드 수정 없음, 간단 | 시작 지연, 무한 대기 가능 | DB 마이그레이션, 초기 연결 |
| **Sidecar Container** | Pod 전체 생명주기 | 지속적 모니터링 | 리소스 사용 증가 | 프록시, 로그 수집 |
| **Readiness Probe** | kubelet | K8s 네이티브, 트래픽 제어 | 외부 의존성 체크 권장 안함 | 앱 자체 준비 상태 |
| **Startup Probe** | kubelet | 느린 시작 앱 지원 | K8s 1.18+ 필요 | 초기화 오래 걸리는 앱 |

### Init Container

Pod의 메인 컨테이너가 시작되기 전에 실행되는 컨테이너입니다.

```yaml
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    spec:
      initContainers:
      - name: wait-for-db
        image: busybox:1.36
        command: ['sh', '-c', '''
          until nc -z customer-db 5432; do
            echo "Waiting for database..."
            sleep 2
          done
          echo "Database is ready!"
        ''']
      - name: wait-for-kafka
        image: busybox:1.36
        command: ['sh', '-c', '''
          until nc -z kafka 9092; do
            echo "Waiting for Kafka..."
            sleep 2
          done
          echo "Kafka is ready!"
        ''']
      containers:
      - name: app
        image: my-app:latest
```

**사용 사례**:
- 데이터베이스 연결 대기
- 스키마 마이그레이션 실행
- 설정 파일 다운로드
- 의존 서비스 준비 확인

### Sidecar Container (K8s 1.28+)

Pod의 전체 생명주기 동안 함께 실행되는 컨테이너입니다.

```yaml
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    spec:
      initContainers:
      - name: log-collector
        image: fluentd:latest
        restartPolicy: Always  # Sidecar로 동작
      containers:
      - name: app
        image: my-app:latest
```

**사용 사례**:
- 로그 수집 및 전송
- 서비스 메시 프록시 (Envoy)
- 보안 에이전트
- 지속적인 상태 모니터링

### Readiness/Liveness Probe

```yaml
containers:
- name: app
  readinessProbe:
    httpGet:
      path: /health/ready
      port: 8080
    initialDelaySeconds: 5
    periodSeconds: 10
  livenessProbe:
    httpGet:
      path: /health/live
      port: 8080
    initialDelaySeconds: 15
    periodSeconds: 20
```

**주의**: Readiness Probe에서 외부 의존성(DB, 외부 API)을 체크하는 것은 권장되지 않습니다. 외부 서비스 장애 시 모든 Pod이 Not Ready 상태가 되어 연쇄 장애를 유발할 수 있습니다.

---

## 3. 애플리케이션 레벨 전략 (코드/서비스메시)

### 비교표

| 전략 | 적용 위치 | 장점 | 단점 | 적합한 상황 |
|------|----------|------|------|------------|
| **Circuit Breaker** | 앱/Istio | 장애 전파 방지 | 설정 복잡 | 일시적 장애 대응 |
| **Retry + Backoff** | 앱/Istio | 일시적 오류 복구 | 과부하 위험 | 네트워크 불안정 |
| **Timeout** | 앱/Istio | 리소스 보호 | 적절한 값 설정 어려움 | 느린 응답 방지 |
| **Fallback** | 앱 코드 | 서비스 연속성 | 비즈니스 로직 필요 | 대체 로직 가능 시 |

### Circuit Breaker

연속적인 실패를 감지하여 빠르게 실패 처리하고, 백엔드 서비스를 보호합니다.

```
상태 흐름:
CLOSED → (실패 임계치 도달) → OPEN → (대기 시간 경과) → HALF-OPEN → (성공) → CLOSED
                                                                    ↓ (실패)
                                                                   OPEN
```

**Istio DestinationRule 설정**:

```yaml
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: customer-db-circuit-breaker
spec:
  host: customer-db
  trafficPolicy:
    outlierDetection:
      consecutive5xxErrors: 5      # 연속 5회 5xx 에러 시
      interval: 10s                # 10초 간격으로 체크
      baseEjectionTime: 30s        # 30초 동안 트래픽 차단
      maxEjectionPercent: 100      # 최대 100% 인스턴스 제외 가능
```

**Resilience4j (Spring Boot) 설정**:

```yaml
resilience4j:
  circuitbreaker:
    instances:
      customerDb:
        failureRateThreshold: 50           # 50% 실패율 시 OPEN
        waitDurationInOpenState: 30s       # OPEN 상태 유지 시간
        permittedNumberOfCallsInHalfOpenState: 3
        slidingWindowSize: 10
```

### Retry with Exponential Backoff

일시적인 오류에 대해 자동으로 재시도합니다.

**Istio VirtualService 설정**:

```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: customer-service
spec:
  hosts:
  - customer-service
  http:
  - route:
    - destination:
        host: customer-service
    retries:
      attempts: 3
      perTryTimeout: 2s
      retryOn: 5xx,reset,connect-failure,retriable-4xx
```

**Resilience4j 설정**:

```yaml
resilience4j:
  retry:
    instances:
      customerDb:
        maxAttempts: 3
        waitDuration: 1s
        exponentialBackoffMultiplier: 2    # 1s → 2s → 4s
        retryExceptions:
          - java.io.IOException
          - java.sql.SQLException
```

### Timeout

느린 응답으로 인한 리소스 고갈을 방지합니다.

```yaml
# Istio VirtualService
http:
- route:
  - destination:
      host: customer-service
  timeout: 10s
```

### Fallback

실패 시 대체 로직을 실행합니다.

```java
@CircuitBreaker(name = "customerDb", fallbackMethod = "getCustomerFallback")
public Customer getCustomer(String id) {
    return customerRepository.findById(id);
}

public Customer getCustomerFallback(String id, Exception e) {
    // 캐시에서 조회 또는 기본값 반환
    return cacheService.getCustomer(id)
        .orElse(Customer.unknown(id));
}
```

---

## 외부 리소스 상태별 권장 전략

### 시나리오 1: 외부 리소스가 없으면 앱 시작 불가

데이터베이스, 메시지 큐 등 필수 인프라가 준비되지 않으면 애플리케이션이 시작되면 안 되는 경우입니다.

```
추천: PreSync Hook + Init Container (이중 보호)

┌─────────────────────────────────────────────────────┐
│ ArgoCD PreSync Hook                                 │
│ - 배포 전 외부 리소스 상태 확인                            │
│ - 실패 시 Sync 자체가 실패 → 명확한 에러                   │
└─────────────────────────────────────────────────────┘
                        ↓ (성공 시)
┌─────────────────────────────────────────────────────┐
│ Pod Init Container                                  │
│ - Pod 시작 전 최종 확인                                 │
│ - PreSync 이후 상태 변경 대비                            │
└─────────────────────────────────────────────────────┘
                        ↓ (성공 시)
                    앱 컨테이너 시작
```

**적합한 경우**:
- 마이크로서비스의 주 데이터베이스
- Kafka Streams 애플리케이션의 Kafka 브로커
- 필수 설정 서버 (Config Server)

### 시나리오 2: 외부 리소스 일시 장애 허용

외부 서비스가 일시적으로 불안정할 수 있지만, 재시도로 복구 가능한 경우입니다.

```
추천: Circuit Breaker + Retry (Istio 또는 앱 레벨)

요청 → Retry (3회, Exponential Backoff)
         ↓
    [성공] → 정상 응답
         ↓
    [실패] → Circuit Breaker 상태 업데이트
                    ↓
              [OPEN] → 빠른 실패 (503)
              [CLOSED/HALF-OPEN] → 요청 전달
```

**적합한 경우**:
- 외부 API 호출
- 비핵심 서비스 연동
- 네트워크가 불안정한 환경

### 시나리오 3: Graceful Degradation (부분 기능 유지)

외부 리소스 장애 시에도 일부 기능은 유지해야 하는 경우입니다.

```
추천: Readiness Probe (앱 자체만) + Circuit Breaker + Fallback

┌─────────────────────────────────────────────────────┐
│ 정상 상태                                             │
│ - DB 조회 → 최신 데이터 반환                             │
└─────────────────────────────────────────────────────┘
                        ↓ (DB 장애 발생)
┌─────────────────────────────────────────────────────┐
│ Degraded 상태                                        │
│ - Circuit Breaker OPEN                              │
│ - Fallback: 캐시 데이터 반환                            │
│ - 쓰기 요청: 503 또는 큐잉                               │
└─────────────────────────────────────────────────────┘
```

**적합한 경우**:
- 읽기 위주 서비스 (캐시 활용 가능)
- 비동기 처리 가능한 쓰기 작업
- 사용자 경험이 중요한 서비스

---

## 현재 프로젝트 권장 구성

로컬 개발 환경 + Kafka Streams 사용을 고려한 권장 구성입니다.

### 레이어별 전략

| 레이어 | 전략 | 이유 |
|--------|------|------|
| **ArgoCD** | Sync Wave + PreSync Hook | Docker 서비스 미실행 시 명확한 에러 |
| **Pod** | Init Container | 앱 시작 전 최종 연결 확인 |
| **앱/Istio** | Circuit Breaker + Retry | 런타임 일시 장애 대응 |

### PreSync Hook vs Init Container 역할 분담

| 체크 대상 | PreSync Hook | Init Container |
|----------|--------------|----------------|
| 외부 리소스 존재 여부 | ✅ (배포 차단) | - |
| 연결 가능 여부 | ✅ | ✅ (최종 확인) |
| DB 스키마 준비 | - | ✅ |
| 마이그레이션 실행 | - | ✅ |

### 구현 우선순위

1. **Phase 1**: PreSync Hook으로 외부 리소스 상태 체크
   - PostgreSQL, Redis, Kafka, Schema Registry 연결 확인
   - 실패 시 ArgoCD에서 명확한 에러 표시

2. **Phase 2**: Init Container 추가
   - 각 마이크로서비스에 의존하는 리소스 체크
   - DB 마이그레이션 실행

3. **Phase 3**: Istio Circuit Breaker/Retry 설정
   - 서비스 간 통신 복원력 강화
   - 외부 API 호출 보호

---

## 참고 자료

### ArgoCD
- [Argo CD Application Dependencies - Codefresh](https://codefresh.io/blog/argo-cd-application-dependencies/)
- [Managing Dependencies with ArgoCD - Stack Overflow](https://stackoverflow.com/questions/74042661/how-to-manage-dependencies-with-argocd)
- [Best Practices ArgoCD 2024 - Medium](https://medium.com/@dikshantmali.dev/best-practices-argocd-k8s-deployment-strategy-with-argocd-5b8226052718)

### Kubernetes Patterns
- [Sidecar vs Init Container - Baeldung](https://www.baeldung.com/ops/kubernetes-sidecar-vs-init-container)
- [Sidecar Containers - Kubernetes Docs](https://kubernetes.io/docs/concepts/workloads/pods/sidecar-containers/)
- [Container Patterns in Kubernetes - Devoriales](https://devoriales.com/post/395/container-patterns-in-kubernetes-init-containers-sidecars-and-co-located-containers-explained)

### Resilience Patterns
- [Circuit Breaker and Retries with Istio - Piotr's TechBlog](https://piotrminkowski.com/2020/06/03/circuit-breaker-and-retries-on-kubernetes-with-istio-and-spring-boot/)
- [Istio Circuit Breaking - Istio Docs](https://istio.io/latest/docs/tasks/traffic-management/circuit-breaking/)
- [Resilience4j Retry Pattern - Medium](https://medium.com/@apichai.tangmansujaritkul/retry-pattern-with-resilience4j-137f62455504)
