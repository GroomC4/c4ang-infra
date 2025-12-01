#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
KUBECONFIG_FILE="${ENV_DIR}/kubeconfig/config"

# 환경 변수 설정
export KUBECONFIG="${KUBECONFIG_FILE}"

# Kafka Bootstrap 서버 설정
# 로컬에서 실행 시 포트 포워딩 필요
# 브로커의 advertised.listeners가 localhost이므로 모든 브로커를 bootstrap 서버로 사용
# 각 브로커 Pod에 포트 포워딩이 설정되어 있으므로 localhost로 연결 가능
KAFKA_PORT_FORWARD_PORT="${KAFKA_PORT_FORWARD_PORT:-9092}"
# 모든 브로커를 bootstrap 서버로 사용 (포트 포워딩을 통해 연결)
KAFKA_BOOTSTRAP_SERVERS="${KAFKA_BOOTSTRAP_SERVERS:-localhost:${KAFKA_PORT_FORWARD_PORT},localhost:$((KAFKA_PORT_FORWARD_PORT + 1)),localhost:$((KAFKA_PORT_FORWARD_PORT + 2))}"

# 포트 포워딩이 실행 중인지 확인
if ! lsof -Pi :${KAFKA_PORT_FORWARD_PORT} -sTCP:LISTEN -t >/dev/null 2>&1; then
    echo "⚠️  Warning: Kafka 포트 포워딩이 실행 중이지 않습니다."
    echo "   다음 명령어로 포트 포워딩을 시작하세요:"
    echo "   kubectl port-forward -n kafka svc/c4-kafka-kafka-bootstrap ${KAFKA_PORT_FORWARD_PORT}:9092"
    echo ""
    echo "   또는 백그라운드로 실행:"
    echo "   kubectl port-forward -n kafka svc/c4-kafka-kafka-bootstrap ${KAFKA_PORT_FORWARD_PORT}:9092 > /tmp/kafka-port-forward.log 2>&1 &"
    echo ""
    read -p "포트 포워딩을 지금 시작하시겠습니까? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        kubectl port-forward -n kafka svc/c4-kafka-kafka-bootstrap ${KAFKA_PORT_FORWARD_PORT}:9092 > /tmp/kafka-port-forward.log 2>&1 &
        KAFKA_PF_PID=$!
        echo "✅ 포트 포워딩 시작됨 (PID: $KAFKA_PF_PID)"
        echo "   종료하려면: kill $KAFKA_PF_PID"
        sleep 2
    else
        echo "❌ 포트 포워딩이 필요합니다. 종료합니다."
        exit 1
    fi
fi

export KAFKA_BOOTSTRAP_SERVERS
export KAFKA_TOPIC="${KAFKA_TOPIC:-broker-failure-test}"
export CONSUMER_GROUP_ID="${CONSUMER_GROUP_ID:-broker-failure-test-group}"
export REPORT_INTERVAL_SEC="${REPORT_INTERVAL_SEC:-5}"

echo "=========================================="
echo "Kafka Test Consumer"
echo "=========================================="
echo "Bootstrap Servers: $KAFKA_BOOTSTRAP_SERVERS"
echo "Topic: $KAFKA_TOPIC"
echo "Consumer Group: $CONSUMER_GROUP_ID"
echo "Report Interval: ${REPORT_INTERVAL_SEC}s"
echo "=========================================="
echo ""

# Kafka 연결 확인 (선택사항, 실패해도 계속 진행)
echo "Checking Kafka connectivity..."
if kubectl exec -n kafka $(kubectl get pods -n kafka -l strimzi.io/cluster=c4-kafka -o jsonpath='{.items[0].metadata.name}' 2>/dev/null) -- \
    kafka-broker-api-versions --bootstrap-server localhost:9092 > /dev/null 2>&1; then
    echo "✅ Kafka is accessible"
else
    echo "⚠️  Warning: Cannot verify Kafka connectivity directly (continuing anyway...)"
fi

# 토픽 존재 확인 (선택사항, 실패해도 계속 진행)
if kubectl get kafkatopic "$KAFKA_TOPIC" -n kafka > /dev/null 2>&1; then
    echo "✅ Topic '$KAFKA_TOPIC' exists"
else
    echo "⚠️  Warning: Topic '$KAFKA_TOPIC' not found via kubectl (may exist, continuing anyway...)"
    echo "   Consumer will try to connect directly to Kafka"
fi

echo ""
echo "Starting consumer..."
echo "Press Ctrl+C to stop"
echo ""

# Python 스크립트 실행
cd "$SCRIPT_DIR"

SCRIPT_FILE="${SCRIPT_DIR}/kafka-test-consumer.py"
VENV_DIR="${SCRIPT_DIR}/.venv"

# Python 실행
if command -v python3 &> /dev/null; then
    # 가상환경 생성 및 활성화
    if [ ! -d "$VENV_DIR" ]; then
        echo "📦 Python 가상환경 생성 중..."
        python3 -m venv "$VENV_DIR"
    fi
    
    # 가상환경 활성화
    source "${VENV_DIR}/bin/activate"
    
    # kafka-python 설치 확인 및 설치
    if ! python3 -c "import kafka" 2>/dev/null; then
        echo "📥 kafka-python 설치 중..."
        pip install kafka-python --quiet || {
            echo "❌ 설치 실패"
            exit 1
        }
    fi
    
    # 스크립트 실행
    python3 "$SCRIPT_FILE"
else
    echo "❌ Error: python3가 설치되어 있지 않습니다."
    exit 1
fi
