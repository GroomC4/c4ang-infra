#!/bin/bash
set -e

# 환경 변수 설정
NAMESPACE="${NAMESPACE:-monitoring}"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-600}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_DIR="$(dirname "${SCRIPT_DIR}")"
KUBECONFIG_FILE="${ENV_DIR}/kubeconfig/config"
PROJECT_ROOT="$(cd "${ENV_DIR}/../../.." && pwd)"
VALUES_DIR="${ENV_DIR}/values"
CONFIG_DIR="${PROJECT_ROOT}/c4ang-infra/config/local"

echo "📊 Argo Rollouts 모니터링 배포 스크립트"
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

# Helm 차트 의존성 빌드
echo "🔨 Monitoring Helm 차트 의존성 빌드 중..."
cd "${PROJECT_ROOT}/c4ang-infra/charts/monitoring"
if [ -f "Chart.yaml" ]; then
    helm dependency build || echo "⚠️  의존성 빌드 실패. 계속 진행합니다..."
else
    echo "❌ Monitoring Chart.yaml을 찾을 수 없습니다."
    exit 1
fi

# values 파일 확인 (k3d 최적화 설정 우선)
VALUES_FILE="${CONFIG_DIR}/monitoring.yaml"
if [ ! -f "${VALUES_FILE}" ]; then
    VALUES_FILE="${VALUES_DIR}/monitoring.yaml"
fi

# k3d 최적화 values 파일이 있으면 사용
K3D_VALUES="${PROJECT_ROOT}/c4ang-infra/charts/monitoring/values-k3d.yaml"
if [ -f "${K3D_VALUES}" ]; then
    echo "📋 k3d 최적화 설정 파일 사용: ${K3D_VALUES}"
    if [ -n "${VALUES_FILE}" ] && [ -f "${VALUES_FILE}" ]; then
        # 두 파일 모두 사용
        VALUES_ARGS="-f ${K3D_VALUES} -f ${VALUES_FILE}"
    else
        VALUES_ARGS="-f ${K3D_VALUES}"
    fi
elif [ -n "${VALUES_FILE}" ] && [ -f "${VALUES_FILE}" ]; then
    VALUES_ARGS="-f ${VALUES_FILE}"
else
    echo "⚠️  monitoring.yaml을 찾을 수 없습니다. 기본 설정으로 설치합니다."
    VALUES_ARGS=""
fi

# Monitoring 스택 설치
echo "🚀 Monitoring 스택 설치 중..."
helm upgrade --install monitoring \
    "${PROJECT_ROOT}/c4ang-infra/charts/monitoring" \
    --namespace "${NAMESPACE}" \
    --create-namespace \
    ${VALUES_ARGS} \
    --wait \
    --timeout "${WAIT_TIMEOUT}s" || {
    echo "⚠️  Monitoring 설치 중 오류가 발생했습니다."
    exit 1
}

# 설치 상태 확인
echo ""
echo "📊 Monitoring 설치 상태 확인 중..."
echo "=================================="
kubectl get pods -n "${NAMESPACE}"
kubectl get svc -n "${NAMESPACE}"
echo ""

# 접속 정보 출력
echo "🌐 접속 정보:"
echo "=================================="
echo ""
echo "Grafana (대시보드):"
echo "  kubectl port-forward -n ${NAMESPACE} svc/grafana 3000:3000"
echo "  http://localhost:3000 (admin/admin)"
echo ""
echo "Prometheus (메트릭):"
echo "  kubectl port-forward -n ${NAMESPACE} svc/prometheus 9090:9090"
echo "  http://localhost:9090"
echo ""
echo "Loki (로그):"
echo "  kubectl port-forward -n ${NAMESPACE} svc/loki 3100:3100"
echo "  http://localhost:3100"
echo ""
echo "Tempo (트레이스):"
echo "  kubectl port-forward -n ${NAMESPACE} svc/tempo 3200:3200"
echo "  http://localhost:3200"
echo ""

echo "✅ Monitoring 스택 배포 완료!"
echo ""

