# 모니터링 설정 가이드

## 🎯 목표

Step 2 (HPA 스케일링) 및 Step 3 (Karpenter) 테스트를 위해 모니터링 도구를 설정합니다.

---

## 📊 모니터링 옵션

### 옵션 1: 간단한 스크립트 모니터링 (빠른 시작) ⭐ 추천

**장점:**
- 빠른 설정 (설치 불필요)
- 실시간 모니터링
- HPA, Pod 상태, Consumer Lag 모두 확인 가능

**사용법:**

```bash
cd external-services/terraform/production/k8s
chmod +x monitor-hpa.sh
./monitor-hpa.sh
```

**모니터링 항목:**
- HPA 상태 (현재 Replicas, CPU 사용률)
- Pod 상태 (이름, 상태, 재시작 횟수, 노드)
- CPU/Memory 사용률
- Consumer Group Lag
- HPA 이벤트

---

### 옵션 2: CloudWatch Container Insights (AWS EKS)

**장점:**
- AWS 네이티브 통합
- 추가 설치 불필요 (EKS에 기본 제공)
- CloudWatch 대시보드 사용 가능

**설정:**

```bash
# CloudWatch Container Insights 활성화 (이미 활성화되어 있을 수 있음)
aws eks update-cluster-config \
  --name c4-cluster \
  --region ap-northeast-2 \
  --logging '{"enable":["api","audit","authenticator","controllerManager","scheduler"]}'

# CloudWatch 대시보드에서 확인
# AWS Console > CloudWatch > Container Insights > Performance monitoring
```

**확인 방법:**
1. AWS Console > CloudWatch > Container Insights
2. 클러스터 선택 > Namespace: kafka
3. Pod 메트릭 확인

---

### 옵션 3: Prometheus + Grafana (고급)

**장점:**
- 강력한 시각화
- 커스텀 대시보드
- 알림 설정 가능

**설치 (Helm 사용):**

```bash
# Prometheus Operator 설치
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace

# Grafana 접근
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
# 브라우저에서 http://localhost:3000 접속
# 기본 사용자: admin / 비밀번호: prom-operator
```

**대시보드 설정:**
- Kubernetes Pod Monitoring 대시보드 사용
- HPA 메트릭 확인
- Kafka Consumer Lag Exporter 추가 설치 필요

---

## 🚀 빠른 시작 (옵션 1 추천)

### 1. 모니터링 스크립트 실행

```bash
cd external-services/terraform/production/k8s
chmod +x monitor-hpa.sh

# 별도 터미널에서 실행
./monitor-hpa.sh
```

### 2. Step 2 실행

**터미널 1: 모니터링**
```bash
cd external-services/terraform/production/k8s
./monitor-hpa.sh
```

**터미널 2: Consumer + HPA 배포**
```bash
cd external-services/terraform/production/k8s
kubectl apply -f kafka-consumer-hpa.yaml
```

**터미널 3: 부하 생성**
```bash
cd external-services/terraform/production/k8s
kubectl apply -f kafka-producer-load.yaml
kubectl logs -n kafka -l app=kafka-producer-load -f
```

---

## 📈 모니터링 항목

### 1. HPA 상태
- 현재 Replicas 수
- 목표 CPU 사용률 (70%)
- 실제 CPU 사용률
- 최소/최대 Pod 수

### 2. Pod 상태
- Pod 이름 및 상태
- 재시작 횟수
- 실행 중인 노드
- 생성 시간

### 3. 리소스 사용률
- CPU 사용률 (m 단위)
- Memory 사용률 (Mi 단위)
- Pod별 상세 정보

### 4. Consumer Group Lag
- 현재 오프셋
- Lag (처리되지 않은 메시지 수)
- 토픽별 상세 정보

### 5. HPA 이벤트
- 스케일 업/다운 이벤트
- 스케일링 이유
- 타임스탬프

---

## 🔧 고급 모니터링 (선택사항)

### Kafka Consumer Lag Exporter

Kafka Lag을 Prometheus 메트릭으로 노출:

```bash
# Kafka Lag Exporter 설치 (Helm)
helm repo add kafka-lag-exporter https://lightbend.github.io/kafka-lag-exporter
helm install kafka-lag-exporter kafka-lag-exporter/kafka-lag-exporter \
  --namespace kafka \
  --set clusters[0].name=msk \
  --set clusters[0].bootstrapBrokers=<MSK_BOOTSTRAP_BROKERS>
```

### Grafana 대시보드

Prometheus + Grafana 설치 후 다음 대시보드 사용:
- Kubernetes Pod Monitoring (ID: 6417)
- HPA Dashboard (ID: 12239)
- Kafka Exporter Dashboard (ID: 7218)

---

## ✅ 추천 설정

**빠른 테스트:** 옵션 1 (스크립트 모니터링)
- 설치 불필요
- 즉시 사용 가능
- 모든 필수 정보 확인 가능

**프로덕션:** 옵션 2 (CloudWatch) 또는 옵션 3 (Prometheus + Grafana)
- 장기 모니터링
- 알림 설정
- 대시보드 시각화

---

## 📝 참고사항

### Metrics Server 확인

모니터링 스크립트가 작동하려면 Metrics Server가 필요합니다:

```bash
# Metrics Server 설치 확인
kubectl get deployment metrics-server -n kube-system

# 없으면 설치
cd external-services/terraform/production/k8s
./install-metrics-server.sh
```

### 모니터링 스크립트 커스터마이징

`monitor-hpa.sh` 파일을 수정하여 원하는 정보만 표시할 수 있습니다:

```bash
# 특정 정보만 표시
kubectl get hpa -n kafka kafka-consumer-hpa
kubectl get pods -n kafka -l app=kafka-consumer
kubectl top pods -n kafka -l app=kafka-consumer
```

