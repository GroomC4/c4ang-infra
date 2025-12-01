#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
KUBECONFIG_FILE="${ENV_DIR}/kubeconfig/config"

export KUBECONFIG="${KUBECONFIG_FILE}"
KAFKA_PORT="${KAFKA_PORT:-9092}"

echo "=== Kafka 포트 포워딩 시작 ==="
echo "각 브로커 Pod에 직접 포트 포워딩 설정"
echo "  - 브로커 0: localhost:${KAFKA_PORT} -> c4-kafka-dual-role-0:9092"
echo "  - 브로커 1: localhost:$((KAFKA_PORT + 1)) -> c4-kafka-dual-role-1:9092"
echo "  - 브로커 2: localhost:$((KAFKA_PORT + 2)) -> c4-kafka-dual-role-2:9092"
echo ""
echo "⚠️  참고: 브로커는 localhost로 advertised되지만,"
echo "   포트 포워딩을 통해 각 브로커 Pod에 연결됩니다."
echo ""

# 기존 포트 포워딩 프로세스 확인 및 종료
for port in ${KAFKA_PORT} $((KAFKA_PORT + 1)) $((KAFKA_PORT + 2)); do
    EXISTING_PID=$(lsof -ti :${port} 2>/dev/null || true)
    if [ -n "$EXISTING_PID" ]; then
        echo "⚠️  기존 포트 포워딩 프로세스 발견 (포트: ${port}, PID: $EXISTING_PID)"
        echo "   종료 중..."
        kill $EXISTING_PID 2>/dev/null || true
    fi
done
sleep 2
echo "✅ 기존 프로세스 정리 완료"
echo ""

# 각 브로커에 포트 포워딩 설정 (백그라운드)
echo "🚀 브로커 포트 포워딩 시작..."
kubectl port-forward -n kafka pod/c4-kafka-dual-role-0 ${KAFKA_PORT}:9092 > /tmp/kafka-broker-0-port-forward.log 2>&1 &
PF_PID_0=$!
echo "  브로커 0: PID $PF_PID_0"

kubectl port-forward -n kafka pod/c4-kafka-dual-role-1 $((KAFKA_PORT + 1)):9092 > /tmp/kafka-broker-1-port-forward.log 2>&1 &
PF_PID_1=$!
echo "  브로커 1: PID $PF_PID_1"

kubectl port-forward -n kafka pod/c4-kafka-dual-role-2 $((KAFKA_PORT + 2)):9092 > /tmp/kafka-broker-2-port-forward.log 2>&1 &
PF_PID_2=$!
echo "  브로커 2: PID $PF_PID_2"

echo ""
echo "✅ 모든 브로커 포트 포워딩 시작됨"
echo ""
echo "종료하려면 Ctrl+C를 누르세요"
echo ""

# 종료 시 모든 포트 포워딩 프로세스 종료
trap "echo ''; echo '🛑 포트 포워딩 종료 중...'; kill $PF_PID_0 $PF_PID_1 $PF_PID_2 2>/dev/null || true; exit" INT TERM

# 대기
wait

