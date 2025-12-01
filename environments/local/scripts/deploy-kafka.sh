#!/bin/bash
set -e

# 환경 변수 설정
NAMESPACE="${NAMESPACE:-kafka}"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-600}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_DIR="$(dirname "${SCRIPT_DIR}")"
KUBECONFIG_FILE="${ENV_DIR}/kubeconfig/config"
PROJECT_ROOT="$(cd "${ENV_DIR}/../../.." && pwd)"
KAFKA_CONFIG="${PROJECT_ROOT}/c4ang-infra/charts/kafka-cluster/kafka-cluster.yaml"

echo "📨 Kafka 배포 스크립트"
echo "=================================="
echo "네임스페이스: ${NAMESPACE}"
echo ""

# kubeconfig 확인
if [ ! -f "${KUBECONFIG_FILE}" ]; then
    echo "❌ kubeconfig 파일을 찾을 수 없습니다: ${KUBECONFIG_FILE}"
    exit 1
fi

export KUBECONFIG="${KUBECONFIG_FILE}"

# 클러스터 연결 확인
if ! kubectl cluster-info &> /dev/null; then
    echo "❌ 클러스터에 연결할 수 없습니다."
    exit 1
fi

# 네임스페이스 생성
echo "📦 네임스페이스 생성 중..."
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

# Strimzi Operator 설치 확인
echo "🔍 Strimzi Operator 확인 중..."
if ! kubectl get crd kafkas.kafka.strimzi.io &> /dev/null; then
    echo "📦 Strimzi Operator 설치 중..."
    
    # Strimzi Operator 설치
    kubectl create -f 'https://strimzi.io/install/latest?namespace=kafka' -n "${NAMESPACE}" || {
        echo "⚠️  Strimzi Operator 설치 실패. 수동으로 설치하세요:"
        echo "kubectl create -f 'https://strimzi.io/install/latest?namespace=kafka' -n ${NAMESPACE}"
        exit 1
    }
    
    echo "⏳ Strimzi Operator가 준비될 때까지 대기 중..."
    kubectl wait --for=condition=Available deployment/strimzi-cluster-operator -n "${NAMESPACE}" --timeout="${WAIT_TIMEOUT}s" || {
        echo "⚠️  Strimzi Operator 대기 시간 초과"
    }
else
    echo "✅ Strimzi Operator가 이미 설치되어 있습니다."
fi

# Kafka 클러스터 설정 파일 확인 및 k3d 최적화
if [ -f "${KAFKA_CONFIG}" ]; then
    echo "📋 Kafka 클러스터 설정 확인 중..."
    
    # k3d 환경에 맞게 replicas를 1로 조정한 임시 파일 생성
    TEMP_KAFKA_CONFIG=$(mktemp)
    cp "${KAFKA_CONFIG}" "${TEMP_KAFKA_CONFIG}"
    
    # k3d 환경에서는 replicas를 1로 줄임
    if grep -q "replicas: 3" "${TEMP_KAFKA_CONFIG}"; then
        echo "🔧 k3d 환경에 맞게 replicas 조정 중..."
        sed -i.bak 's/replicas: 3/replicas: 1/g' "${TEMP_KAFKA_CONFIG}"
        sed -i.bak 's/replication.factor: 3/replication.factor: 1/g' "${TEMP_KAFKA_CONFIG}"
        sed -i.bak 's/min.isr: 2/min.isr: 1/g' "${TEMP_KAFKA_CONFIG}"
    fi
    
    # Kafka 클러스터 배포
    echo "🚀 Kafka 클러스터 배포 중..."
    kubectl apply -f "${TEMP_KAFKA_CONFIG}" || {
        echo "⚠️  Kafka 클러스터 배포 실패"
        rm -f "${TEMP_KAFKA_CONFIG}" "${TEMP_KAFKA_CONFIG}.bak"
        exit 1
    }
    
    # 임시 파일 삭제
    rm -f "${TEMP_KAFKA_CONFIG}" "${TEMP_KAFKA_CONFIG}.bak"
    
    echo "⏳ Kafka 클러스터가 준비될 때까지 대기 중..."
    kubectl wait --for=condition=Ready kafka/c4-kafka -n "${NAMESPACE}" --timeout="${WAIT_TIMEOUT}s" || {
        echo "⚠️  Kafka 클러스터 대기 시간 초과. 상태 확인 중..."
        kubectl get kafka -n "${NAMESPACE}"
    }
else
    echo "❌ Kafka 설정 파일을 찾을 수 없습니다: ${KAFKA_CONFIG}"
    exit 1
fi

# 배포 상태 확인
echo ""
echo "📊 Kafka 배포 상태 확인 중..."
echo "=================================="
kubectl get kafka -n "${NAMESPACE}"
kubectl get pods -n "${NAMESPACE}"
kubectl get svc -n "${NAMESPACE}" | grep kafka || true
echo ""

echo "✅ Kafka 배포 완료!"
echo ""
echo "다음 명령어로 상태를 확인하세요:"
echo "  kubectl get kafka -n ${NAMESPACE}"
echo "  kubectl get pods -n ${NAMESPACE}"
echo "  kubectl get svc -n ${NAMESPACE}"
echo ""

