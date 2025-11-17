# EKS Istio 배포 완료 보고서

> **프로젝트**: C4ang E-commerce 마이크로서비스 플랫폼  
> **환경**: AWS EKS + Istio Service Mesh  
> **완료일**: 2025-11-16  
> **상태**: ✅ 배포 및 테스트 완료

---

## 📋 목차

1. [배포 개요](#배포-개요)
2. [테스트 과정](#테스트-과정)
3. [발생한 문제와 해결](#발생한-문제와-해결)
4. [최종 아키텍처](#최종-아키텍처)
5. [다음 단계](#다음-단계)
6. [프로덕션 체크리스트](#프로덕션-체크리스트)

---

## 🎯 배포 개요

### 배포된 서비스

| 서비스명 | Replicas | 상태 | API 경로 |
|---------|----------|------|----------|
| Customer Service | 2 | ✅ Running | `/api/v1/customers` |
| Order Service | 2 | ✅ Running | `/api/v1/orders` |
| Product Service | 2 | ✅ Running | `/api/v1/products` |
| Payment Service | 2 | ✅ Running | `/api/v1/payments` |
| Recommendation Service | 2 | ✅ Running | `/api/v1/recommendations` |
| Saga Tracker | 2 | ✅ Running | `/api/v1/saga` |

**총 12개 Pod** (모두 2/2 Running - Application + Istio Sidecar)

### 인프라 구성

```
┌─────────────────────────────────────────────────────┐
│                    Internet                          │
└──────────────────┬──────────────────────────────────┘
                   │
         ┌─────────▼──────────┐
         │   AWS NLB          │
         │ (Network LB)       │
         └─────────┬──────────┘
                   │
         ┌─────────▼──────────┐
         │ Istio Ingress      │
         │   Gateway          │
         └─────────┬──────────┘
                   │
    ┌──────────────┼──────────────┐
    │              │              │
┌───▼───┐    ┌────▼────┐    ┌───▼────┐
│Service│    │Service  │    │Service │
│  Pod  │    │  Pod    │    │  Pod   │
│ 2/2   │    │  2/2    │    │  2/2   │
└───┬───┘    └────┬────┘    └───┬────┘
    │             │             │
    └─────────────┼─────────────┘
                  │
        ┌─────────▼──────────┐
        │ AWS RDS (PostgreSQL)│
        └─────────┬──────────┘
                  │
        ┌─────────▼──────────┐
        │ Redis (Helm Chart) │
        │  (StatefulSet)     │
        └────────────────────┘
```

**주요 컴포넌트:**
- **EKS Cluster**: Kubernetes 1.28+
- **Istio**: 1.28.0 (Service Mesh)
- **AWS NLB**: 외부 트래픽 진입점
- **AWS RDS**: 외부 PostgreSQL 데이터베이스
- **Redis**: Helm Chart 기반 StatefulSet (redis-base dependency)
- **Namespace**: ecommerce

---

## 🧪 테스트 과정

### 1단계: 인프라 검증 (✅ 완료)

```bash
# Pod 상태 확인
kubectl get pods -n ecommerce
# 결과: 12/12 pods running (2/2 each)

# Istio 리소스 확인
kubectl get virtualservice,destinationrule,gateway -n ecommerce
# 결과: 6 VirtualServices, 6 DestinationRules, 1 Gateway
```

**검증 항목:**
- ✅ 모든 Pod가 Istio Sidecar와 함께 실행 (2/2 Running)
- ✅ Service Endpoints가 모든 Pod를 가리킴
- ✅ VirtualService가 Gateway에 연결됨
- ✅ NLB가 정상적으로 프로비저닝됨

### 2단계: 내부 접근 테스트 (✅ 완료)

**테스트 방법:**
클러스터 내부에서 Istio Gateway를 통한 접근 테스트

```bash
kubectl run test-pod --image=curlimages/curl --restart=Never -n ecommerce --rm -i -- \
  curl -s -H "Host: api.c4ang.com" \
  http://istio-ingressgateway.istio-system.svc.cluster.local/api/v1/customers
```

**결과:**
```
✅ Customer Service: "Customer Service Test Response"
✅ Order Service: "Order Service Test Response"
✅ Product Service: "Product Service Test Response"
✅ Payment Service: "Payment Service Test Response"
✅ Recommendation Service: "Recommendation Service Test Response"
✅ Saga Tracker: "Saga Tracker Test Response"
```

**성공률: 6/6 (100%)**

### 3단계: 외부 접근 테스트 (✅ 완료)

**테스트 방법:**
AWS NLB를 통한 인터넷 접근 테스트

```bash
LB_HOST="a8eb08307a1794cb186c4fb33f37f0d3-a56a0b005e5ff59b.elb.ap-northeast-2.amazonaws.com"
curl -H "Host: api.c4ang.com" http://$LB_HOST/api/v1/customers
```

**DNS 해석:**
- IP 1: 43.201.216.188
- IP 2: 52.78.18.204
- IP 3: 43.202.225.191

**결과:** ✅ 모든 서비스 정상 응답

---

## 🔧 발생한 문제와 해결

### 문제 1: Istio Sidecar 자동 주입 실패

**증상:**
```
Error creating: Internal error occurred: failed calling webhook 
"namespace.sidecar-injector.istio.io": failed to call webhook: 
Post "https://istiod.istio-system.svc:443/inject?timeout=10s": 
context deadline exceeded
```

**원인:**
- istiod의 webhook endpoint가 10초 내에 응답하지 않음
- EKS 네트워크 정책 또는 보안 그룹 문제 가능성

**해결 방법:**
수동 Sidecar 주입 사용

```bash
helm template service-name helm/services/service-name \
  -n ecommerce -f values-eks-test.yaml | \
  istioctl kube-inject -f - | \
  kubectl apply -f - -n ecommerce
```

**결과:** ✅ 모든 Pod가 Sidecar와 함께 정상 실행

**향후 개선:**
- EKS 보안 그룹에서 istiod 443 포트 접근 확인
- Webhook timeout 설정 증가
- Istio 재설치 고려

---

### 문제 2: Order Service Endpoints 없음

**증상:**
```
NAME        ENDPOINTS   AGE
order-api   <none>      19h
```

**원인:**
- Service selector와 Pod labels 불일치
- Service targetPort와 실제 Pod containerPort 불일치

**트러블슈팅 과정:**

1. **Service 설정 확인**
```bash
kubectl get svc order-api -n ecommerce -o yaml
# 결과: targetPort: 5678 ✅
```

2. **Pod 포트 확인**
```bash
kubectl get pod -l app.kubernetes.io/name=order-service -o yaml | grep containerPort
# 결과: containerPort: 5678 ✅
```

3. **Endpoints 확인**
```bash
kubectl get endpoints order-api -n ecommerce
# 결과: <none> ❌
```

4. **직접 접근 테스트**
```bash
curl http://order-api.ecommerce.svc.cluster.local:8080/
# 결과: Connection refused ❌
```

**해결 방법:**
Pod를 재배포하여 올바른 labels 적용

```bash
kubectl delete deployment order-api -n ecommerce
helm template order-api helm/services/order-service \
  -n ecommerce -f values-eks-test.yaml | \
  istioctl kube-inject -f - | \
  kubectl apply -f - -n ecommerce
```

**결과:**
```
NAME        ENDPOINTS                             AGE
order-api   172.20.58.232:5678,172.20.81.8:5678   19h
```

✅ Endpoints 정상 생성

---

### 문제 3: Command/Args가 Pod에 적용 안됨

**증상:**
```bash
kubectl get pod order-pod -o jsonpath='{.spec.containers[0].args}'
# 결과: (비어있음)
```

서비스 응답이 없거나 빈 응답

**원인:**
deployment.yaml 템플릿에 `command`와 `args` 필드가 누락됨

**발견 과정:**

1. Customer Service는 작동하지만 다른 서비스들은 빈 응답
2. Customer Service deployment.yaml과 비교
3. `command`와 `args` 섹션이 없음을 확인

**해결 방법:**

모든 서비스의 `deployment.yaml`에 추가:

```yaml
containers:
- name: {{ .Chart.Name }}
  image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
  imagePullPolicy: {{ .Values.image.pullPolicy }}
  {{- with .Values.command }}
  command:
    {{- toYaml . | nindent 10 }}
  {{- end }}
  {{- with .Values.args }}
  args:
    {{- toYaml . | nindent 10 }}
  {{- end }}
  ports:
  # ...
```

**적용 파일:**
- `order-service/templates/deployment.yaml`
- `product-service/templates/deployment.yaml`
- `payment-service/templates/deployment.yaml`
- `recommendation-service/templates/deployment.yaml`
- `saga-tracker/templates/deployment.yaml`

**결과:**
```bash
kubectl get pod order-pod -o jsonpath='{.spec.containers[0].args}'
["-listen=:5678","-text=Order Service Test Response"]
```

✅ Args 정상 적용

---

### 문제 4: VirtualService가 Gateway와 연결 안됨

**증상:**
```
NAME                    GATEWAYS   HOSTS                   AGE
customer-api-vs         []         ["customer-api"]        30m
order-api-vs            []         ["order-api"]           30m
```

내부 접근은 되지만 Gateway를 통한 외부 접근 불가

**원인:**
VirtualService 템플릿에 `gateways` 필드와 올바른 `hosts` 설정이 없음

**해결 방법:**

모든 `virtualservice.yaml` 템플릿 수정:

```yaml
spec:
  gateways:
    - {{ .Values.istio.gatewayAPI.gatewayName | default "ecommerce-gateway" }}
  hosts:
    - {{ .Values.istio.gatewayAPI.hostnames | default (list "api.c4ang.com" "*") | first }}
    - "*"
  http:
    - match:
        - uri:
            prefix: {{ .Values.istio.pathPrefix }}
      # ...
```

**재배포:**
```bash
helm template order-api helm/services/order-service \
  --show-only templates/virtualservice.yaml | \
  kubectl apply -f - -n ecommerce
```

**결과:**
```
NAME                    GATEWAYS                HOSTS                   AGE
order-api-vs            ["ecommerce-gateway"]   ["api.c4ang.com","*"]   30m
```

✅ Gateway 연결 완료

---

## 🏗️ 최종 아키텍처

### Helm Chart 구조

```
helm/services/
├── customer-service/
│   ├── Chart.yaml                 # Chart 메타데이터 + Redis dependency
│   ├── values.yaml                # 기본 설정
│   ├── values-eks-test.yaml       # EKS 테스트용 설정
│   └── templates/
│       ├── deployment.yaml        # ✅ command/args 추가됨
│       ├── service.yaml
│       ├── configmap.yaml
│       ├── virtualservice.yaml    # ✅ gateway/hosts 추가됨
│       ├── destinationrule.yaml
│       └── httproute.yaml         # (Gateway API - 선택사항)
├── order-service/                 # 동일 구조
├── product-service/               # 동일 구조
├── payment-service/               # 동일 구조
├── recommendation-service/        # 동일 구조
└── saga-tracker/                  # 동일 구조
```

**Chart.yaml 예시:**
```yaml
apiVersion: v2
name: customer-service
description: Customer Service Microservice
type: application
version: 1.0.0
appVersion: "1.0.0"

# Note: PostgreSQL은 외부 RDS 사용 (dependency 제거됨)
# Redis는 Helm dependency 사용
dependencies:
  - name: redis-base
    alias: redis
    version: "1.0.0"
    repository: "file://../../statefulset-base/redis"
    condition: redis.enabled  # values.yaml에서 제어 가능
```

### Istio 설정

**VirtualService 예시:**
```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: order-api-vs
spec:
  gateways:
    - ecommerce-gateway
  hosts:
    - api.c4ang.com
    - "*"
  http:
    - match:
        - uri:
            prefix: /api/v1/orders
      route:
        - destination:
            host: order-api
            port:
              number: 8080
      timeout: 30s
      retries:
        attempts: 3
        perTryTimeout: 10s
        retryOn: "5xx,reset,connect-failure,refused-stream"
```

**DestinationRule 예시:**
```yaml
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: order-api-dr
spec:
  host: order-api
  trafficPolicy:
    connectionPool:
      tcp:
        maxConnections: 100
      http:
        http1MaxPendingRequests: 50
        http2MaxRequests: 100
    outlierDetection:
      consecutive5xxErrors: 5
      interval: 10s
      baseEjectionTime: 30s
      maxEjectionPercent: 50
```

### 배포 스크립트

**유지할 스크립트:**

1. **`deploy-with-sidecar-injection.sh`**
   - 용도: 모든 서비스를 Sidecar 수동 주입으로 배포
   - 언제: 새 서비스 추가 또는 전체 재배포 시

2. **`final-deploy.sh`**
   - 용도: VirtualService만 빠르게 재배포
   - 언제: 라우팅 규칙 변경 시

3. **`test-external-simple.sh`**
   - 용도: 외부 접근 테스트
   - 언제: 배포 후 검증 시

**작성된 문서:**

1. **`ISTIO-DEPLOYMENT-GUIDE.md`**
   - 전체 배포 가이드
   - 문제 해결 섹션 포함

2. **`README-NEXT-STEPS.md`**
   - 빠른 시작 가이드
   - 다음 단계 안내

---

## 📝 다음 단계

### 즉시 필요한 작업

#### 1. DNS 설정 (Route53)

**CNAME 레코드 추가:**
```
레코드명: api.c4ang.com
타입: CNAME
값: a8eb08307a1794cb186c4fb33f37f0d3-a56a0b005e5ff59b.elb.ap-northeast-2.amazonaws.com
TTL: 300
```

**테스트:**
```bash
nslookup api.c4ang.com
curl -H "Host: api.c4ang.com" http://api.c4ang.com/api/v1/customers
```

#### 2. TLS/HTTPS 설정

**옵션 A: AWS Certificate Manager (ACM)**

1. ACM에서 인증서 발급
```
도메인: api.c4ang.com
검증: DNS 검증 (Route53 자동)
```

2. NLB에 리스너 추가
```
Protocol: TLS
Port: 443
Certificate: ACM 인증서
Target: Istio Ingress Gateway
```

3. Gateway 업데이트
```yaml
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: ecommerce-gateway
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 443
      name: https
      protocol: HTTPS
    tls:
      mode: PASSTHROUGH
    hosts:
    - api.c4ang.com
```

**옵션 B: cert-manager + Let's Encrypt**

1. cert-manager 설치
```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml
```

2. ClusterIssuer 생성
```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@c4ang.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: istio
```

3. Certificate 생성
```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: api-c4ang-com-tls
  namespace: istio-system
spec:
  secretName: api-c4ang-com-tls
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
  - api.c4ang.com
```

#### 3. 실제 애플리케이션 이미지로 교체

현재 테스트용 `http-echo` 이미지를 실제 애플리케이션으로 교체:

**`values.yaml` 업데이트:**
```yaml
image:
  repository: your-registry.com/customer-service
  tag: v1.0.0
  pullPolicy: IfNotPresent

# command와 args 제거 (실제 애플리케이션은 자체 ENTRYPOINT 사용)
# command: ["/http-echo"]
# args:
#   - "-listen=:5678"
#   - "-text=Customer Service Test Response"
```

**배포:**
```bash
helm upgrade customer-api helm/services/customer-service \
  -n ecommerce \
  -f helm/services/customer-service/values.yaml
```

### 단기 작업 (1-2주)

#### 4. Observability 구축

**Kiali (Service Mesh Dashboard)**
```bash
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.28/samples/addons/kiali.yaml
kubectl port-forward -n istio-system svc/kiali 20001:20001
# http://localhost:20001
```

**Prometheus + Grafana (메트릭)**
```bash
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.28/samples/addons/prometheus.yaml
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.28/samples/addons/grafana.yaml
kubectl port-forward -n istio-system svc/grafana 3000:3000
```

**Jaeger (분산 추적)**
```bash
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.28/samples/addons/jaeger.yaml
kubectl port-forward -n istio-system svc/tracing 16686:80
```

#### 5. mTLS 활성화

**PeerAuthentication 생성:**
```yaml
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: ecommerce
spec:
  mtls:
    mode: STRICT
```

**검증:**
```bash
istioctl authn tls-check deployment/order-api.ecommerce
```

#### 6. Rate Limiting 설정

```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: order-api-vs
spec:
  # ... existing config
  http:
    - match:
        - uri:
            prefix: /api/v1/orders
      route:
        - destination:
            host: order-api
      fault:
        abort:
          percentage:
            value: 0.1
          httpStatus: 429
```

#### 7. External Database 및 Redis 연결

**RDS PostgreSQL 설정:**

프로덕션 환경에서는 외부 RDS를 사용합니다 (Chart.yaml에서 PostgreSQL dependency 제거됨).

```yaml
# values.yaml
database:
  host: c4ang-prod.xxxxx.ap-northeast-2.rds.amazonaws.com
  port: 5432
  name: ecommerce
  username: admin
  # password는 Kubernetes Secret 사용

env:
  - name: DB_HOST
    value: "{{ .Values.database.host }}"
  - name: DB_PASSWORD
    valueFrom:
      secretKeyRef:
        name: db-credentials
        key: password
```

**Redis 설정 (Helm Chart Dependency):**

현재 환경에서는 Helm의 `redis-base` dependency를 사용합니다.

```yaml
# Chart.yaml
dependencies:
  - name: redis-base
    alias: redis
    version: "1.0.0"
    repository: "file://../../statefulset-base/redis"
    condition: redis.enabled
```

```yaml
# values.yaml
redis:
  enabled: true  # Redis 활성화
  master:
    persistence:
      enabled: true
      size: 8Gi
  auth:
    enabled: true
    password: "your-redis-password"

env:
  - name: REDIS_HOST
    value: "{{ .Release.Name }}-redis-master"
  - name: REDIS_PORT
    value: "6379"
  - name: REDIS_PASSWORD
    valueFrom:
      secretKeyRef:
        name: {{ .Release.Name }}-redis
        key: redis-password
```

**참고**: 프로덕션 환경에서 ElastiCache로 전환하려면:
1. `redis.enabled: false`로 설정
2. 환경 변수를 ElastiCache 엔드포인트로 변경

### 중기 작업 (1-3개월)

#### 8. CI/CD 파이프라인 구축

**GitHub Actions 예시:**
```yaml
name: Deploy to EKS

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v2
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ap-northeast-2
      
      - name: Update kubeconfig
        run: aws eks update-kubeconfig --name c4ang-cluster
      
      - name: Deploy with Istio Sidecar
        run: |
          export PATH="/path/to/istioctl:$PATH"
          helm template order-api helm/services/order-service \
            -n ecommerce -f values.yaml | \
            istioctl kube-inject -f - | \
            kubectl apply -f - -n ecommerce
      
      - name: Wait for rollout
        run: kubectl rollout status deployment/order-api -n ecommerce
      
      - name: Run smoke tests
        run: ./test-external-simple.sh
```

#### 9. Auto-scaling 설정

**HPA (Horizontal Pod Autoscaler):**
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: order-api-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: order-api
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
```

**Cluster Autoscaler:**
```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/autoscaler/master/cluster-autoscaler/cloudprovider/aws/examples/cluster-autoscaler-autodiscover.yaml
```

#### 10. Backup & Disaster Recovery

**Velero 설치:**
```bash
velero install \
    --provider aws \
    --plugins velero/velero-plugin-for-aws:v1.8.0 \
    --bucket c4ang-velero-backups \
    --backup-location-config region=ap-northeast-2 \
    --snapshot-location-config region=ap-northeast-2
```

**스케줄 백업:**
```bash
velero schedule create daily-backup --schedule="0 2 * * *"
```

---

## ✅ 프로덕션 체크리스트

### 보안

- [ ] TLS/HTTPS 설정 완료
- [ ] mTLS (서비스 간 통신 암호화) 활성화
- [ ] Network Policies 설정
- [ ] Pod Security Standards 적용
- [ ] Secrets 관리 (AWS Secrets Manager 또는 External Secrets)
- [ ] RBAC (Role-Based Access Control) 구성
- [ ] Container 이미지 취약점 스캔 (Trivy, Snyk)
- [ ] API Gateway Rate Limiting
- [ ] WAF (Web Application Firewall) 설정

### 신뢰성

- [ ] Health Checks (Liveness/Readiness) 설정
- [ ] Resource Limits & Requests 적절히 설정
- [ ] HPA (Horizontal Pod Autoscaler) 구성
- [ ] PodDisruptionBudget 설정
- [ ] Multi-AZ 배포 확인
- [ ] Circuit Breaker 패턴 적용 (Istio DestinationRule)
- [ ] Retry & Timeout 정책 최적화
- [ ] Database Connection Pooling

### 모니터링 & 로깅

- [ ] Prometheus 메트릭 수집
- [ ] Grafana 대시보드 구성
- [ ] Jaeger 분산 추적 활성화
- [ ] Kiali Service Graph 확인
- [ ] CloudWatch Logs 통합
- [ ] 알람 설정 (PagerDuty, Slack)
- [ ] SLO/SLA 정의 및 모니터링
- [ ] Application Performance Monitoring (APM)

### 성능

- [ ] Load Testing 수행 (k6, JMeter)
- [ ] Database 인덱스 최적화
- [ ] Redis 캐싱 전략 수립
- [ ] CDN 설정 (CloudFront)
- [ ] 이미지 최적화
- [ ] API Response Compression
- [ ] Database 읽기 전용 Replica 구성
- [ ] Connection Pool 튜닝

### 운영

- [ ] CI/CD 파이프라인 구축
- [ ] Blue-Green 또는 Canary 배포 전략
- [ ] Automated Rollback 메커니즘
- [ ] Backup & Recovery 프로세스
- [ ] Disaster Recovery Plan
- [ ] Runbook 작성
- [ ] On-call 정책 수립
- [ ] 변경 관리 프로세스

### 비용 최적화

- [ ] Right-sizing (적절한 인스턴스 크기)
- [ ] Spot Instances 활용
- [ ] Auto-scaling 정책 최적화
- [ ] Unused Resources 정리
- [ ] Reserved Instances 고려
- [ ] Cost Allocation Tags
- [ ] Budget Alerts 설정

### 컴플라이언스

- [ ] 데이터 암호화 (at rest & in transit)
- [ ] 감사 로그 활성화
- [ ] GDPR 준수 (개인정보 처리)
- [ ] 데이터 백업 정책
- [ ] 접근 제어 로그
- [ ] 정기 보안 감사

---

## 📚 참고 자료

### 공식 문서
- [Istio Documentation](https://istio.io/latest/docs/)
- [AWS EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Helm Charts Guide](https://helm.sh/docs/)

### 작성된 문서
- `ISTIO-DEPLOYMENT-GUIDE.md` - 상세 배포 가이드
- `README-NEXT-STEPS.md` - 빠른 시작 가이드

### 유용한 명령어

**디버깅:**
```bash
# Pod 로그
kubectl logs <pod-name> -n ecommerce -c <container-name>

# Istio Proxy 로그
kubectl logs <pod-name> -n ecommerce -c istio-proxy

# Istio 설정 확인
istioctl proxy-config routes <pod-name> -n ecommerce
istioctl proxy-status

# 네트워크 테스트
kubectl run debug --image=nicolaka/netshoot -n ecommerce --rm -it -- bash
```

**모니터링:**
```bash
# 리소스 사용량
kubectl top pods -n ecommerce
kubectl top nodes

# 이벤트 확인
kubectl get events -n ecommerce --sort-by='.lastTimestamp'

# Istio 메트릭
kubectl -n istio-system port-forward svc/prometheus 9090:9090
```

---

## 🎓 학습한 교훈

### 1. Istio Webhook 문제
자동 Sidecar 주입이 실패할 경우를 대비해 수동 주입 방법을 항상 준비해야 함

### 2. Helm Template 검증
배포 전에 `helm template` 명령으로 생성되는 YAML을 반드시 확인

### 3. Endpoints 모니터링
Service가 정상이어도 Endpoints가 없으면 라우팅 불가 - 항상 확인 필요

### 4. VirtualService 설정
Gateway를 통한 외부 접근을 위해서는 `gateways`와 올바른 `hosts` 설정 필수

### 5. 점진적 테스트
내부 접근 → Gateway 접근 → 외부 접근 순으로 단계별 검증이 효과적

---

## 📞 문의 및 지원

**문제 발생 시:**
1. `ISTIO-DEPLOYMENT-GUIDE.md`의 문제 해결 섹션 참고
2. Istio Proxy 로그 확인
3. `istioctl analyze` 실행
4. Kiali에서 Service Graph 확인

**긴급 상황:**
```bash
# 전체 롤백
kubectl rollout undo deployment/<deployment-name> -n ecommerce

# Istio 비활성화
kubectl label namespace ecommerce istio-injection-

# 서비스 재시작
kubectl rollout restart deployment/<deployment-name> -n ecommerce
```

---

**문서 버전**: 1.0  
**최종 업데이트**: 2025-11-16  
**작성자**: DevOps Team

