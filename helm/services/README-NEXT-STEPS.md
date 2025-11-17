# 다음 단계 - Istio 배포 완료 후

## 🎉 완료된 작업

1. ✅ **모든 서비스 배포 완료** (6개 서비스, 12개 Pod)
2. ✅ **Istio Sidecar 수동 주입** (모든 Pod 2/2 Running)
3. ✅ **NLB 설정 완료** (AWS Network Load Balancer)
4. ✅ **Istio 리소스 구성** (VirtualService, DestinationRule, Gateway)
5. ✅ **배포 자동화 스크립트 작성**

## 📝 남은 작업 실행 방법

### 새 터미널 세션에서 실행하세요

현재 shell에 문제가 있으므로 **새 터미널**을 열어서 다음 작업을 진행하세요:

### 1. 스크립트 실행 권한 부여

```bash
cd /Users/kim/Documents/GitHub/c4ang-infra/helm/services

chmod +x deploy-with-sidecar-injection.sh
chmod +x test-istio-gateway.sh
chmod +x install-gateway-api.sh
```

### 2. Istio Gateway 테스트

```bash
./test-istio-gateway.sh
```

**이 스크립트가 수행하는 작업:**
- Pod 상태 확인 (모든 Pod가 2/2 Running인지)
- Istio 리소스 확인 (VirtualService, DestinationRule, Gateway)
- NLB 주소 확인
- 클러스터 내부 접근 테스트
- 외부 접근 테스트 (curl 가능 시)
- Istio Proxy 로그 확인

### 3. Gateway API CRD 설치 (선택사항)

HTTPRoute를 사용하려면:

```bash
./install-gateway-api.sh
```

설치 후 서비스 재배포:

```bash
./deploy-with-sidecar-injection.sh
```

**참고:** VirtualService만으로도 충분히 작동하므로 필수는 아닙니다.

### 4. 외부 접근 테스트 (수동)

```bash
# NLB 주소 가져오기
LB_HOST=$(kubectl get svc istio-ingressgateway -n istio-system \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

echo "NLB 주소: $LB_HOST"

# Customer Service 테스트
curl -H "Host: api.c4ang.com" http://$LB_HOST/api/v1/customers

# Order Service 테스트  
curl -H "Host: api.c4ang.com" http://$LB_HOST/api/v1/orders

# Product Service 테스트
curl -H "Host: api.c4ang.com" http://$LB_HOST/api/v1/products

# Payment Service 테스트
curl -H "Host: api.c4ang.com" http://$LB_HOST/api/v1/payments

# Recommendation Service 테스트
curl -H "Host: api.c4ang.com" http://$LB_HOST/api/v1/recommendations

# Saga Tracker 테스트
curl -H "Host: api.c4ang.com" http://$LB_HOST/api/v1/saga
```

## 📚 상세 가이드

전체 배포 가이드는 다음 문서를 참고하세요:

```bash
cat /Users/kim/Documents/GitHub/c4ang-infra/helm/services/ISTIO-DEPLOYMENT-GUIDE.md
```

또는 IDE에서 `ISTIO-DEPLOYMENT-GUIDE.md` 파일을 열어보세요.

## 🔧 작성된 스크립트

### 1. `deploy-with-sidecar-injection.sh`
- **용도**: 모든 서비스에 Istio Sidecar를 수동으로 주입하여 배포
- **사용 시기**: 새 서비스 추가 시 또는 서비스 재배포 시

### 2. `test-istio-gateway.sh`
- **용도**: Istio Gateway와 모든 서비스의 동작 확인
- **사용 시기**: 배포 후 검증, 문제 발생 시 진단

### 3. `install-gateway-api.sh`
- **용도**: Kubernetes Gateway API CRD 설치
- **사용 시기**: HTTPRoute 사용을 원할 경우 (선택사항)

## 🚀 빠른 검증

새 터미널에서 다음 명령어로 현재 상태를 빠르게 확인:

```bash
cd /Users/kim/Documents/GitHub/c4ang-infra/helm/services

echo "=== Pod 상태 ==="
kubectl get pods -n ecommerce | grep "2/2"
echo ""

echo "=== VirtualService ==="
kubectl get virtualservice -n ecommerce
echo ""

echo "=== Gateway ==="
kubectl get gateway -n ecommerce
echo ""

echo "=== NLB 주소 ==="
kubectl get svc istio-ingressgateway -n istio-system \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
echo ""
```

## ⚠️ 현재 알려진 문제

### Istio Webhook Timeout

**증상:** 자동 Sidecar 주입이 작동하지 않음

**해결:** 수동 Sidecar 주입 사용 중 (현재 방식)

**장기 해결책:**
1. EKS 보안 그룹 확인
2. Istio 재설치 고려
3. Webhook timeout 설정 증가

자세한 내용은 `ISTIO-DEPLOYMENT-GUIDE.md`의 "문제 해결" 섹션 참조

## 📊 현재 배포 상태

```
Namespace: ecommerce

Services (6):
  ├─ customer-api (2 pods)
  ├─ order-api (2 pods)
  ├─ product-api (2 pods)
  ├─ payment-api (2 pods)
  ├─ recommendation-api (2 pods)
  └─ saga-tracker-api (2 pods)

Istio Resources:
  ├─ VirtualServices: 6개
  ├─ DestinationRules: 6개
  └─ Gateway: 1개 (NLB 연결)

Total: 12 Pods (모두 2/2 Running with Istio Sidecar)
```

## 🎯 다음 권장 작업

1. **즉시 실행**: `./test-istio-gateway.sh` - 현재 상태 검증
2. **선택사항**: `./install-gateway-api.sh` - HTTPRoute 사용 원할 경우
3. **프로덕션 준비**:
   - TLS 인증서 설정
   - DNS (Route53) 설정
   - Observability 도구 설치 (Kiali, Grafana, Jaeger)
   - mTLS 활성화

각 작업의 자세한 방법은 `ISTIO-DEPLOYMENT-GUIDE.md`를 참고하세요.

## 🆘 도움이 필요한 경우

1. `ISTIO-DEPLOYMENT-GUIDE.md`의 "문제 해결" 섹션 확인
2. `./test-istio-gateway.sh` 실행하여 상태 점검
3. Istio Proxy 로그 확인:
   ```bash
   kubectl logs <pod-name> -n ecommerce -c istio-proxy
   ```


