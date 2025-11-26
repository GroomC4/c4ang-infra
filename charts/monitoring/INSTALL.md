# Monitoring Stack 설치 가이드

## 빠른 시작 (Quick Start)

### 1단계: 네임스페이스 확인

```bash
kubectl create namespace monitoring
```

### 2단계: Helm 설치

```bash
# 리포지토리 루트에서
cd helm/management-base/monitoring

# 기본 설치
helm install monitoring . -n monitoring

# 설치 확인
kubectl get pods -n monitoring -w
```

### 3단계: Grafana 접속

```bash
# 포트 포워딩
kubectl port-forward -n monitoring svc/grafana 3000:3000

# 웹 브라우저에서 접속
# URL: http://localhost:3000
# Username: admin
# Password: admin (기본값)
```

## 프로덕션 설치

### 사전 준비

1. **values-production.yaml** 생성:

```yaml
namespace: monitoring

# ECR 이미지 풀 시크릿
imagePullSecrets:
  - name: ecr-creds

# Grafana 설정
grafana:
  admin:
    password: "ChangeThisStrongPassword123!"
  storage:
    size: 10Gi
    storageClassName: "gp3"

# Prometheus 설정
prometheus:
  storage:
    size: 100Gi
    storageClassName: "gp3"
  retention:
    time: 90d
    size: 95GB
  resources:
    requests:
      cpu: "1000m"
      memory: "4Gi"
    limits:
      cpu: "2000m"
      memory: "8Gi"

# Loki 설정
loki:
  storage:
    size: 50Gi
    storageClassName: "gp3"
  retention:
    period: 180d
  resources:
    requests:
      cpu: "1000m"
      memory: "2Gi"
    limits:
      cpu: "2000m"
      memory: "4Gi"

# Tempo 설정
tempo:
  storage:
    size: 50Gi
    storageClassName: "gp3"
  retention:
    period: 60d
  sampling:
    rate: 0.1  # 10% 샘플링

# 알림 설정
alerting:
  enabled: true
  slack:
    enabled: true
    webhookUrl: "https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
    channel: "#monitoring-alerts"
```

2. **ECR 시크릿 생성** (프라이빗 레지스트리 사용 시):

```bash
aws ecr get-login-password --region ap-northeast-2 | \
  kubectl create secret docker-registry ecr-creds \
    --docker-server=123456789012.dkr.ecr.ap-northeast-2.amazonaws.com \
    --docker-username=AWS \
    --docker-password-stdin \
    -n monitoring
```

### 설치 실행

```bash
# Helm 차트 의존성 업데이트 (필요한 경우)
helm dependency update

# Dry-run으로 검증
helm install monitoring . -n monitoring \
  -f values-production.yaml \
  --dry-run --debug

# 실제 설치
helm install monitoring . -n monitoring \
  -f values-production.yaml

# 설치 확인
kubectl get all -n monitoring
```

### 설치 검증

```bash
# 1. Pod 상태 확인
kubectl get pods -n monitoring

# 예상 출력:
# NAME                          READY   STATUS    RESTARTS   AGE
# alloy-xxxxx                   1/1     Running   0          5m
# prometheus-xxxxx              1/1     Running   0          5m
# loki-xxxxx                    1/1     Running   0          5m
# tempo-xxxxx                   1/1     Running   0          5m
# grafana-xxxxx                 1/1     Running   0          5m

# 2. 서비스 확인
kubectl get svc -n monitoring

# 3. PVC 확인
kubectl get pvc -n monitoring

# 4. 로그 확인
kubectl logs -n monitoring -l app.kubernetes.io/component=alloy --tail=50
kubectl logs -n monitoring -l app.kubernetes.io/component=prometheus --tail=50
kubectl logs -n monitoring -l app.kubernetes.io/component=grafana --tail=50
```

## Argo CD GitOps 배포

### Application 매니페스트

`monitoring-app.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: monitoring
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  
  source:
    repoURL: https://github.com/GroomC4/c4ang-infra.git
    targetRevision: main
    path: helm/management-base/monitoring
    helm:
      valueFiles:
        - values.yaml
        - values-production.yaml  # 프로덕션 설정
  
  destination:
    server: https://kubernetes.default.svc
    namespace: monitoring
  
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
      allowEmpty: false
    syncOptions:
      - CreateNamespace=true
      - PrunePropagationPolicy=foreground
      - PruneLast=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
  
  ignoreDifferences:
    - group: apps
      kind: Deployment
      jsonPointers:
        - /spec/replicas
```

### 배포 실행

```bash
# Application 생성
kubectl apply -f monitoring-app.yaml

# 동기화 상태 확인
argocd app get monitoring

# 수동 동기화 (필요 시)
argocd app sync monitoring

# 상태 모니터링
argocd app watch monitoring
```

## 업그레이드

### Helm 업그레이드

```bash
# values 파일 수정 후
helm upgrade monitoring . -n monitoring \
  -f values-production.yaml

# 롤백 (문제 발생 시)
helm rollback monitoring -n monitoring
```

### Argo CD 업그레이드

```bash
# Git에 변경사항 커밋
git add helm/management-base/monitoring/
git commit -m "Update monitoring configuration"
git push origin main

# Argo CD가 자동으로 동기화 (automated sync 설정 시)
# 또는 수동 동기화
argocd app sync monitoring
```

## 제거 (Uninstall)

### Helm 제거

```bash
# Helm 릴리스 삭제
helm uninstall monitoring -n monitoring

# PVC 삭제 (데이터 완전 삭제)
kubectl delete pvc -n monitoring --all

# 네임스페이스 삭제
kubectl delete namespace monitoring
```

### Argo CD 제거

```bash
# Application 삭제
kubectl delete application monitoring -n argocd

# 또는 argocd CLI 사용
argocd app delete monitoring --cascade
```

## 트러블슈팅

### Pod가 Pending 상태

```bash
# PVC 상태 확인
kubectl get pvc -n monitoring

# 이벤트 확인
kubectl get events -n monitoring --sort-by='.lastTimestamp'

# 스토리지 클래스 확인
kubectl get storageclass

# 해결: 기본 스토리지 클래스 설정
kubectl patch storageclass gp3 \
  -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

### ImagePullBackOff 에러

```bash
# 이미지 풀 시크릿 확인
kubectl get secret -n monitoring ecr-creds

# ECR 토큰 갱신
kubectl delete secret ecr-creds -n monitoring
aws ecr get-login-password --region ap-northeast-2 | \
  kubectl create secret docker-registry ecr-creds \
    --docker-server=123456789012.dkr.ecr.ap-northeast-2.amazonaws.com \
    --docker-username=AWS \
    --docker-password-stdin \
    -n monitoring

# Pod 재시작
kubectl rollout restart deployment -n monitoring
```

### CrashLoopBackOff

```bash
# 로그 확인
kubectl logs -n monitoring <pod-name> --previous

# 설정 확인
kubectl describe pod -n monitoring <pod-name>

# ConfigMap 검증
kubectl get configmap -n monitoring -o yaml
```

### 리소스 부족

```bash
# 노드 리소스 확인
kubectl top nodes

# Pod 리소스 사용량
kubectl top pods -n monitoring

# 리소스 제한 조정 (values-production.yaml)
prometheus:
  resources:
    requests:
      cpu: "500m"      # 낮춤
      memory: "2Gi"    # 낮춤
```

## 추가 설정

### Ingress 설정 (외부 접근)

```yaml
# values-production.yaml에 추가
ingress:
  enabled: true
  className: "nginx"
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
  
  grafana:
    host: "grafana.example.com"
    tls:
      enabled: true
      secretName: "grafana-tls"
  
  prometheus:
    host: "prometheus.example.com"
    tls:
      enabled: true
      secretName: "prometheus-tls"
```

Ingress 리소스 생성:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana
  namespace: monitoring
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - grafana.example.com
      secretName: grafana-tls
  rules:
    - host: grafana.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: grafana
                port:
                  number: 3000
```

### ServiceMonitor 설정 (Prometheus Operator 사용 시)

```yaml
serviceMonitor:
  enabled: true
  interval: 30s
  scrapeTimeout: 10s
```

## 참고 자료

- [Helm 공식 문서](https://helm.sh/docs/)
- [Argo CD 공식 문서](https://argo-cd.readthedocs.io/)
- [Kubernetes Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)

