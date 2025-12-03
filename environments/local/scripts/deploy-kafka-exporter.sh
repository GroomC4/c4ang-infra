#!/bin/bash
set -e

# 환경 변수 설정
NAMESPACE="${NAMESPACE:-kafka}"
KAFKA_BOOTSTRAP="${KAFKA_BOOTSTRAP:-c4-kafka-kafka-bootstrap.kafka:9092}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_DIR="$(dirname "${SCRIPT_DIR}")"
KUBECONFIG_FILE="${ENV_DIR}/kubeconfig/config"

echo "📊 Kafka Exporter 배포 스크립트"
echo "=================================="
echo "네임스페이스: ${NAMESPACE}"
echo "Kafka Bootstrap: ${KAFKA_BOOTSTRAP}"
echo ""

# kubeconfig 확인
if [ ! -f "${KUBECONFIG_FILE}" ]; then
    echo "❌ kubeconfig 파일을 찾을 수 없습니다: ${KUBECONFIG_FILE}"
    exit 1
fi

export KUBECONFIG="${KUBECONFIG_FILE}"

# 클러스터 연결 확인
if ! kubectl cluster-info &> /dev/null; then
    echo "❌ 클러스터에 연결할 수 없습니다."
    exit 1
fi

# 네임스페이스 확인
if ! kubectl get namespace "${NAMESPACE}" &> /dev/null; then
    echo "❌ 네임스페이스 '${NAMESPACE}'가 존재하지 않습니다."
    exit 1
fi

# Kafka Exporter 배포
echo "🚀 Kafka Exporter 배포 중..."
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kafka-exporter
  namespace: ${NAMESPACE}
  labels:
    app: kafka-exporter
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
          value: "${KAFKA_BOOTSTRAP}"
        - name: LOG_LEVEL
          value: "info"
        - name: KAFKA_VERSION
          value: "2.0.0"
        - name: GODEBUG
          value: "netdns=go"
        args:
        # 내부 서비스 이름 + 포트 9095 사용 (backplane 리스너)
        # Kafka Exporter는 여러 서버를 각각 별도의 --kafka.server 인자로 받아야 함
        # 이제 Exporter는 내부 DNS 주소 + 9095 포트를 사용하므로
        # 브로커가 반환하는 내부 메타데이터와 일치하게 됩니다.
        - --kafka.server=c4-kafka-dual-role-0.c4-kafka-kafka-brokers.kafka.svc.cluster.local:9095
        - --kafka.server=c4-kafka-dual-role-1.c4-kafka-kafka-brokers.kafka.svc.cluster.local:9095
        - --kafka.server=c4-kafka-dual-role-2.c4-kafka-kafka-brokers.kafka.svc.cluster.local:9095
        - --log.level=info
        - --web.listen-address=:9308
        - --topic.filter=.*
        - --group.filter=.*
        resources:
          requests:
            cpu: "100m"
            memory: "128Mi"
          limits:
            cpu: "200m"
            memory: "256Mi"
        livenessProbe:
          httpGet:
            path: /metrics
            port: 9308
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /metrics
            port: 9308
          initialDelaySeconds: 10
          periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: kafka-exporter
  namespace: ${NAMESPACE}
  labels:
    app: kafka-exporter
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "9308"
spec:
  ports:
  - port: 9308
    targetPort: 9308
    protocol: TCP
    name: metrics
  selector:
    app: kafka-exporter
  type: ClusterIP
EOF

echo "⏳ Kafka Exporter가 준비될 때까지 대기 중..."
kubectl wait --for=condition=available --timeout=120s deployment/kafka-exporter -n "${NAMESPACE}" || {
    echo "⚠️  Kafka Exporter 대기 시간 초과"
}

# 배포 상태 확인
echo ""
echo "📊 Kafka Exporter 배포 상태 확인 중..."
echo "=================================="
kubectl get pods -n "${NAMESPACE}" -l app=kafka-exporter
kubectl get svc -n "${NAMESPACE}" -l app=kafka-exporter
echo ""

echo "✅ Kafka Exporter 배포 완료!"
echo ""
echo "메트릭 확인:"
echo "  kubectl port-forward -n ${NAMESPACE} svc/kafka-exporter 9308:9308"
echo "  curl http://localhost:9308/metrics"
echo ""

