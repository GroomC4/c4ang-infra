#!/bin/bash
set -e

# 환경 변수 설정
CLUSTER_NAME="${CLUSTER_NAME:-msa-quality-cluster}"
NAMESPACE="${NAMESPACE:-msa-quality}"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-600}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_DIR="$(dirname "${SCRIPT_DIR}")"
KUBECONFIG_FILE="${ENV_DIR}/kubeconfig/config"
PROJECT_ROOT="$(cd "${ENV_DIR}/../../.." && pwd)"
VALUES_DIR="${ENV_DIR}/values"
CONFIG_DIR="${PROJECT_ROOT}/c4ang-infra/config/local"

echo "🚀 로컬 환경 시작 스크립트"
echo "=================================="
echo "클러스터 이름: ${CLUSTER_NAME}"
echo "네임스페이스: ${NAMESPACE}"
echo ""

# kubeconfig 확인
if [ ! -f "${KUBECONFIG_FILE}" ]; then
    echo "❌ kubeconfig 파일을 찾을 수 없습니다: ${KUBECONFIG_FILE}"
    echo "먼저 install-k3s.sh를 실행하여 클러스터를 생성하세요."
    exit 1
fi

export KUBECONFIG="${KUBECONFIG_FILE}"

# 클러스터 상태 확인
if ! kubectl cluster-info &> /dev/null; then
    echo "⚠️  클러스터에 연결할 수 없습니다. 클러스터를 시작합니다..."
    k3d cluster start "${CLUSTER_NAME}" || {
        echo "❌ 클러스터 시작 실패. install-k3s.sh를 실행하여 클러스터를 생성하세요."
        exit 1
    }
fi

# 네임스페이스 생성
echo "📦 네임스페이스 생성 중..."
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

# Helm 차트 의존성 빌드
echo "🔨 Helm 차트 의존성 빌드 중..."
cd "${PROJECT_ROOT}/c4ang-infra/charts"

# PostgreSQL 의존성 빌드
if [ -d "statefulset-base/postgresql" ]; then
    echo "📦 PostgreSQL 의존성 빌드 중..."
    cd statefulset-base/postgresql
    helm dependency build || echo "⚠️  PostgreSQL 의존성 빌드 실패"
    cd "${PROJECT_ROOT}/c4ang-infra/charts"
fi

# Redis 의존성 빌드 (필요시)
if [ -d "statefulset-base/redis" ]; then
    echo "📦 Redis 의존성 확인 중..."
    cd statefulset-base/redis
    if [ -f "Chart.yaml" ] && grep -q "dependencies:" Chart.yaml 2>/dev/null; then
        helm dependency build || echo "⚠️  Redis 의존성 빌드 실패"
    fi
    cd "${PROJECT_ROOT}/c4ang-infra/charts"
fi

# values 디렉토리 확인 및 생성
if [ ! -d "${VALUES_DIR}" ]; then
    echo "📁 values 디렉토리 생성 중..."
    mkdir -p "${VALUES_DIR}"
    
    # config/local의 파일들을 values로 복사
    if [ -d "${CONFIG_DIR}" ]; then
        echo "📋 설정 파일 복사 중..."
        cp "${CONFIG_DIR}/postgresql.yaml" "${VALUES_DIR}/" 2>/dev/null || true
        cp "${CONFIG_DIR}/redis.yaml" "${VALUES_DIR}/" 2>/dev/null || true
    fi
fi

# PostgreSQL 배포
echo "🐘 PostgreSQL 배포 중..."
if [ -f "${VALUES_DIR}/postgresql.yaml" ]; then
    helm upgrade --install postgresql \
        "${PROJECT_ROOT}/c4ang-infra/charts/statefulset-base/postgresql" \
        --namespace "${NAMESPACE}" \
        --create-namespace \
        --values "${VALUES_DIR}/postgresql.yaml" \
        --wait \
        --timeout "${WAIT_TIMEOUT}s" || {
        echo "⚠️  PostgreSQL 배포 실패. 계속 진행합니다..."
    }
else
    echo "⚠️  postgresql.yaml을 찾을 수 없습니다. 기본 설정으로 배포합니다."
    helm upgrade --install postgresql \
        "${PROJECT_ROOT}/c4ang-infra/charts/statefulset-base/postgresql" \
        --namespace "${NAMESPACE}" \
        --create-namespace \
        --wait \
        --timeout "${WAIT_TIMEOUT}s" || {
        echo "⚠️  PostgreSQL 배포 실패. 계속 진행합니다..."
    }
fi

# Redis 배포
echo "🔴 Redis 배포 중..."
if [ -f "${VALUES_DIR}/redis.yaml" ]; then
    helm upgrade --install redis \
        "${PROJECT_ROOT}/c4ang-infra/charts/statefulset-base/redis" \
        --namespace "${NAMESPACE}" \
        --create-namespace \
        --values "${VALUES_DIR}/redis.yaml" \
        --wait \
        --timeout "${WAIT_TIMEOUT}s" || {
        echo "⚠️  Redis 배포 실패. 계속 진행합니다..."
    }
else
    echo "⚠️  redis.yaml을 찾을 수 없습니다. 기본 설정으로 배포합니다."
    helm upgrade --install redis \
        "${PROJECT_ROOT}/c4ang-infra/charts/statefulset-base/redis" \
        --namespace "${NAMESPACE}" \
        --create-namespace \
        --wait \
        --timeout "${WAIT_TIMEOUT}s" || {
        echo "⚠️  Redis 배포 실패. 계속 진행합니다..."
    }
fi

# 배포 상태 확인
echo ""
echo "📊 배포 상태 확인 중..."
echo "=================================="
kubectl get pods -n "${NAMESPACE}"
echo ""

# 헬스체크
echo "🏥 헬스체크 중..."
sleep 5

POSTGRESQL_READY=$(kubectl get pods -n "${NAMESPACE}" -l app.kubernetes.io/name=postgresql -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
REDIS_READY=$(kubectl get pods -n "${NAMESPACE}" -l app=redis -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")

echo "PostgreSQL Ready: ${POSTGRESQL_READY}"
echo "Redis Ready: ${REDIS_READY}"
echo ""

# 서비스 정보 출력
echo "📋 서비스 정보:"
echo "=================================="
kubectl get svc -n "${NAMESPACE}"
echo ""

echo "✅ 로컬 환경 시작 완료!"
echo ""
echo "다음 명령어로 상태를 확인하세요:"
echo "  kubectl get pods -n ${NAMESPACE}"
echo "  kubectl get svc -n ${NAMESPACE}"
echo ""

