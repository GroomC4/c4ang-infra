#!/bin/bash

# 최종 배포 및 테스트 스크립트

set -e

export PATH="/Users/kim/Documents/GitHub/c4ang-infra/k8s-eks/istio/istio-1.28.0/bin:$PATH"
cd /Users/kim/Documents/GitHub/c4ang-infra

NAMESPACE="ecommerce"

echo "🚀 모든 서비스 VirtualService만 재배포 (빠른 수정)"
echo ""

SERVICES=("order-service" "product-service" "payment-service" "recommendation-service" "saga-tracker")

for service in "${SERVICES[@]}"; do
  api_name="${service/-service/}-api"
  if [ "$service" = "saga-tracker" ]; then
    api_name="saga-tracker-api"
  fi
  
  echo "[$service] VirtualService 재배포..."
  
  helm template $api_name helm/services/$service \
    -n $NAMESPACE \
    -f helm/services/$service/values-eks-test.yaml \
    --show-only templates/virtualservice.yaml | \
    kubectl apply -f - -n $NAMESPACE
    
  echo "  ✓ 완료"
done

echo ""
echo "⏳ 10초 대기..."
sleep 10

echo ""
echo "🧪 모든 서비스 테스트"
echo ""

# Customer Service
echo "[1/6] Customer:"
kubectl run test-v2-customer --image=curlimages/curl:latest --restart=Never -n $NAMESPACE --rm -i -- \
  curl -s -H "Host: api.c4ang.com" \
  http://istio-ingressgateway.istio-system.svc.cluster.local/api/v1/customers
echo ""

# Order Service
echo "[2/6] Order:"
kubectl run test-v2-order --image=curlimages/curl:latest --restart=Never -n $NAMESPACE --rm -i -- \
  curl -s -H "Host: api.c4ang.com" \
  http://istio-ingressgateway.istio-system.svc.cluster.local/api/v1/orders
echo ""

# Product Service
echo "[3/6] Product:"
kubectl run test-v2-product --image=curlimages/curl:latest --restart=Never -n $NAMESPACE --rm -i -- \
  curl -s -H "Host: api.c4ang.com" \
  http://istio-ingressgateway.istio-system.svc.cluster.local/api/v1/products
echo ""

# Payment Service
echo "[4/6] Payment:"
kubectl run test-v2-payment --image=curlimages/curl:latest --restart=Never -n $NAMESPACE --rm -i -- \
  curl -s -H "Host: api.c4ang.com" \
  http://istio-ingressgateway.istio-system.svc.cluster.local/api/v1/payments
echo ""

# Recommendation Service
echo "[5/6] Recommendation:"
kubectl run test-v2-rec --image=curlimages/curl:latest --restart=Never -n $NAMESPACE --rm -i -- \
  curl -s -H "Host: api.c4ang.com" \
  http://istio-ingressgateway.istio-system.svc.cluster.local/api/v1/recommendations
echo ""

# Saga Tracker
echo "[6/6] Saga:"
kubectl run test-v2-saga --image=curlimages/curl:latest --restart=Never -n $NAMESPACE --rm -i -- \
  curl -s -H "Host: api.c4ang.com" \
  http://istio-ingressgateway.istio-system.svc.cluster.local/api/v1/saga
echo ""

echo "✅ 테스트 완료!"


