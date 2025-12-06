#!/bin/bash
# HPA 모니터링 스크립트

set -e

NAMESPACE="kafka"
HPA_NAME="kafka-consumer-hpa"
DEPLOYMENT_NAME="kafka-consumer"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║     Kafka Consumer HPA Monitoring Dashboard              ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "Press Ctrl+C to exit"
echo ""

while true; do
  clear
  echo "╔════════════════════════════════════════════════════════════╗"
  echo "║     Kafka Consumer HPA Monitoring Dashboard              ║"
  echo "╚════════════════════════════════════════════════════════════╝"
  echo ""
  
  # HPA Status
  echo "📊 HPA Status:"
  echo "────────────────────────────────────────────────────────────"
  kubectl get hpa -n $NAMESPACE $HPA_NAME -o custom-columns=\
NAME:.metadata.name,\
REFERENCE:.spec.scaleTargetRef.name,\
MINPODS:.spec.minReplicas,\
MAXPODS:.spec.maxReplicas,\
REPLICAS:.status.currentReplicas,\
CPU:.status.currentMetrics[0].resource.current.averageUtilization 2>/dev/null || echo "HPA not found"
  echo ""
  
  # Pod Status
  echo "📦 Pod Status:"
  echo "────────────────────────────────────────────────────────────"
  kubectl get pods -n $NAMESPACE -l app=$DEPLOYMENT_NAME -o custom-columns=\
NAME:.metadata.name,\
STATUS:.status.phase,\
RESTARTS:.status.containerStatuses[0].restartCount,\
AGE:.metadata.creationTimestamp,\
NODE:.spec.nodeName
  echo ""
  
  # Resource Usage
  echo "💻 Resource Usage:"
  echo "────────────────────────────────────────────────────────────"
  kubectl top pods -n $NAMESPACE -l app=$DEPLOYMENT_NAME 2>/dev/null || echo "Metrics Server not available"
  echo ""
  
  # Consumer Group Status
  echo "📈 Consumer Group Status:"
  echo "────────────────────────────────────────────────────────────"
  POD_NAME=$(kubectl get pods -n $NAMESPACE -l app=kafka-client --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  if [ -n "$POD_NAME" ]; then
    MSK_BROKERS=$(kubectl get secret -n $NAMESPACE msk-bootstrap-brokers -o jsonpath='{.data.bootstrap-brokers}' 2>/dev/null | base64 -d)
    if [ -n "$MSK_BROKERS" ]; then
      kubectl exec -n $NAMESPACE $POD_NAME -- kafka-consumer-groups \
        --bootstrap-server $MSK_BROKERS \
        --describe \
        --group hpa-test-consumer-group 2>/dev/null | grep -E "TOPIC|LAG|CURRENT-OFFSET" | head -5 || echo "Consumer Group not found or no messages"
    else
      echo "MSK Bootstrap Brokers secret not found"
    fi
  else
    echo "kafka-client pod not found"
  fi
  echo ""
  
  # HPA Events (최근 3개)
  echo "📋 Recent HPA Events:"
  echo "────────────────────────────────────────────────────────────"
  kubectl describe hpa -n $NAMESPACE $HPA_NAME 2>/dev/null | grep -A 5 "Events:" | tail -6 || echo "No events"
  echo ""
  
  echo "⏰ Updated: $(date '+%Y-%m-%d %H:%M:%S')"
  echo ""
  echo "Press Ctrl+C to exit"
  sleep 5
done

