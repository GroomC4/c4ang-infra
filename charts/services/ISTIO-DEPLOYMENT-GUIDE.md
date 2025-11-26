# Istio 배포 가이드 - EKS 환경

이 문서는 Istio Sidecar 수동 주입을 사용한 EKS 배포 가이드입니다.

## 📋 목차

1. [현재 상태](#현재-상태)
2. [배포된 서비스](#배포된-서비스)
3. [Istio 리소스](#istio-리소스)
4. [테스트 방법](#테스트-방법)
5. [문제 해결](#문제-해결)
6. [남은 작업](#남은-작업)

## 현재 상태

### ✅ 완료된 작업

- **모든 서비스 배포 완료**: 6개 서비스 (12개 Pod)
- **Istio Sidecar 주입**: 모든 Pod가 2/2 Running 상태
- **NLB 설정**: AWS Network Load Balancer 연결 완료
- **Istio 리소스 구성**: VirtualService, DestinationRule, Gateway 설정 완료

### 🔧 기술 스택

- **Kubernetes**: EKS 1.28+
- **Istio**: 1.28.0
- **Service Mesh**: Istio with Manual Sidecar Injection
- **Load Balancer**: AWS NLB

## 배포된 서비스

| 서비스명 | API Path | Replica | 상태 |
|---------|----------|---------|------|
| Customer Service | `/api/v1/customers` | 2 | 2/2 Running |
| Order Service | `/api/v1/orders` | 2 | 2/2 Running |
| Product Service | `/api/v1/products` | 2 | 2/2 Running |
| Payment Service | `/api/v1/payments` | 2 | 2/2 Running |
| Recommendation Service | `/api/v1/recommendations` | 2 | 2/2 Running |
| Saga Tracker | `/api/v1/saga` | 2 | 2/2 Running |

### 서비스 상태 확인

```bash
kubectl get pods -n ecommerce
kubectl get svc -n ecommerce
```

## Istio 리소스

### 1. VirtualService (6개)

각 서비스마다 VirtualService가 생성되어 있습니다:

```bash
kubectl get virtualservice -n ecommerce
```

**주요 설정:**
- **Retry Policy**: 3회 재시도, 10초 timeout
- **Circuit Breaker**: DestinationRule과 연동
- **Gateway 연결**: `ecommerce-gateway`와 연결

### 2. DestinationRule (6개)

트래픽 관리 정책이 설정되어 있습니다:

```bash
kubectl get destinationrule -n ecommerce
```

**주요 설정:**
- **Connection Pool**: TCP 최대 100개 연결, HTTP2 최대 100개 요청
- **Outlier Detection**: 연속 5xx 에러 5회 시 Circuit Open
- **Load Balancing**: Round Robin (기본값)

### 3. Gateway (1개)

외부 트래픽 진입점:

```bash
kubectl get gateway -n ecommerce
```

**설정:**
- **HTTP Port**: 80
- **HTTPS Port**: 443 (TLS 인증서: `ecommerce-tls-cert`)
- **Hosts**: `api.c4ang.com`, `*`

### 4. Ingress Gateway

AWS NLB를 통한 외부 접근:

```bash
kubectl get svc istio-ingressgateway -n istio-system
```

**NLB 주소 확인:**
```bash
kubectl get svc istio-ingressgateway -n istio-system \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

## 테스트 방법

### 자동 테스트 스크립트 사용

```bash
cd /Users/kim/Documents/GitHub/c4ang-infra/helm/services
chmod +x test-istio-gateway.sh
./test-istio-gateway.sh
```

이 스크립트는 다음을 수행합니다:
1. Pod 상태 확인
2. Istio 리소스 확인
3. Ingress Gateway 확인
4. 클러스터 내부 접근 테스트
5. 외부 접근 테스트 (curl 가능 시)
6. Istio Proxy 로그 확인

### 수동 테스트

#### 1. 클러스터 내부에서 테스트

```bash
kubectl run test-curl \
  --image=curlimages/curl:latest \
  --restart=Never \
  -n ecommerce \
  --rm -i \
  --command -- \
  curl -s -H "Host: api.c4ang.com" \
  http://istio-ingressgateway.istio-system.svc.cluster.local/api/v1/customers
```

#### 2. 로컬에서 외부 접근 테스트

```bash
# NLB 주소 가져오기
LB_HOST=$(kubectl get svc istio-ingressgateway -n istio-system \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Customer Service 테스트
curl -H "Host: api.c4ang.com" http://$LB_HOST/api/v1/customers

# Order Service 테스트
curl -H "Host: api.c4ang.com" http://$LB_HOST/api/v1/orders

# Product Service 테스트
curl -H "Host: api.c4ang.com" http://$LB_HOST/api/v1/products
```

#### 3. Istio Proxy 로그 확인

```bash
# 특정 Pod의 Istio Proxy 로그
kubectl logs <pod-name> -n ecommerce -c istio-proxy

# 실시간 로그
kubectl logs <pod-name> -n ecommerce -c istio-proxy -f
```

## 문제 해결

### Istio Webhook Timeout 문제

**증상:**
```
Error creating: Internal error occurred: failed calling webhook "namespace.sidecar-injector.istio.io": 
failed to call webhook: Post "https://istiod.istio-system.svc:443/inject?timeout=10s": 
context deadline exceeded
```

**해결 방법:**
수동 Sidecar 주입 사용 (현재 사용 중인 방법):

```bash
cd /Users/kim/Documents/GitHub/c4ang-infra/helm/services
chmod +x deploy-with-sidecar-injection.sh
./deploy-with-sidecar-injection.sh
```

**근본 해결 (장기 과제):**
1. EKS 보안 그룹에서 istiod의 443 포트 허용 확인
2. Istio 재설치:
   ```bash
   cd /Users/kim/Documents/GitHub/c4ang-infra/k8s-eks/istio
   ./install-istio.sh
   ```

### VirtualService가 Gateway와 연결되지 않음

**확인:**
```bash
kubectl get virtualservice -n ecommerce
```

GATEWAYS 컬럼이 비어있으면:

```bash
kubectl patch virtualservice <vs-name> -n ecommerce \
  --type='json' \
  -p='[{"op": "add", "path": "/spec/gateways", "value": ["ecommerce-gateway"]}]'
```

### 외부 접근이 안됨

**체크리스트:**
1. NLB가 정상적으로 생성되었는지 확인
   ```bash
   kubectl get svc istio-ingressgateway -n istio-system
   ```

2. VirtualService hosts 설정 확인
   ```bash
   kubectl get virtualservice <vs-name> -n ecommerce -o yaml | grep hosts:
   ```
   
   `api.c4ang.com` 또는 `*`가 포함되어야 함

3. Gateway selector 확인
   ```bash
   kubectl get gateway ecommerce-gateway -n ecommerce -o yaml | grep selector: -A2
   ```
   
   `istio: ingressgateway`여야 함

4. 내부 접근 테스트
   클러스터 내부에서는 접근되는지 확인

### Pod가 1/1 상태로 유지됨

Sidecar가 주입되지 않은 상태입니다. 재배포 필요:

```bash
export PATH="/Users/kim/Documents/GitHub/c4ang-infra/k8s-eks/istio/istio-1.28.0/bin:$PATH"
cd /Users/kim/Documents/GitHub/c4ang-infra

# 특정 서비스만 재배포
helm template <service-api> helm/services/<service-name> \
  -n ecommerce \
  -f helm/services/<service-name>/values-eks-test.yaml | \
  istioctl kube-inject -f - | \
  kubectl apply -f - -n ecommerce
```

## 남은 작업

### 1. Gateway API CRD 설치 (선택사항)

HTTPRoute를 사용하려면 Gateway API CRD 설치 필요:

```bash
cd /Users/kim/Documents/GitHub/c4ang-infra/helm/services
chmod +x install-gateway-api.sh
./install-gateway-api.sh
```

설치 후 서비스 재배포하여 HTTPRoute 리소스 생성.

**참고:** VirtualService만으로도 충분히 작동하므로 선택사항입니다.

### 2. TLS 인증서 설정

현재 Gateway에 TLS 설정이 있지만 실제 인증서가 없습니다:

```bash
# Self-signed 인증서 생성 (테스트용)
openssl req -x509 -newkey rsa:4096 \
  -keyout /tmp/tls.key -out /tmp/tls.crt \
  -days 365 -nodes \
  -subj "/CN=api.c4ang.com"

# Secret 생성
kubectl create secret tls ecommerce-tls-cert \
  --key=/tmp/tls.key \
  --cert=/tmp/tls.crt \
  -n istio-system
```

**프로덕션:** ACM(AWS Certificate Manager)이나 Let's Encrypt 사용 권장

### 3. DNS 설정

Route53에 CNAME 레코드 추가:

```
api.c4ang.com  CNAME  <NLB-HOSTNAME>
```

NLB 주소:
```bash
kubectl get svc istio-ingressgateway -n istio-system \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

### 4. Observability 설정

#### Kiali (Istio 대시보드)

```bash
# Kiali 설치 (Istio에 포함)
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.28/samples/addons/kiali.yaml

# 포트 포워딩
kubectl port-forward -n istio-system svc/kiali 20001:20001

# 브라우저에서 접근
open http://localhost:20001
```

#### Grafana (메트릭)

```bash
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.28/samples/addons/grafana.yaml
kubectl port-forward -n istio-system svc/grafana 3000:3000
```

#### Jaeger (분산 추적)

```bash
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.28/samples/addons/jaeger.yaml
kubectl port-forward -n istio-system svc/tracing 16686:80
```

### 5. mTLS 활성화

서비스 간 상호 TLS 인증:

```yaml
# peer-authentication.yaml
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: ecommerce
spec:
  mtls:
    mode: STRICT
```

```bash
kubectl apply -f peer-authentication.yaml
```

## 유용한 명령어

### Istio 상태 확인

```bash
# Istio 컴포넌트 상태
kubectl get pods -n istio-system

# Istio 설정 확인
istioctl verify-install

# Proxy 상태
istioctl proxy-status
```

### 디버깅

```bash
# 특정 Pod의 Istio 설정 확인
istioctl proxy-config routes <pod-name> -n ecommerce

# VirtualService 적용 여부 확인
istioctl proxy-config listeners <pod-name> -n ecommerce

# Envoy 로그 레벨 변경
istioctl proxy-config log <pod-name> -n ecommerce --level debug
```

### 리소스 정리

```bash
# 모든 서비스 삭제
kubectl delete deployment,service,configmap -n ecommerce --all

# Istio 리소스 삭제
kubectl delete virtualservice,destinationrule,gateway -n ecommerce --all

# Namespace 삭제
kubectl delete namespace ecommerce
```

## 참고 자료

- [Istio 공식 문서](https://istio.io/latest/docs/)
- [Istio Traffic Management](https://istio.io/latest/docs/concepts/traffic-management/)
- [EKS Best Practices - Service Mesh](https://aws.github.io/aws-eks-best-practices/servicemesh/)
- [Kubernetes Gateway API](https://gateway-api.sigs.k8s.io/)

## 연락처

문제 발생 시:
1. 먼저 이 가이드의 [문제 해결](#문제-해결) 섹션 확인
2. Istio Proxy 로그 확인
3. `test-istio-gateway.sh` 스크립트 실행하여 상태 점검


