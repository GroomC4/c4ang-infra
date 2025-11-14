# Istio 설치 및 사용 가이드 (k3d)

k3d 환경에서 Istio를 설치하고 사용하는 방법입니다.

## 🚀 빠른 시작

### Istio 설치

```bash
cd k8s-dev-k3d/scripts
./install-istio.sh
```

이 스크립트는 다음을 수행합니다:
1. Istio Control Plane 설치 (istioctl)
2. Gateway API CRD 설치
3. Helm 차트로 Istio 설정 배포 (`helm/management-base/istio`)
4. Values 파일 사용 (`k8s-dev-k3d/values/istio.yaml`)

### 설치 확인

```bash
# Istio Control Plane 확인
kubectl get pods -n istio-system

# Gateway 확인
kubectl get gateway -n ecommerce

# Helm Release 확인
helm list -n ecommerce
```

## 📁 파일 구조

```
k8s-dev-k3d/
├── scripts/
│   ├── install-istio.sh        # Istio 설치 스크립트
│   └── uninstall-istio.sh      # Istio 제거 스크립트
├── values/
│   └── istio.yaml              # Istio 설정 (Helm values)
└── helm/management-base/istio/ # Istio Helm 차트
```

## 🔧 설정 변경

### Values 파일 수정

```bash
# values/istio.yaml 파일 수정
vi k8s-dev-k3d/values/istio.yaml

# 변경사항 적용
helm upgrade istio-config ../../helm/management-base/istio \
  -n ecommerce \
  -f k8s-dev-k3d/values/istio.yaml
```

### 서비스별 HTTPRoute 활성화

```bash
# values/istio.yaml에서 특정 서비스 활성화
# 예: order-service 활성화
helm upgrade istio-config ../../helm/management-base/istio \
  -n ecommerce \
  -f k8s-dev-k3d/values/istio.yaml \
  --set httpRoute.services.order.enabled=true
```

## 🧪 테스트

### 1. 테스트 애플리케이션 배포

```bash
# httpbin 배포
kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: httpbin
  namespace: ecommerce
spec:
  ports:
  - port: 8000
    targetPort: 80
  selector:
    app: httpbin
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: httpbin
  namespace: ecommerce
spec:
  replicas: 1
  selector:
    matchLabels:
      app: httpbin
  template:
    metadata:
      labels:
        app: httpbin
    spec:
      containers:
      - image: kennethreitz/httpbin:latest
        name: httpbin
        ports:
        - containerPort: 80
EOF
```

### 2. Gateway 접근 (Port Forward)

k3d 환경에서는 LoadBalancer가 NodePort로 매핑되므로 Port Forward를 사용:

```bash
# Gateway Pod로 Port Forward
export GATEWAY_POD=$(kubectl get pods -n ecommerce \
  -l gateway.networking.k8s.io/gateway-name=ecommerce-gateway \
  -o jsonpath='{.items[0].metadata.name}')

kubectl port-forward -n ecommerce $GATEWAY_POD 8080:80

# 다른 터미널에서 테스트
curl -H "Host: api.ecommerce.com" "http://localhost:8080/test/get"
```

## 📝 주요 명령어

### Helm 차트 관리

```bash
# 업데이트
helm upgrade istio-config ../../helm/management-base/istio \
  -n ecommerce \
  -f k8s-dev-k3d/values/istio.yaml

# 제거
helm uninstall istio-config -n ecommerce

# 또는 스크립트 사용
cd k8s-dev-k3d/scripts
./uninstall-istio.sh
```

### Gateway 상태 확인

```bash
# Gateway 확인
kubectl get gateway -n ecommerce

# HTTPRoute 확인
kubectl get httproute -n ecommerce

# Gateway Pod 확인
kubectl get pods -n ecommerce -l gateway.networking.k8s.io/gateway-name=ecommerce-gateway
```

## 🗑️ 제거

### Istio 설정 제거

```bash
cd k8s-dev-k3d/scripts
./uninstall-istio.sh
```

### Istio Control Plane 제거

```bash
istioctl uninstall --purge -y
kubectl delete namespace istio-system
```

## 📚 참고 자료

- [Helm 차트 가이드](../../helm/management-base/istio/README.md)
- [Istio 공식 문서](https://istio.io/latest/docs/)
- [k3d 공식 문서](https://k3d.io/)

