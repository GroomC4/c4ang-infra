# C4ang E-commerce Microservices - Helm Charts

## 📦 서비스 목록

| 서비스 | 설명 | API 경로 | 상태 |
|--------|------|----------|------|
| Customer Service | 고객 관리 | `/api/v1/customers` | ✅ Production Ready |
| Order Service | 주문 관리 | `/api/v1/orders` | ✅ Production Ready |
| Product Service | 상품 관리 | `/api/v1/products` | ✅ Production Ready |
| Payment Service | 결제 처리 | `/api/v1/payments` | ✅ Production Ready |
| Recommendation Service | 추천 시스템 | `/api/v1/recommendations` | ✅ Production Ready |
| Saga Tracker | 분산 트랜잭션 추적 | `/api/v1/saga` | ✅ Production Ready |

## 🚀 빠른 시작

### 1. 전체 서비스 배포 (Istio Sidecar 포함)

```bash
cd /Users/kim/Documents/GitHub/c4ang-infra/helm/services
./deploy-with-sidecar-injection.sh
```

### 2. VirtualService만 재배포

```bash
./final-deploy.sh
```

### 3. 외부 접근 테스트

```bash
./test-external-simple.sh
```

## 📝 사용 가능한 스크립트

### `deploy-with-sidecar-injection.sh`
**용도**: 모든 서비스를 Istio Sidecar 수동 주입으로 배포

**언제 사용하나요?**
- 새 서비스를 추가할 때
- 전체 서비스를 재배포할 때
- Istio 자동 주입이 실패할 때

**실행:**
```bash
./deploy-with-sidecar-injection.sh
```

---

### `final-deploy.sh`
**용도**: VirtualService만 빠르게 재배포

**언제 사용하나요?**
- 라우팅 규칙을 변경했을 때
- Timeout/Retry 정책을 수정했을 때
- Gateway 설정을 변경했을 때

**실행:**
```bash
./final-deploy.sh
```

---

### `test-external-simple.sh`
**용도**: NLB를 통한 외부 접근 테스트

**언제 사용하나요?**
- 배포 후 검증할 때
- API 응답을 확인할 때
- 문제 해결 시 연결 테스트

**실행:**
```bash
./test-external-simple.sh
```

---

### `install-gateway-api.sh`
**용도**: Kubernetes Gateway API CRD 설치

**언제 사용하나요?**
- HTTPRoute를 사용하려고 할 때
- 새 클러스터에 Gateway API를 설치할 때

**실행:**
```bash
./install-gateway-api.sh
```

## 📖 문서

### 핵심 문서

- **[ARCHITECTURE.md](../../docs/ARCHITECTURE.md)** ⭐️⭐️⭐️
  - **전체 시스템 아키텍처 문서**
  - Kubernetes 아키텍처 상세
  - Istio Service Mesh 구성
  - 데이터 파이프라인 아키텍처
  - 보안 아키텍처
  - 환경별 구성 (Local/Staging/Production)
  - 모든 컴포넌트 상세 설명

- **[EKS-ISTIO-DEPLOYMENT-SUMMARY.md](../../docs/EKS-ISTIO-DEPLOYMENT-SUMMARY.md)** ⭐️
  - **노션으로 옮길 메인 문서**
  - 전체 배포 과정 정리
  - 발생한 문제와 해결 방법
  - 프로덕션 체크리스트
  - 다음 단계 가이드

- **[EKS-ISTIO-TEST-REPORT.md](../../docs/EKS-ISTIO-TEST-REPORT.md)** ⭐️
  - **노션으로 옮길 테스트 보고서**
  - 수행한 테스트 상세 내역
  - 각 테스트의 목적과 검증 항목
  - 프로덕션 테스트 가이드
  - 성능 테스트 시나리오
  - 모니터링 및 알림 설정

### 참고 문서
- **[ISTIO-DEPLOYMENT-GUIDE.md](./ISTIO-DEPLOYMENT-GUIDE.md)**
  - 상세 배포 가이드
  - 문제 해결 섹션
  - Istio 설정 예시

- **[README-NEXT-STEPS.md](./README-NEXT-STEPS.md)**
  - 빠른 시작 가이드
  - 체크리스트

## 🏗️ Chart 구조

```
services/
├── customer-service/
│   ├── Chart.yaml
│   ├── values.yaml                 # 기본 설정
│   ├── values-eks-test.yaml        # EKS 테스트용 설정
│   └── templates/
│       ├── deployment.yaml         # Pod 정의
│       ├── service.yaml            # K8s Service
│       ├── configmap.yaml          # 설정 파일
│       ├── virtualservice.yaml     # Istio 라우팅
│       ├── destinationrule.yaml    # Istio 트래픽 정책
│       └── httproute.yaml          # (선택) Gateway API
├── order-service/                  # 동일 구조
├── product-service/                # 동일 구조
├── payment-service/                # 동일 구조
├── recommendation-service/         # 동일 구조
└── saga-tracker/                   # 동일 구조
```

## ⚙️ 주요 설정

### Istio 설정

모든 서비스는 다음 Istio 기능을 사용합니다:

**VirtualService** - 라우팅 규칙
- Path-based routing
- Timeout: 30s
- Retries: 3회 시도 (10s per try)
- Retry 조건: 5xx, reset, connect-failure, refused-stream

**DestinationRule** - 트래픽 정책
- Connection Pool: TCP 100개, HTTP 50/100 요청
- Circuit Breaker: 5회 연속 5xx 에러 시 30초간 격리

**Gateway** - 외부 진입점
- HTTP (80) + HTTPS (443)
- Host: `api.c4ang.com`
- AWS NLB 사용

### 리소스 설정

| 서비스 | Replicas | CPU Request | CPU Limit | Memory Request | Memory Limit |
|--------|----------|-------------|-----------|----------------|--------------|
| Customer | 2 | 50m | 100m | 64Mi | 128Mi |
| Order | 2 | 50m | 100m | 64Mi | 128Mi |
| Product | 2 | 50m | 100m | 64Mi | 128Mi |
| Payment | 2 | 50m | 100m | 64Mi | 128Mi |
| Recommendation | 2 | 50m | 100m | 64Mi | 128Mi |
| Saga Tracker | 2 | 50m | 100m | 64Mi | 128Mi |

> **참고**: 위 수치는 테스트용입니다. 실제 프로덕션 환경에서는 부하 테스트 후 조정 필요.

## 🔧 일반적인 작업

### 새 서비스 추가

1. 기존 서비스 복사
```bash
cp -r customer-service new-service
```

2. Chart.yaml 수정
```yaml
name: new-service
description: New Service Microservice
```

3. values.yaml 수정
```yaml
fullnameOverride: new-api
image:
  repository: your-registry/new-service
  tag: v1.0.0
```

4. values-eks-test.yaml 수정
```yaml
istio:
  pathPrefix: /api/v1/newservice
```

5. 배포
```bash
helm template new-api helm/services/new-service \
  -n ecommerce -f helm/services/new-service/values-eks-test.yaml | \
  istioctl kube-inject -f - | \
  kubectl apply -f - -n ecommerce
```

### 라우팅 규칙 변경

1. `values-eks-test.yaml`의 `istio` 섹션 수정
```yaml
istio:
  pathPrefix: /api/v1/newpath
  timeout: 60s
  retries:
    attempts: 5
```

2. VirtualService 재배포
```bash
helm template service-name helm/services/service-name \
  --show-only templates/virtualservice.yaml \
  -n ecommerce -f values-eks-test.yaml | \
  kubectl apply -f - -n ecommerce
```

### 이미지 업데이트

```bash
kubectl set image deployment/order-api \
  order-service=your-registry/order-service:v1.1.0 \
  -n ecommerce

# 롤아웃 상태 확인
kubectl rollout status deployment/order-api -n ecommerce

# 롤백 (필요시)
kubectl rollout undo deployment/order-api -n ecommerce
```

## 🐛 문제 해결

### Pod가 시작되지 않을 때

```bash
# Pod 상태 확인
kubectl get pods -n ecommerce

# 상세 정보
kubectl describe pod <pod-name> -n ecommerce

# 로그 확인
kubectl logs <pod-name> -n ecommerce -c <container-name>

# Istio Proxy 로그
kubectl logs <pod-name> -n ecommerce -c istio-proxy
```

### Service Endpoints가 없을 때

```bash
# Endpoints 확인
kubectl get endpoints -n ecommerce

# Service Selector와 Pod Labels 비교
kubectl get svc <service-name> -n ecommerce -o yaml | grep selector -A 5
kubectl get pod <pod-name> -n ecommerce -o yaml | grep labels -A 10
```

### 외부 접근이 안될 때

```bash
# NLB 상태 확인
kubectl get svc istio-ingressgateway -n istio-system

# VirtualService 확인
kubectl get virtualservice -n ecommerce -o yaml

# Gateway 확인
kubectl get gateway -n ecommerce -o yaml

# Istio 설정 분석
istioctl analyze -n ecommerce
```

## 📚 더 알아보기

- [Istio 공식 문서](https://istio.io/latest/docs/)
- [Helm 공식 문서](https://helm.sh/docs/)
- [Kubernetes 공식 문서](https://kubernetes.io/docs/)
- [AWS EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)

## 🎯 다음 단계

1. ✅ DNS 설정 (Route53에 CNAME 레코드 추가)
2. ✅ TLS/HTTPS 설정 (ACM 또는 cert-manager)
3. ✅ 실제 애플리케이션 이미지로 교체
4. ⏳ Observability 구축 (Kiali, Prometheus, Grafana, Jaeger)
5. ⏳ mTLS 활성화
6. ⏳ CI/CD 파이프라인 구축
7. ⏳ Auto-scaling 설정

자세한 내용은 [EKS-ISTIO-DEPLOYMENT-SUMMARY.md](../../docs/EKS-ISTIO-DEPLOYMENT-SUMMARY.md)를 참고하세요.

---

**마지막 업데이트**: 2025-11-16  
**Istio 버전**: 1.28.0  
**EKS 버전**: 1.28+

