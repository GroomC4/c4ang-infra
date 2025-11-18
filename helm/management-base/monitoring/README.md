# Kubernetes 관측성 스택 (Grafana Stack)

Kubernetes 클러스터를 위한 통합 관측성 솔루션입니다. 메트릭, 로그, 트레이스를 수집하고 시각화하여 실시간 모니터링과 장애 조기 탐지를 제공합니다.

## 📋 목차

- [아키텍처 개요](#아키텍처-개요)
- [주요 컴포넌트](#주요-컴포넌트)
- [사전 요구사항](#사전-요구사항)
- [설치 방법](#설치-방법)
- [설정 가이드](#설정-가이드)
- [사용 방법](#사용-방법)
- [운영 가이드](#운영-가이드)
- [문제 해결](#문제-해결)

## 🏗️ 아키텍처 개요

```
┌─────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                        │
│                                                               │
│  ┌───────────────┐                                           │
│  │ Grafana Alloy │ (DaemonSet)                              │
│  │   Agent       │ ← 메트릭/로그/트레이스 수집               │
│  └───────┬───────┘                                           │
│          │                                                    │
│          ├─────────────┬──────────────┬──────────────┐      │
│          ▼             ▼              ▼              ▼       │
│   ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  │
│   │Prometheus│  │   Loki   │  │  Tempo   │  │ Grafana  │  │
│   │(메트릭)  │  │  (로그)  │  │(트레이스)│  │(시각화)  │  │
│   └──────────┘  └──────────┘  └──────────┘  └────┬─────┘  │
│                                                     │         │
└─────────────────────────────────────────────────────┼────────┘
                                                      │
                                           ┌──────────▼─────────┐
                                           │  대시보드 & 알림   │
                                           └────────────────────┘
```

## 🔧 주요 컴포넌트

### 1. Grafana Alloy (에이전트)
- **역할**: 메트릭, 로그, 트레이스 통합 수집
- **배치**: DaemonSet으로 모든 노드에 배포
- **기능**:
  - Kubernetes 컨테이너 로그 수집
  - 노드/파드 메트릭 수집
  - OTLP(OpenTelemetry) 트레이스 수신

### 2. Prometheus (메트릭 저장소)
- **역할**: 시계열 메트릭 저장 및 쿼리
- **보존 기간**: 30일 (설정 가능)
- **기능**:
  - Kubernetes 클러스터 메트릭
  - 애플리케이션 메트릭
  - 알림 규칙 실행

### 3. Loki (로그 저장소)
- **역할**: 로그 집계 및 검색
- **보존 기간**: 90일 (설정 가능)
- **기능**:
  - 효율적인 로그 인덱싱
  - 레이블 기반 검색
  - LogQL 쿼리 언어

### 4. Tempo (트레이스 저장소)
- **역할**: 분산 트레이싱
- **보존 기간**: 30일 (설정 가능)
- **기능**:
  - OTLP 수신
  - 트레이스 ID 검색
  - 서비스 맵 생성

### 5. Grafana (시각화)
- **역할**: 통합 대시보드 및 알림
- **기능**:
  - 메트릭/로그/트레이스 통합 뷰
  - 사전 구성된 대시보드
  - 알림 관리

## 📦 사전 요구사항

- **Kubernetes**: v1.24 이상
- **Helm**: v3.8 이상
- **스토리지**: 
  - Prometheus: 50GB (기본값)
  - Loki: 20GB (기본값)
  - Tempo: 20GB (기본값)
  - Grafana: 5GB (기본값)
- **리소스**:
  - 최소 4GB RAM, 2 CPU per node
  - 네임스페이스: `monitoring`

## 🚀 설치 방법

### 1. 기본 설치

```bash
# 1. Helm 차트 설치
cd helm/management-base/monitoring
helm install monitoring . -n monitoring --create-namespace

# 2. 설치 확인
kubectl get pods -n monitoring

# 예상 출력:
# NAME                          READY   STATUS    RESTARTS   AGE
# alloy-xxxxx                   1/1     Running   0          2m
# prometheus-xxxxx              1/1     Running   0          2m
# loki-xxxxx                    1/1     Running   0          2m
# tempo-xxxxx                   1/1     Running   0          2m
# grafana-xxxxx                 1/1     Running   0          2m
```

### 2. 커스텀 values 파일로 설치

```bash
# values-custom.yaml 생성
cat > values-custom.yaml <<EOF
namespace: monitoring

# Prometheus 스토리지 증설
prometheus:
  storage:
    size: 100Gi

# Grafana 관리자 비밀번호 변경
grafana:
  admin:
    password: "MySecurePassword123!"

# 알림 활성화
alerting:
  enabled: true
  slack:
    enabled: true
    webhookUrl: "https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
    channel: "#alerts"
EOF

# 설치
helm install monitoring . -n monitoring --create-namespace -f values-custom.yaml
```

### 3. Argo CD를 통한 GitOps 배포

`argocd-application.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: monitoring
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/c4ang-infra
    targetRevision: main
    path: helm/management-base/monitoring
    helm:
      valueFiles:
        - values.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: monitoring
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

적용:

```bash
kubectl apply -f argocd-application.yaml
```

## ⚙️ 설정 가이드

### 애플리케이션 메트릭 수집 설정

애플리케이션에서 Prometheus 메트릭을 노출하려면, Pod에 다음 어노테이션을 추가하세요:

```yaml
apiVersion: v1
kind: Pod
metadata:
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "8080"
    prometheus.io/path: "/metrics"
spec:
  containers:
    - name: app
      image: myapp:latest
```

### 트레이스 전송 설정

애플리케이션에서 OTLP로 트레이스를 전송:

**환경변수 설정**:
```yaml
env:
  - name: OTEL_EXPORTER_OTLP_ENDPOINT
    value: "http://alloy.monitoring.svc.cluster.local:4318"
  - name: OTEL_SERVICE_NAME
    value: "my-service"
```

**Go 예시**:
```go
import "go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"

exporter, _ := otlptracehttp.New(
    context.Background(),
    otlptracehttp.WithEndpoint("alloy.monitoring.svc.cluster.local:4318"),
    otlptracehttp.WithInsecure(),
)
```

### 스토리지 클래스 지정

특정 스토리지 클래스를 사용하려면:

```yaml
prometheus:
  storage:
    size: 100Gi
    storageClassName: "gp3"  # AWS EBS gp3

loki:
  storage:
    size: 50Gi
    storageClassName: "gp3"
```

### ECR 이미지 풀 시크릿 설정

프라이빗 ECR을 사용하는 경우:

```yaml
imagePullSecrets:
  - name: ecr-creds
```

시크릿 생성:
```bash
kubectl create secret docker-registry ecr-creds \
  --docker-server=123456789012.dkr.ecr.ap-northeast-2.amazonaws.com \
  --docker-username=AWS \
  --docker-password=$(aws ecr get-login-password --region ap-northeast-2) \
  -n monitoring
```

## 📊 사용 방법

### Grafana 접속

```bash
# 포트 포워딩
kubectl port-forward -n monitoring svc/grafana 3000:3000

# 브라우저에서 접속: http://localhost:3000
# 기본 계정: admin / admin
```

### Prometheus 쿼리 예시

Grafana Explore에서 Prometheus 데이터소스를 선택하고:

```promql
# CPU 사용률
rate(container_cpu_usage_seconds_total[5m])

# 메모리 사용량
container_memory_usage_bytes

# HTTP 요청 비율
rate(http_requests_total[5m])

# 에러율
sum(rate(http_requests_total{status=~"5.."}[5m])) / sum(rate(http_requests_total[5m]))
```

### Loki 로그 쿼리 예시

Grafana Explore에서 Loki 데이터소스를 선택하고:

```logql
# 특정 네임스페이스 로그
{namespace="default"}

# 에러 로그 필터링
{namespace="default"} |= "error"

# 파드별 로그 스트림
{pod="my-app-xxxxx"}

# 로그 비율 계산
rate({namespace="default"} |= "error" [5m])
```

### Tempo 트레이스 검색

1. Grafana Explore > Tempo 선택
2. Search 탭에서:
   - Service Name 선택
   - Duration 범위 설정
   - 트레이스 검색
3. 트레이스 클릭하여 상세 스팬 확인

## 🛠️ 운영 가이드

### 대시보드 추가

추천 대시보드 ID (grafana.com):

- **Kubernetes Cluster**: 7249
- **Node Exporter**: 1860
- **Pod Monitoring**: 6417
- **Loki Logs**: 13639

임포트 방법:
1. Grafana UI > Dashboards > Import
2. 대시보드 ID 입력
3. Prometheus/Loki 데이터소스 선택

### 알림 규칙 추가

`values.yaml`에서:

```yaml
alerting:
  enabled: true
  rules:
    - name: HighMemoryUsage
      enabled: true
      expr: 'container_memory_usage_bytes{namespace="default"} > 1e9'
      duration: 5m
      severity: warning
      summary: "High memory usage detected"
      description: "Container {{ $labels.pod }} is using more than 1GB memory"
```

### 백업 전략

**1. Prometheus 데이터 백업**:
```bash
# 스냅샷 생성
kubectl exec -n monitoring prometheus-xxxxx -- \
  curl -XPOST http://localhost:9090/api/v1/admin/tsdb/snapshot

# PVC 백업 (Velero 사용 시)
velero backup create monitoring-prometheus \
  --include-namespaces monitoring \
  --include-resources pvc,pv
```

**2. Grafana 대시보드 백업**:
```bash
# 대시보드 내보내기
kubectl exec -n monitoring grafana-xxxxx -- \
  grafana-cli admin export-dashboards --homepath=/usr/share/grafana
```

### 리소스 확장

부하가 증가하면 리소스를 조정하세요:

```yaml
prometheus:
  replicas: 2  # 고가용성
  resources:
    requests:
      cpu: "1000m"
      memory: "4Gi"
    limits:
      cpu: "2000m"
      memory: "8Gi"

loki:
  replicas: 2
  resources:
    requests:
      cpu: "1000m"
      memory: "2Gi"
```

### 로그 보존 정책 조정

```yaml
loki:
  retention:
    enabled: true
    period: 180d  # 180일 보존

prometheus:
  retention:
    time: 90d  # 90일 보존
    size: 100GB
```

## 🔍 문제 해결

### Pod가 시작되지 않음

```bash
# Pod 상태 확인
kubectl get pods -n monitoring

# 로그 확인
kubectl logs -n monitoring <pod-name>

# 이벤트 확인
kubectl describe pod -n monitoring <pod-name>
```

**일반적인 문제**:

1. **PVC Pending**:
   ```bash
   # 스토리지 클래스 확인
   kubectl get storageclass
   
   # 기본 스토리지 클래스 설정
   kubectl patch storageclass <storage-class-name> \
     -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
   ```

2. **이미지 풀 에러**:
   ```bash
   # ImagePullSecrets 확인
   kubectl get secret -n monitoring
   
   # ECR 토큰 갱신
   kubectl delete secret ecr-creds -n monitoring
   kubectl create secret docker-registry ecr-creds \
     --docker-server=<ecr-url> \
     --docker-username=AWS \
     --docker-password=$(aws ecr get-login-password --region ap-northeast-2) \
     -n monitoring
   ```

3. **권한 에러**:
   ```bash
   # RBAC 확인
   kubectl get clusterrole,clusterrolebinding -n monitoring | grep monitoring
   
   # ServiceAccount 확인
   kubectl get sa -n monitoring
   ```

### 메트릭이 수집되지 않음

```bash
# Alloy 로그 확인
kubectl logs -n monitoring -l app.kubernetes.io/component=alloy

# Prometheus targets 확인
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# 브라우저: http://localhost:9090/targets

# Pod 어노테이션 확인
kubectl get pod <pod-name> -o jsonpath='{.metadata.annotations}'
```

### 로그가 보이지 않음

```bash
# Alloy가 로그를 수집하는지 확인
kubectl logs -n monitoring -l app.kubernetes.io/component=alloy | grep loki

# Loki 상태 확인
kubectl port-forward -n monitoring svc/loki 3100:3100
curl http://localhost:3100/ready

# 레이블 확인
curl http://localhost:3100/loki/api/v1/labels
```

### Grafana 대시보드가 비어있음

```bash
# 데이터소스 연결 확인
kubectl exec -n monitoring <grafana-pod> -- \
  curl http://localhost:3000/api/datasources

# ConfigMap 확인
kubectl get configmap -n monitoring grafana-datasources -o yaml
```

### 디스크 공간 부족

```bash
# PVC 사용량 확인
kubectl exec -n monitoring <prometheus-pod> -- df -h

# PVC 확장 (스토리지 클래스가 지원하는 경우)
kubectl patch pvc prometheus-storage -n monitoring \
  -p '{"spec":{"resources":{"requests":{"storage":"100Gi"}}}}'
```

## 📈 성능 최적화

### 1. 샘플링 조정

트래픽이 많은 경우 샘플링 비율을 낮추세요:

```yaml
tempo:
  sampling:
    rate: 0.01  # 1%만 샘플링
```

### 2. 로그 필터링

불필요한 로그 수집을 방지:

```yaml
alloy:
  config:
    logs:
      excludeNamespaces:
        - kube-system
        - kube-public
```

### 3. 메트릭 스크랩 간격 조정

```yaml
alloy:
  config:
    metrics:
      scrapeInterval: 60s  # 기본 30s에서 증가
```

## 📚 추가 리소스

- [Grafana 공식 문서](https://grafana.com/docs/)
- [Prometheus 문서](https://prometheus.io/docs/)
- [Loki 문서](https://grafana.com/docs/loki/)
- [Tempo 문서](https://grafana.com/docs/tempo/)
- [Grafana Alloy 문서](https://grafana.com/docs/alloy/)

## 🤝 기여 및 지원

문제가 발생하거나 개선 사항이 있으면 이슈를 생성해주세요.

## 📝 라이선스

이 프로젝트는 MIT 라이선스를 따릅니다.

