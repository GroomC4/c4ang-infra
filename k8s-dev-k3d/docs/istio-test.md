# k3d 환경에서 Istio 테스트 가이드

k3d 클러스터에서 Istio를 설치하고 테스트하는 방법입니다.

## 🚀 빠른 시작

### 1. Istio 설치

```bash
# k3d Istio 디렉토리로 이동
cd k8s-dev-k3d/istio

# Istio 설치 스크립트 실행
./install-istio.sh
```

### 2. 설치 확인

```bash
# Istio Control Plane 확인
kubectl get pods -n istio-system

# Gateway 확인
kubectl get gateway -n ecommerce

# HTTPRoute 확인
kubectl get httproute -n ecommerce
```

### 3. 테스트 애플리케이션 배포

```bash
# httpbin 배포 (테스트용 HTTP 서버)
kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: httpbin
  namespace: ecommerce
  labels:
    app: httpbin
spec:
  ports:
  - name: http
    port: 8000
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
        imagePullPolicy: IfNotPresent
        name: httpbin
        ports:
        - containerPort: 80
EOF

# Pod 준비 대기
kubectl wait --for=condition=ready pod -l app=httpbin -n ecommerce --timeout=120s
```

### 4. HTTPRoute 생성

```bash
kubectl apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: httpbin-route
  namespace: ecommerce
spec:
  parentRefs:
    - name: ecommerce-gateway
  hostnames:
    - "api.ecommerce.com"
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /test
      backendRefs:
        - name: httpbin
          port: 8000
          weight: 100
EOF
```

## 🔍 k3d 환경 특이사항

### LoadBalancer 타입

k3d에서는 LoadBalancer 타입의 서비스가 자동으로 **NodePort**로 매핑됩니다.

```bash
# Gateway Service 확인 (NodePort로 매핑됨)
kubectl get svc -n ecommerce ecommerce-gateway-istio

# 예시 출력:
# NAME                      TYPE           CLUSTER-IP    EXTERNAL-IP   PORT(S)
# ecommerce-gateway-istio   LoadBalancer   10.43.x.x     172.18.0.2    443:31345/TCP,80:31623/TCP
```

### 접근 방법

#### 방법 1: NodePort 직접 사용

```bash
# NodePort 확인
export HTTP_PORT=$(kubectl get svc -n ecommerce ecommerce-gateway-istio -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}')
export HTTPS_PORT=$(kubectl get svc -n ecommerce ecommerce-gateway-istio -o jsonpath='{.spec.ports[?(@.name=="https")].nodePort}')

echo "HTTP Port: $HTTP_PORT"
echo "HTTPS Port: $HTTPS_PORT"

# 테스트 (Host 헤더 필요)
curl -H "Host: api.ecommerce.com" "http://localhost:$HTTP_PORT/test/get"
```

#### 방법 2: Port Forward 사용 (권장)

```bash
# Gateway Pod로 Port Forward
export GATEWAY_POD=$(kubectl get pods -n ecommerce -l gateway.networking.k8s.io/gateway-name=ecommerce-gateway -o jsonpath='{.items[0].metadata.name}')

# Port Forward
kubectl port-forward -n ecommerce $GATEWAY_POD 8080:80 8443:443

# 다른 터미널에서 테스트
curl -H "Host: api.ecommerce.com" "http://localhost:8080/test/get"
```

#### 방법 3: k3d LoadBalancer 직접 사용

k3d 클러스터 생성 시 포트 매핑이 설정되어 있다면:

```bash
# k3d 클러스터 포트 확인
k3d cluster list

# 예시: 포트 매핑이 80:80@loadbalancer로 설정되어 있다면
curl -H "Host: api.ecommerce.com" "http://localhost:80/test/get"
```

### Hosts 파일 설정 (선택사항)

로컬에서 `api.ecommerce.com`으로 접근하려면 `/etc/hosts`에 추가:

```bash
# macOS/Linux
echo "127.0.0.1 api.ecommerce.com" | sudo tee -a /etc/hosts

# Windows (관리자 권한 필요)
# C:\Windows\System32\drivers\etc\hosts 파일에 추가:
# 127.0.0.1 api.ecommerce.com
```

## 🧪 Helm 차트로 테스트

### Helm 차트 배포

```bash
# Helm 차트로 Istio 설정 배포
helm install istio-config ./helm/management-base/istio \
  --namespace ecommerce \
  --create-namespace \
  --set gateway.main.hostname=api.ecommerce.com \
  --set httpRoute.services.order.enabled=false \
  --set httpRoute.services.product.enabled=false
```

### Helm 차트 업데이트

```bash
# 설정 업데이트
helm upgrade istio-config ./helm/management-base/istio \
  --namespace ecommerce \
  --set security.mTLS.mode=PERMISSIVE
```

### Helm 차트 제거

```bash
helm uninstall istio-config --namespace ecommerce
```

## 📋 테스트 체크리스트

### 1. Istio 설치 확인

```bash
# Control Plane 확인
kubectl get pods -n istio-system
# istiod Pod가 Running 상태여야 함

# Gateway 확인
kubectl get gateway -n ecommerce
# ecommerce-gateway가 PROGRAMMED=True 상태여야 함
```

### 2. Sidecar 주입 확인

```bash
# Pod에 Sidecar가 주입되었는지 확인 (2개의 컨테이너)
kubectl get pod -n ecommerce -l app=httpbin -o jsonpath='{.items[0].spec.containers[*].name}'
# 출력: httpbin istio-proxy
```

### 3. Gateway 접근 테스트

```bash
# Port Forward로 접근
kubectl port-forward -n ecommerce \
  $(kubectl get pods -n ecommerce -l gateway.networking.k8s.io/gateway-name=ecommerce-gateway -o jsonpath='{.items[0].metadata.name}') \
  8080:80

# 다른 터미널에서
curl -H "Host: api.ecommerce.com" "http://localhost:8080/test/get"
```

### 4. mTLS 확인

```bash
# mTLS 인증서 확인
export POD_NAME=$(kubectl get pods -n ecommerce -l app=httpbin -o jsonpath='{.items[0].metadata.name}')
istioctl proxy-config secret ${POD_NAME}.ecommerce
```

## 🐛 문제 해결

### Gateway가 준비되지 않음

```bash
# Gateway 상태 확인
kubectl describe gateway ecommerce-gateway -n ecommerce

# Gateway Pod 확인
kubectl get pods -n ecommerce -l gateway.networking.k8s.io/gateway-name=ecommerce-gateway

# Pod 로그 확인
kubectl logs -n ecommerce -l gateway.networking.k8s.io/gateway-name=ecommerce-gateway
```

### Sidecar가 주입되지 않음

```bash
# 네임스페이스 라벨 확인
kubectl get namespace ecommerce --show-labels
# istio-injection=enabled 라벨이 있어야 함

# 라벨 추가
kubectl label namespace ecommerce istio-injection=enabled --overwrite

# Pod 재생성 (자동 주입)
kubectl delete pod -n ecommerce -l app=httpbin
```

### 접근할 수 없음

```bash
# Service 확인
kubectl get svc -n ecommerce ecommerce-gateway-istio

# NodePort 확인
kubectl get svc -n ecommerce ecommerce-gateway-istio -o jsonpath='{.spec.ports[*].nodePort}'

# Port Forward 사용
kubectl port-forward -n ecommerce \
  $(kubectl get pods -n ecommerce -l gateway.networking.k8s.io/gateway-name=ecommerce-gateway -o jsonpath='{.items[0].metadata.name}') \
  8080:80
```

## 🧹 정리

### 테스트 애플리케이션 제거

```bash
kubectl delete httproute httpbin-route -n ecommerce
kubectl delete deployment httpbin -n ecommerce
kubectl delete service httpbin -n ecommerce
```

### Istio 제거

```bash
cd k8s-dev-k3d/istio
./uninstall-istio.sh

# Control Plane 제거 (선택사항)
REMOVE_CONTROL_PLANE=true ./uninstall-istio.sh
```

## 📚 참고 자료

- [k3d 공식 문서](https://k3d.io/)
- [Istio 공식 문서](https://istio.io/latest/docs/)
- [k3d Istio 가이드](../k8s-dev-k3d/istio/README.md)

