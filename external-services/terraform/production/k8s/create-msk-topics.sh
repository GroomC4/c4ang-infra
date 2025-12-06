#!/bin/bash
# MSK 토픽 생성 스크립트
# 사용법: ./create-msk-topics.sh <MSK_BOOTSTRAP_BROKERS>

set -e

MSK_BOOTSTRAP_BROKERS="${1:-}"
KAFKA_CLIENT_POD="kafka-client"
KAFKA_NAMESPACE="kafka"

if [ -z "$MSK_BOOTSTRAP_BROKERS" ]; then
    echo "❌ 사용법: $0 <MSK_BOOTSTRAP_BROKERS>"
    echo "예시: $0 b-1.c4-dev-kafka.xxxxx.c2.kafka.ap-northeast-2.amazonaws.com:9092,b-2.c4-dev-kafka.xxxxx.c2.kafka.ap-northeast-2.amazonaws.com:9092"
    exit 1
fi

echo "🚀 MSK 토픽 생성 시작"
echo "MSK Bootstrap Brokers: $MSK_BOOTSTRAP_BROKERS"
echo ""

# kafka-client Pod 확인
if ! kubectl get pod -n "$KAFKA_NAMESPACE" "$KAFKA_CLIENT_POD" &>/dev/null; then
    echo "❌ kafka-client Pod를 찾을 수 없습니다: $KAFKA_CLIENT_POD"
    echo "먼저 kafka-client를 배포하세요:"
    echo "  kubectl apply -f k8s/msk-kafka-client.yaml"
    exit 1
fi

# 토픽 정의 (kafka-topics/values.yaml 기반)
TOPICS=(
    # ORDER
    "order.created:3:2"
    "order.canceled:3:2"
    "order.updated:3:2"
    "order.retry:1:2"
    "order.dlq:1:2"
    
    # PAYMENT
    "payment.completed:3:2"
    "payment.failed:3:2"
    "payment.refunded:3:2"
    "payment.retry:1:2"
    "payment.dlq:1:2"
    
    # REVIEW
    "review.created:3:2"
    "review.updated:3:2"
    "review.deleted:3:2"
    "review.retry:1:2"
    "review.dlq:1:2"
    
    # STORE
    "store.created:3:2"
    "store.updated:3:2"
    "store.deleted:3:2"
    "store.retry:1:2"
    "store.dlq:1:2"
    
    # USER
    "user.created:3:2"
    "user.updated:3:2"
    "user.deleted:3:2"
    "user.retry:1:2"
    "user.dlq:1:2"
    
    # SAGA
    "saga.order-creation.failed:1:2"
    "saga.stock-reservation.failed:1:2"
    "saga.order-confirmation.failed:1:2"
    
    # 테스트용
    "test-topic:3:2"
)

# 토픽 생성 함수
create_topic() {
    local topic_config="$1"
    local topic_name=$(echo "$topic_config" | cut -d: -f1)
    local partitions=$(echo "$topic_config" | cut -d: -f2)
    local replication_factor=$(echo "$topic_config" | cut -d: -f3)
    
    echo "📝 토픽 생성: $topic_name (파티션: $partitions, 복제: $replication_factor)"
    
    kubectl exec -n "$KAFKA_NAMESPACE" "$KAFKA_CLIENT_POD" -- \
        /opt/kafka/bin/kafka-topics.sh \
        --bootstrap-server "$MSK_BOOTSTRAP_BROKERS" \
        --create \
        --topic "$topic_name" \
        --partitions "$partitions" \
        --replication-factor "$replication_factor" \
        --if-not-exists \
        2>&1 | grep -v "already exists" || true
}

# 모든 토픽 생성
for topic_config in "${TOPICS[@]}"; do
    create_topic "$topic_config"
done

echo ""
echo "✅ 토픽 생성 완료"
echo ""
echo "📋 생성된 토픽 확인:"
kubectl exec -n "$KAFKA_NAMESPACE" "$KAFKA_CLIENT_POD" -- \
    /opt/kafka/bin/kafka-topics.sh \
    --bootstrap-server "$MSK_BOOTSTRAP_BROKERS" \
    --list

