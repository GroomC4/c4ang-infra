# Kafka Operator + Kafka Cluster 설치 스크립트
#!/usr/bin/env bash
set -euo pipefail

#################################
# CONFIG
#################################
KAFKA_NS="kafka"
STRIMZI_VERSION="latest"
KAFKA_VERSION="4.1.0"
CLUSTER_NAME="  c4-kafka"
CLIENT_IMAGE="quay.io/strimzi/kafka:latest-kafka-${KAFKA_VERSION}"

echo "🚀 Start Kafka Installation on EKS"
echo


#################################
# 1) Create Namespace
#################################
echo "📌 Creating namespace: ${KAFKA_NS}"
kubectl get ns ${KAFKA_NS} >/dev/null 2>&1 || \
kubectl create namespace ${KAFKA_NS}


#################################
# 2) Install Strimzi Operator
#################################
echo "📌 Installing Strimzi Operator"

kubectl apply -f \
  "https://strimzi.io/install/${STRIMZI_VERSION}?namespace=${KAFKA_NS}" \
  -n ${KAFKA_NS}

echo "⏳ Waiting 10 sec..."
sleep 10

echo "✅ Strimzi installed"
echo


#################################
# 3) Install Kafka Cluster
#################################
echo "📌 Deploying Kafka Cluster ${CLUSTER_NAME}"

cat <<EOF | kubectl apply -n ${KAFKA_NS} -f -
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaNodePool
metadata:
  name: kafka-pool
  namespace: ${KAFKA_NS}
  labels:
    strimzi.io/cluster: ${CLUSTER_NAME}
spec:
  replicas: 3
  roles:
    - broker
    - controller
  storage:
    type: ephemeral
---
apiVersion: kafka.strimzi.io/v1beta2
kind: Kafka
metadata:
  name: ${CLUSTER_NAME}
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
      default.replication.factor: 1
      offsets.topic.replication.factor: 1
      transaction.state.log.replication.factor: 1
      transaction.state.log.min.isr: 1
      min.insync.replicas: 1
EOF

echo "⏳ Waiting 25 sec for Kafka pods..."
sleep 25
echo "✅ Kafka cluster deployed"
echo


#################################
# 4) Create Kafka Client Pod
#################################
echo "📌 Creating Kafka Client pod..."

kubectl delete pod kafka-client -n ${KAFKA_NS} --ignore-not-found

kubectl run kafka-client \
  -n ${KAFKA_NS} \
  --restart='Never' \
  --image=${CLIENT_IMAGE} \
  -- sleep infinity

echo "⏳ Waiting 10 sec..."
sleep 10

echo "✅ Kafka client created"
echo


#################################
# 5) Install Schema Registry
#################################
echo "📌 Installing Schema Registry..."

# Schema Registry를 Kubernetes 리소스로 직접 배포
SCHEMA_REGISTRY_YAML="$(dirname "$0")/schema-registry/schema-registry-deployment.yaml"

if [ -f "$SCHEMA_REGISTRY_YAML" ]; then
    echo "Deploying Schema Registry from YAML..."
    kubectl apply -f "$SCHEMA_REGISTRY_YAML" || {
        echo "❌ Schema Registry 배포 실패"
        exit 1
    }
    
    echo "⏳ Waiting for Schema Registry pods..."
    kubectl wait --for=condition=ready pod \
      -l app=cp-schema-registry \
      -n ${KAFKA_NS} \
      --timeout=300s || echo "⚠️  Schema Registry pods may still be starting..."
    
    echo "✅ Schema Registry deployed"
    echo "   Service: schema-registry-cp-schema-registry.${KAFKA_NS}:8081"
else
    echo "⚠️  Schema Registry YAML 파일을 찾을 수 없습니다: $SCHEMA_REGISTRY_YAML"
    echo "⚠️  Schema Registry 설치를 건너뜁니다."
fi
echo


#################################
# 6) Show status
#################################
echo "📊 Current Status:"
echo
kubectl get pods -n ${KAFKA_NS}

echo
echo "🚀✅ Kafka + Schema Registry installation complete!"
echo

echo "
========================
Kafka Usage Example
========================
# exec
kubectl exec -it kafka-client -n ${KAFKA_NS} -- bash

# list topics
/opt/kafka/bin/kafka-topics.sh --bootstrap-server ${CLUSTER_NAME}-kafka-bootstrap.${KAFKA_NS}:9092 --list

# create topic
/opt/kafka/bin/kafka-topics.sh \
    --bootstrap-server ${CLUSTER_NAME}-kafka-bootstrap.${KAFKA_NS}:9092 \
    --create \
    --topic test-topic \
    --partitions 1 \
    --replication-factor 1

# producer
/opt/kafka/bin/kafka-console-producer.sh \
  --bootstrap-server ${CLUSTER_NAME}-kafka-bootstrap.${KAFKA_NS}:9092 \
  --topic test-topic

# consumer
/opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server ${CLUSTER_NAME}-kafka-bootstrap.${KAFKA_NS}:9092 \
  --topic test-topic \
  --from-beginning

========================
Schema Registry Usage
========================
# Check Schema Registry health
kubectl port-forward -n ${KAFKA_NS} svc/schema-registry-cp-schema-registry 8081:8081 &
curl http://localhost:8081/

# List subjects (schemas)
curl http://localhost:8081/subjects

# Check _schemas topic (created automatically)
kubectl exec -it kafka-client -n ${KAFKA_NS} -- \
  /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server ${CLUSTER_NAME}-kafka-bootstrap.${KAFKA_NS}:9092 \
  --list | grep _schemas

# Application connection URL
# http://schema-registry-cp-schema-registry.${KAFKA_NS}:8081
"