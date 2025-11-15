# EKS Istio 테스트 가이드

실제 이미지 없이 EKS에서 Istio 통합을 테스트하는 가이드입니다.

## 📋 사전 요구사항

### 1. EKS 클러스터 설정
```bash
# 현재 context 확인
kubectl config current-context

# EKS 클러스터로 전환
aws eks update-kubeconfig --name <cluster-name> --region ap-northeast-2
```

### 2. Istio 설치 확인
```bash
# Istio 설치 여부 확인
kubectl get namespace istio-system

# Istio 컴포넌트 확인
kubectl get pods -n istio-system

# Gateway API CRD 확인
kubectl get crd gateways.gateway.networking.k8s.io
```

### 3. Namespace 준비
```bash
# Namespace 생성
kubectl create namespace ecommerce

# Istio sidecar 자동 주입 활성화
kubectl label namespace ecommerce istio-injection=enabled

# Label 확인
kubectl get namespace ecommerce --show-labels
```

## 🚀 배포 방법

### Option 1: 자동 배포 스크립트 사용 (권장)

```bash
cd /Users/kim/Documents/GitHub/c4ang-infra/helm/services

# 1. Dry-run으로 검증
DRY_RUN=true ./deploy-test-eks.sh

# 2. 실제 배포
DRY_RUN=false ./deploy-test-eks.sh

# 또는
NAMESPACE=ecommerce ./deploy-test-eks.sh
```

### Option 2: 개별 서비스 배포

```bash
# 테스트용 이미지로 배포 (values-eks-test.yaml 사용)
helm upgrade --install customer-service ./customer-service \
  -f ./customer-service/values-eks-test.yaml \
  --namespace ecommerce \
  --create-namespace

# 또는 기본 이미지로 배포 (values.yaml 사용)
helm upgrade --install customer-service ./customer-service \
  --namespace ecommerce \
  --set istio.enabled=true \
  --set istio.gatewayAPI.enabled=true
```

## 🧪 테스트 이미지 정보

현재 `values-eks-test.yaml`에서 사용하는 테스트 이미지:
- **이미지**: `hashicorp/http-echo:1.0.0`
- **포트**: 5678 (ClusterIP Service는 8080으로 노출)
- **응답**: 각 서비스별로 다른 텍스트 메시지 반환

### 테스트 이미지 특징
✅ 가볍고 빠른 시작 (64MB 메모리, 50m CPU)
✅ HTTP 요청에 간단한 텍스트 응답
✅ Istio sidecar와 호환성 검증
✅ 네트워크 및 라우팅 테스트

## ✅ 배포 검증

### 1. Pod 상태 확인
```bash
# Pod 목록 확인
kubectl get pods -n ecommerce

# Istio sidecar injection 확인 (2/2 READY 여부)
# 정상: customer-api-xxx   2/2     Running
# 비정상: customer-api-xxx   1/1     Running (sidecar 없음)

# Pod 상세 정보
kubectl describe pod -n ecommerce <pod-name>

# Istio proxy 컨테이너 확인
kubectl get pod -n ecommerce <pod-name> -o jsonpath='{.spec.containers[*].name}'
# 출력 예시: customer-service istio-proxy
```

### 2. Service 확인
```bash
# Service 목록
kubectl get svc -n ecommerce

# Service 상세 정보
kubectl describe svc -n ecommerce customer-api
```

### 3. Istio 리소스 확인
```bash
# VirtualService 확인
kubectl get virtualservices -n ecommerce
kubectl describe virtualservice -n ecommerce customer-api-vs

# DestinationRule 확인
kubectl get destinationrules -n ecommerce
kubectl describe destinationrule -n ecommerce customer-api-dr

# HTTPRoute 확인 (Gateway API 활성화 시)
kubectl get httproutes -n ecommerce
kubectl describe httproute -n ecommerce customer-api-route
```

### 4. Gateway 확인
```bash
# Gateway 확인
kubectl get gateway -n ecommerce

# Gateway 상태
kubectl describe gateway -n ecommerce ecommerce-gateway
```

### 5. 로그 확인
```bash
# 애플리케이션 로그
kubectl logs -n ecommerce <pod-name> -c customer-service

# Istio proxy 로그
kubectl logs -n ecommerce <pod-name> -c istio-proxy

# 실시간 로그 모니터링
kubectl logs -n ecommerce <pod-name> -c istio-proxy -f
```

## 🔍 연결 테스트

### 1. Pod 간 통신 테스트
```bash
# 테스트용 Pod 생성
kubectl run test-pod --image=curlimages/curl:latest -n ecommerce --command -- sleep 3600

# 서비스 호출 테스트
kubectl exec -n ecommerce test-pod -- curl -s http://customer-api:8080

# 예상 응답: "Customer Service Test Response"
```

### 2. Istio Ingress를 통한 외부 접근
```bash
# Istio Ingress Gateway 주소 확인
kubectl get svc istio-ingressgateway -n istio-system

# ALB/NLB 엔드포인트 확인
GATEWAY_URL=$(kubectl get gateway ecommerce-gateway -n ecommerce -o jsonpath='{.status.addresses[0].value}')
echo $GATEWAY_URL

# 서비스 테스트
curl http://$GATEWAY_URL/api/v1/customers
```

### 3. Kiali로 서비스 메시 시각화
```bash
# Kiali 접속 (사전 설치 필요)
istioctl dashboard kiali

# 또는 Port-forward
kubectl port-forward -n istio-system svc/kiali 20001:20001
# 브라우저에서 http://localhost:20001 접속
```

## 🐛 트러블슈팅

### Pod가 Pending 상태
```bash
# 원인 확인
kubectl describe pod -n ecommerce <pod-name>

# 일반적인 원인:
# - 리소스 부족 (CPU/Memory)
# - Node selector 미스매치
# - PV/PVC 문제
```

### Istio Sidecar가 주입되지 않음
```bash
# Namespace label 확인
kubectl get namespace ecommerce --show-labels | grep istio-injection

# Label이 없으면 추가
kubectl label namespace ecommerce istio-injection=enabled --overwrite

# Pod 재시작
kubectl rollout restart deployment -n ecommerce
```

### HTTPRoute가 작동하지 않음
```bash
# Gateway 상태 확인
kubectl describe gateway ecommerce-gateway -n ecommerce

# HTTPRoute와 Gateway 연결 확인
kubectl get httproute -n ecommerce -o yaml

# Gateway API CRD 버전 확인
kubectl get crd gateways.gateway.networking.k8s.io -o yaml | grep version
```

### Circuit Breaker 테스트
```bash
# 부하 생성하여 Circuit Breaker 동작 확인
kubectl exec -n ecommerce test-pod -- sh -c "
  for i in \$(seq 1 100); do
    curl -s http://customer-api:8080 &
  done
  wait
"

# DestinationRule의 outlierDetection이 작동하는지 확인
kubectl logs -n ecommerce <pod-name> -c istio-proxy | grep -i "outlier"
```

## 📊 Istio 메트릭 확인

### Prometheus 쿼리
```bash
# Istio Prometheus 접속
kubectl port-forward -n istio-system svc/prometheus 9090:9090

# 브라우저에서 http://localhost:9090
# 쿼리 예시:
# - istio_requests_total
# - istio_request_duration_milliseconds
# - istio_tcp_connections_opened_total
```

### Grafana 대시보드
```bash
# Grafana 접속
kubectl port-forward -n istio-system svc/grafana 3000:3000

# 브라우저에서 http://localhost:3000
# Istio 관련 대시보드 확인
```

## 🎯 다음 단계

### 1. 실제 이미지로 전환
```bash
# values.yaml의 이미지를 실제 ECR 이미지로 변경
helm upgrade customer-service ./customer-service \
  --namespace ecommerce \
  --set image.repository=<your-ecr-repo> \
  --set image.tag=<your-tag> \
  --reuse-values
```

### 2. 추가 Istio 기능 테스트
- **Traffic Splitting**: Canary 배포
- **Fault Injection**: 장애 시뮬레이션
- **Rate Limiting**: 요청 제한
- **mTLS**: 서비스 간 암호화 통신

### 3. 모니터링 구성
- Prometheus + Grafana
- Jaeger (Distributed Tracing)
- Kiali (Service Mesh 시각화)

## 📚 참고 자료

- [Istio 공식 문서](https://istio.io/latest/docs/)
- [Kubernetes Gateway API](https://gateway-api.sigs.k8s.io/)
- [EKS Istio 통합 가이드](https://aws.amazon.com/blogs/containers/service-mesh-on-amazon-eks/)

## ⚠️ 주의사항

1. **테스트 환경**: 이 설정은 프로덕션이 아닌 테스트용입니다
2. **리소스 제한**: 테스트 이미지는 최소 리소스로 설정되어 있습니다
3. **보안**: 실제 배포 시 Secret, NetworkPolicy 등 추가 보안 설정 필요
4. **모니터링**: 프로덕션 환경에서는 적절한 모니터링 구성 필수

## 🧹 정리 (Clean up)

```bash
# 특정 서비스 삭제
helm uninstall customer-service -n ecommerce

# 모든 서비스 삭제
helm list -n ecommerce | awk 'NR>1 {print $1}' | xargs -I {} helm uninstall {} -n ecommerce

# Namespace 삭제 (주의!)
kubectl delete namespace ecommerce
```

