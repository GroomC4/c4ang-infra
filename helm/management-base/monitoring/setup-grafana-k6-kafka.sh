#!/bin/bash
# Grafana + K6 + Kafka 메트릭 통합 설정 스크립트

set -euo pipefail

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 로그 함수
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

error_exit() {
    log_error "$1"
    exit 1
}

# 현재 디렉토리 확인
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || error_exit "스크립트 디렉토리로 이동할 수 없습니다"

MONITORING_NS="monitoring"
KAFKA_NS="kafka"

echo ""
log_info "=========================================="
log_info "Grafana + K6 + Kafka 메트릭 설정 시작"
log_info "=========================================="
echo ""

# 1. 사전 체크
log_info "[1/5] 사전 요구사항 확인 중..."
command -v kubectl &> /dev/null || error_exit "kubectl이 설치되어 있지 않습니다."
command -v helm &> /dev/null || error_exit "helm이 설치되어 있지 않습니다."
kubectl cluster-info &> /dev/null || error_exit "Kubernetes 클러스터에 연결할 수 없습니다."
log_success "사전 요구사항 확인 완료"

# 2. Grafana 배포
echo ""
log_info "[2/5] Grafana 배포 중..."

# 네임스페이스 확인
if ! kubectl get namespace "$MONITORING_NS" &>/dev/null; then
    log_info "monitoring 네임스페이스 생성 중..."
    kubectl create namespace "$MONITORING_NS"
fi

# Helm 차트 설치 확인
if helm list -n "$MONITORING_NS" | grep -q "monitoring"; then
    log_warning "모니터링 스택이 이미 설치되어 있습니다."
    read -p "업그레이드하시겠습니까? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        helm upgrade monitoring . -n "$MONITORING_NS" || log_warning "업그레이드 실패"
    else
        log_info "기존 설치를 유지합니다."
    fi
else
    log_info "모니터링 스택 설치 중..."
    helm install monitoring . -n "$MONITORING_NS" || error_exit "모니터링 스택 설치 실패"
fi

# Grafana Pod 대기
log_info "Grafana Pod 준비 대기 중..."
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/component=grafana \
  -n "$MONITORING_NS" \
  --timeout=300s || log_warning "Grafana Pod 준비 시간 초과"

log_success "Grafana 배포 완료"

# 3. Kafka Exporter 배포
echo ""
log_info "[3/5] Kafka Exporter 배포 중..."

# Kafka Exporter가 이미 있는지 확인
if kubectl get deployment kafka-exporter -n "$KAFKA_NS" &>/dev/null; then
    log_warning "Kafka Exporter가 이미 배포되어 있습니다."
else
    log_info "Kafka Exporter 배포 중..."
    
    cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kafka-exporter
  namespace: ${KAFKA_NS}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: kafka-exporter
  template:
    metadata:
      labels:
        app: kafka-exporter
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "9308"
    spec:
      containers:
      - name: kafka-exporter
        image: danielqsj/kafka-exporter:latest
        ports:
        - containerPort: 9308
          name: metrics
        env:
        - name: KAFKA_BROKERS
          value: "c4-kafka-kafka-bootstrap.${KAFKA_NS}:9092"
        - name: LOG_LEVEL
          value: "info"
        resources:
          requests:
            cpu: "100m"
            memory: "128Mi"
          limits:
            cpu: "200m"
            memory: "256Mi"
---
apiVersion: v1
kind: Service
metadata:
  name: kafka-exporter
  namespace: ${KAFKA_NS}
  labels:
    app: kafka-exporter
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "9308"
spec:
  ports:
  - port: 9308
    targetPort: 9308
    name: metrics
  selector:
    app: kafka-exporter
EOF

    log_success "Kafka Exporter 배포 완료"
    
    # Kafka Exporter Pod 대기
    log_info "Kafka Exporter Pod 준비 대기 중..."
    kubectl wait --for=condition=ready pod \
      -l app=kafka-exporter \
      -n "$KAFKA_NS" \
      --timeout=300s || log_warning "Kafka Exporter Pod 준비 시간 초과"
fi

# 4. Prometheus에 Kafka Exporter 추가
echo ""
log_info "[4/5] Prometheus에 Kafka Exporter 스크랩 설정 추가 중..."

# Prometheus ConfigMap 백업
kubectl get configmap prometheus-config -n "$MONITORING_NS" -o yaml > /tmp/prometheus-config-backup.yaml

# 현재 설정 확인
CURRENT_CONFIG=$(kubectl get configmap prometheus-config -n "$MONITORING_NS" -o jsonpath='{.data.prometheus\.yml}')

if echo "$CURRENT_CONFIG" | grep -q "kafka-exporter"; then
    log_warning "Kafka Exporter 스크랩 설정이 이미 있습니다."
else
    log_info "Prometheus ConfigMap 업데이트 중..."
    
    # 임시 파일에 새 설정 작성
    cat > /tmp/prometheus-kafka-scrape.yml <<'EOF'
      # Kafka Exporter
      - job_name: 'kafka-exporter'
        static_configs:
          - targets: ['kafka-exporter.kafka:9308']
            labels:
              job: kafka-exporter
              namespace: kafka
EOF

    # ConfigMap 업데이트 (간단한 방법: kubectl patch 사용)
    log_warning "Prometheus ConfigMap을 수동으로 업데이트해야 합니다."
    log_info "다음 내용을 prometheus.yml의 scrape_configs 섹션에 추가하세요:"
    echo ""
    cat /tmp/prometheus-kafka-scrape.yml
    echo ""
    log_info "또는 다음 명령어로 수동 편집:"
    echo "  kubectl edit configmap prometheus-config -n $MONITORING_NS"
fi

# 5. Kafka 대시보드 안내
echo ""
log_info "[5/5] Kafka 대시보드 설정 안내"
log_info "=========================================="
echo ""
log_info "Grafana에 Kafka 대시보드를 추가하는 방법:"
echo ""
echo "1. Grafana 접속:"
echo "   kubectl port-forward -n $MONITORING_NS svc/grafana 3000:3000"
echo "   브라우저에서 http://localhost:3000 접속"
echo "   Username: admin"
echo "   Password: admin"
echo ""
echo "2. 대시보드 Import:"
echo "   - + → Import"
echo "   - 대시보드 ID 입력: 721 (Kafka Exporter) 또는 758 (Kafka Overview)"
echo "   - Load → Prometheus 데이터소스 선택 → Import"
echo ""
echo "3. 또는 대시보드 JSON 파일 사용:"
echo "   - Grafana 공식 사이트에서 Kafka 대시보드 다운로드"
echo "   - Import → Upload JSON file"
echo ""

# 완료 요약
echo ""
log_info "=========================================="
log_success "설정 완료!"
log_info "=========================================="
echo ""
log_info "다음 단계:"
echo ""
echo "1. Grafana 접속:"
echo "   kubectl port-forward -n $MONITORING_NS svc/grafana 3000:3000"
echo ""
echo "2. Prometheus에서 Kafka 메트릭 확인:"
echo "   kubectl port-forward -n $MONITORING_NS svc/prometheus 9090:9090"
echo "   브라우저에서 http://localhost:9090 접속"
echo "   PromQL: kafka_topic_partitions"
echo ""
echo "3. Kafka Exporter 메트릭 확인:"
echo "   kubectl port-forward -n $KAFKA_NS svc/kafka-exporter 9308:9308"
echo "   curl http://localhost:9308/metrics | grep kafka"
echo ""
echo "4. K6 테스트 실행:"
echo "   cd /Users/sanga/Desktop/c4/code/c4ang-infra/performance-tests"
echo "   k6 run --cloud tests/load/product-service.js"
echo ""

