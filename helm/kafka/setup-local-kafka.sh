#!/usr/bin/env bash
set -euo pipefail

# ===============================
# ENV
# ===============================
CLUSTER_NAME="msa-quality-cluster"
KAFKA_NS="kafka"
STRIMZI_VERSION="0.40.0"
KAFKA_VERSION="4.1.0"
CLIENT_IMAGE="quay.io/strimzi/kafka:latest-kafka-${KAFKA_VERSION}"

echo "✅ Start Local Kafka Setup"


# ===============================
# 0) Docker check
# ===============================
if ! command -v docker &> /dev/null; then
  echo "❌ Docker not installed"
  exit 1
fi

if ! docker info &> /dev/null; then
  echo "❌ Docker daemon not running"
  exit 1
fi


# ===============================
# 1) k3d cluster create
# ===============================
if ! command -v k3d &> /dev/null; then
  echo "⚠️  k3d not found! Install with Homebrew"
  exit 1
fi

EXISTING=$(k3d cluster list | grep -c "${CLUSTER_NAME}" || true)

if [[ $EXISTING -gt 0 ]]; then
  echo "⚠️  k3d cluster exists → skip"
else
  echo "✅ Creating k3d cluster..."
  k3d cluster create "${CLUSTER_NAME}" \
      --api-port 6443 \
      --port "80:80@loadbalancer" \
      --port "443:443@loadbalancer" \
      --k3s-arg "--disable=traefik@server:0"
fi


# ===============================
# 2) create namespace
# ===============================
kubectl create ns "${KAFKA_NS}" || true


# ===============================
# 3) Install Strimzi operator
# ===============================
echo "✅ Installing Strimzi Operator..."
kubectl apply -f https://strimzi.io/install/latest?namespace=${KAFKA_NS} -n ${KAFKA_NS}

echo "⏳ Waiting 10 seconds for operator startup..."
sleep 10


# ===============================
# 4) Apply Kafka Cluster
# ===============================
echo "✅ Applying Kafka Cluster CRDs"

cat <<EOF | kubectl apply -n ${KAFKA_NS} -f -
# ✅ NodePool
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaNodePool
metadata:
  name: kafka-pool
  namespace: ${KAFKA_NS}
  labels:
    strimzi.io/cluster: my-kafka
spec:
  replicas: 1
  roles:
    - controller
    - broker
  storage:
    type: ephemeral
---
# ✅ Kafka Cluster
apiVersion: kafka.strimzi.io/v1beta2
kind: Kafka
metadata:
  name: my-kafka
  namespace: ${KAFKA_NS}
spec:
  kafka:
    version: ${KAFKA_VERSION}
    listeners:
      - name: plain
        port: 9092
        type: internal
        tls: false
    config:
      offsets.topic.replication.factor: 1
      transaction.state.log.replication.factor: 1
      transaction.state.log.min.isr: 1
      default.replication.factor: 1
      min.insync.replicas: 1
EOF

echo "⏳ Waiting 25 seconds for Kafka pod..."
sleep 25


# ===============================
# 5) Check Kafka pods
# ===============================
kubectl get pods -n ${KAFKA_NS}


# ===============================
# 6) Create client pod
# ===============================
echo "✅ Creating Kafka Client pod..."

kubectl delete pod kafka-client -n ${KAFKA_NS} --ignore-not-found

kubectl run kafka-client \
  -n ${KAFKA_NS} \
  --restart='Never' \
  --image=${CLIENT_IMAGE} \
  -- sleep infinity


echo "⏳ Waiting 10 seconds client startup..."
sleep 10


# ===============================
# 7) Final info
# ===============================
echo
echo "✅ ✅ ✅ Kafka Local Cluster READY ✅ ✅ ✅"

echo "
========================
Kafka Usage Example
========================
# exec
kubectl exec -it kafka-client -n kafka -- bash

# list topics
/opt/kafka/bin/kafka-topics.sh --bootstrap-server my-kafka-kafka-bootstrap.kafka:9092 --list

# create topic
/opt/kafka/bin/kafka-topics.sh \
    --bootstrap-server my-kafka-kafka-bootstrap.kafka:9092 \
    --create \
    --topic test-topic \
    --partitions 1 \
    --replication-factor 1

# console producer
/opt/kafka/bin/kafka-console-producer.sh \
  --bootstrap-server my-kafka-kafka-bootstrap.kafka:9092 \
  --topic test-topic

# console consumer
/opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server my-kafka-kafka-bootstrap.kafka:9092 \
  --topic test-topic \
  --from-beginning
"