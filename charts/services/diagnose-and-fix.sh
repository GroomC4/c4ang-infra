#!/bin/bash

# 문제 진단 및 자동 수정 스크립트

set -euo pipefail

export PATH="/Users/kim/Documents/GitHub/c4ang-infra/k8s-eks/istio/istio-1.28.0/bin:$PATH"
NAMESPACE="ecommerce"

echo "=== 1. Pod에서 직접 응답 확인 ==="
echo ""

# Order Service Pod 직접 테스트
ORDER_POD=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=order-service -o jsonpath='{.items[0].metadata.name}')
echo "Order Service Pod: $ORDER_POD"
echo "Order Service 직접 접근 (Pod 내부):"
kubectl exec -n $NAMESPACE $ORDER_POD -c order-service -- /http-echo -listen=:9999 -text="Direct Test" &
sleep 2
kubectl exec -n $NAMESPACE $ORDER_POD -c order-service -- wget -qO- http://localhost:5678/ 2>/dev/null || echo "접근 실패"
echo ""

# Order Service의 실제 프로세스 확인
echo "Order Service 실행 중인 프로세스:"
kubectl exec -n $NAMESPACE $ORDER_POD -c order-service -- ps aux 2>/dev/null || echo "ps 명령 없음"
echo ""

echo "=== 2. Service Endpoints 확인 ==="
kubectl get endpoints -n $NAMESPACE | grep api
echo ""

echo "=== 3. VirtualService 상세 확인 ==="
kubectl get virtualservice order-api-vs -n $NAMESPACE -o yaml | grep -A30 "spec:"
echo ""

echo "=== 4. Istio Proxy 로그 확인 ==="
echo "Order Service Istio Proxy 로그 (최근 20줄):"
kubectl logs $ORDER_POD -n $NAMESPACE -c istio-proxy --tail=20


