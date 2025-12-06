#!/bin/bash
# Metrics Server 설치 스크립트 (HPA 작동을 위해 필요)

set -e

echo "📊 Metrics Server 설치 중..."
echo ""

# Metrics Server 설치 (EKS용)
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# 설치 확인 대기
echo "⏳ Metrics Server 설치 대기 중..."
sleep 10

# Pod 상태 확인
kubectl get pods -n kube-system -l k8s-app=metrics-server

# 설치 확인
echo ""
echo "✅ Metrics Server 설치 완료!"
echo ""
echo "테스트:"
echo "  kubectl top nodes"
echo "  kubectl top pods -n kafka"

