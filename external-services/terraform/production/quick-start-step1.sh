#!/bin/bash
set -e

echo "🚀 Step 1: MSK + EKS + kafka-client 기본 통신 테스트 시작"
echo ""

# 1. EKS 클러스터 연결
echo "📡 Step 1.1: EKS 클러스터 연결 설정..."
EKS_CLUSTER_NAME=$(terraform output -raw eks_cluster_name)
AWS_REGION=$(terraform output -raw aws_region)
aws eks update-kubeconfig --name $EKS_CLUSTER_NAME --region $AWS_REGION
echo "✅ EKS 클러스터 연결 완료: $EKS_CLUSTER_NAME"
kubectl get nodes | head -3
echo ""

# 2. MSK Bootstrap Brokers Secret 생성
echo "🔐 Step 1.2: MSK Bootstrap Brokers Secret 생성..."
MSK_BROKERS=$(terraform output -raw msk_bootstrap_brokers)
kubectl create namespace kafka --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic msk-bootstrap-brokers \
  --from-literal=bootstrap-brokers="$MSK_BROKERS" \
  -n kafka \
  --dry-run=client -o yaml | kubectl apply -f -
echo "✅ Secret 생성 완료"
echo ""

# 3. kafka-client YAML 업데이트 및 배포
echo "📦 Step 1.3: kafka-client Pod 배포..."
cd k8s
if [ -f msk-kafka-client.yaml ]; then
  # YAML 파일 백업 및 업데이트
  cp msk-kafka-client.yaml msk-kafka-client.yaml.bak
  sed "s|REPLACE_WITH_MSK_BOOTSTRAP_BROKERS|$MSK_BROKERS|g" msk-kafka-client.yaml.bak > msk-kafka-client.yaml
  kubectl apply -f msk-kafka-client.yaml
  echo "✅ kafka-client 배포 완료"
else
  echo "❌ msk-kafka-client.yaml 파일을 찾을 수 없습니다"
  exit 1
fi
cd ..
echo ""

# 4. Pod 상태 확인
echo "⏳ Step 1.4: Pod 상태 확인 (30초 대기)..."
sleep 30
kubectl get pods -n kafka -l app=kafka-client
echo ""

# 5. 연결 테스트
echo "🧪 Step 1.5: MSK 연결 테스트..."
POD_NAME=$(kubectl get pods -n kafka -l app=kafka-client -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$POD_NAME" ]; then
  echo "Pod 이름: $POD_NAME"
  echo "토픽 목록 확인 중..."
  kubectl exec -n kafka $POD_NAME -- kafka-topics.sh --bootstrap-server $MSK_BROKERS --list || echo "⚠️  연결 테스트 실패 (Pod가 아직 준비 중일 수 있음)"
else
  echo "⚠️  Pod를 찾을 수 없습니다. 잠시 후 다시 시도하세요."
fi
echo ""

echo "✅ Step 1 기본 설정 완료!"
echo ""
echo "다음 단계:"
echo "  1. Pod 로그 확인: kubectl logs -n kafka -l app=kafka-client"
echo "  2. Pod 접속: kubectl exec -it -n kafka <POD_NAME> -- /bin/sh"
echo "  3. 토픽 생성 테스트: kafka-topics.sh --bootstrap-server \$MSK_BOOTSTRAP_BROKERS --create --topic test-topic --partitions 3 --replication-factor 3"
echo ""
echo "자세한 가이드는 STEP1_EXECUTE.md를 참고하세요."
