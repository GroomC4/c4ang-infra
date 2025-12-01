#!/bin/bash
set -e

# 환경 변수 설정
NAMESPACE="${NAMESPACE:-ecommerce}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_DIR="$(dirname "${SCRIPT_DIR}")"
KUBECONFIG_FILE="${ENV_DIR}/kubeconfig/config"
PROJECT_ROOT="$(cd "${ENV_DIR}/../../.." && pwd)"
VALUES_DIR="${ENV_DIR}/values"
CONFIG_DIR="${PROJECT_ROOT}/c4ang-infra/config/local"

echo "🌐 Istio 설치 스크립트"
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

# Istio Control Plane 설치 확인
echo "🔍 Istio Control Plane 확인 중..."
if ! kubectl get crd gateways.gateway.networking.k8s.io &> /dev/null; then
    echo "📦 Istio Control Plane 설치 중..."
    
    # istioctl이 설치되어 있는지 확인
    if command -v istioctl &> /dev/null; then
        echo "✅ istioctl을 사용하여 Istio 설치 중..."
        istioctl install --set values.defaultRevision=default -y || {
            echo "⚠️  istioctl 설치 실패. Helm으로 시도합니다..."
            
            # Helm으로 Istio base 설치
            helm repo add istio https://istio-release.storage.googleapis.com/charts 2>/dev/null || true
            helm repo update
            
            kubectl create namespace istio-system --dry-run=client -o yaml | kubectl apply -f -
            helm install istio-base istio/base -n istio-system --wait || {
                echo "❌ Istio base 설치 실패"
                exit 1
            }
            
            helm install istiod istio/istiod -n istio-system --wait || {
                echo "❌ Istiod 설치 실패"
                exit 1
            }
        }
    else
        echo "⚠️  istioctl이 설치되어 있지 않습니다. Helm으로 설치합니다..."
        
        # Helm으로 Istio base 설치
        helm repo add istio https://istio-release.storage.googleapis.com/charts 2>/dev/null || true
        helm repo update
        
        kubectl create namespace istio-system --dry-run=client -o yaml | kubectl apply -f -
        helm install istio-base istio/base -n istio-system --wait || {
            echo "❌ Istio base 설치 실패"
            exit 1
        }
        
        helm install istiod istio/istiod -n istio-system --wait || {
            echo "❌ Istiod 설치 실패"
            exit 1
        }
    fi
    
    echo "⏳ Istio CRD가 준비될 때까지 대기 중..."
    sleep 10
else
    echo "✅ Istio Control Plane이 이미 설치되어 있습니다."
fi

# Gateway API CRD 설치 확인
echo "🔍 Gateway API CRD 확인 중..."
if ! kubectl get crd gateways.gateway.networking.k8s.io &> /dev/null; then
    echo "📦 Gateway API CRD 설치 중..."
    kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.0.0/standard-install.yaml || {
        echo "⚠️  Gateway API CRD 설치 실패"
        exit 1
    }
    echo "⏳ Gateway API CRD가 준비될 때까지 대기 중..."
    sleep 5
else
    echo "✅ Gateway API CRD가 이미 설치되어 있습니다."
fi

# Helm 차트 의존성 빌드
echo "🔨 Istio Helm 차트 의존성 빌드 중..."
ISTIO_CHART_DIR="${PROJECT_ROOT}/c4ang-infra/charts/istio"
if [ ! -d "${ISTIO_CHART_DIR}" ]; then
    ISTIO_CHART_DIR="${PROJECT_ROOT}/c4ang-infra/charts/management-base/istio"
fi

if [ -d "${ISTIO_CHART_DIR}" ] && [ -f "${ISTIO_CHART_DIR}/Chart.yaml" ]; then
    cd "${ISTIO_CHART_DIR}"
    helm dependency build || echo "⚠️  의존성 빌드 실패. 계속 진행합니다..."
else
    echo "⚠️  Istio Chart.yaml을 찾을 수 없습니다. 의존성 빌드를 건너뜁니다."
fi

# values 파일 확인
VALUES_FILE="${CONFIG_DIR}/istio.yaml"
if [ ! -f "${VALUES_FILE}" ]; then
    VALUES_FILE="${VALUES_DIR}/istio.yaml"
fi

if [ ! -f "${VALUES_FILE}" ]; then
    echo "⚠️  istio.yaml을 찾을 수 없습니다. 기본 설정으로 설치합니다."
    VALUES_FILE=""
fi

# Istio 차트 경로 확인
ISTIO_CHART_DIR="${PROJECT_ROOT}/c4ang-infra/charts/istio"
if [ ! -d "${ISTIO_CHART_DIR}" ]; then
    ISTIO_CHART_DIR="${PROJECT_ROOT}/c4ang-infra/charts/management-base/istio"
fi

if [ ! -d "${ISTIO_CHART_DIR}" ]; then
    echo "❌ Istio 차트 디렉토리를 찾을 수 없습니다."
    exit 1
fi

# Istio 설치
echo "🚀 Istio 설치 중..."
if [ -n "${VALUES_FILE}" ] && [ -f "${VALUES_FILE}" ]; then
    helm upgrade --install istio \
        "${ISTIO_CHART_DIR}" \
        --namespace "${NAMESPACE}" \
        --create-namespace \
        --values "${VALUES_FILE}" \
        --wait || {
        echo "⚠️  Istio 설치 중 오류가 발생했습니다."
        exit 1
    }
else
    helm upgrade --install istio \
        "${ISTIO_CHART_DIR}" \
        --namespace "${NAMESPACE}" \
        --create-namespace \
        --wait || {
        echo "⚠️  Istio 설치 중 오류가 발생했습니다."
        exit 1
    }
fi

# 설치 상태 확인
echo ""
echo "📊 Istio 설치 상태 확인 중..."
echo "=================================="
kubectl get pods -n "${NAMESPACE}"
kubectl get svc -n "${NAMESPACE}"
echo ""

echo "✅ Istio 설치 완료!"
echo ""
echo "다음 명령어로 상태를 확인하세요:"
echo "  kubectl get pods -n ${NAMESPACE}"
echo "  kubectl get gateway -n ${NAMESPACE}"
echo ""

