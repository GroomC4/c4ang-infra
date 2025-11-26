#!/bin/bash
# Kafka 인프라 배포 스크립트
# Strimzi Operator, Kafka Cluster, Schema Registry, Topics, Connect, UI 배포
#
# 사용법:
#   ./kafka.sh                    # 전체 배포
#   ./kafka.sh --no-topics        # Topics 제외
#   ./kafka.sh --no-ui            # UI 제외
#   ./kafka.sh --status           # 상태 확인만

set -euo pipefail

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 스크립트 경로
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CHARTS_DIR="${PROJECT_ROOT}/charts"

# 설정
KAFKA_NS="kafka"

# 로그 함수
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 사전 체크
check_prerequisites() {
    log_info "사전 요구사항 확인 중..."

    command -v kubectl &> /dev/null || { log_error "kubectl이 설치되어 있지 않습니다."; exit 1; }
    command -v helm &> /dev/null || { log_error "helm이 설치되어 있지 않습니다."; exit 1; }
    kubectl cluster-info &> /dev/null || { log_error "Kubernetes 클러스터에 연결할 수 없습니다."; exit 1; }

    log_success "사전 요구사항 확인 완료"
}

# 네임스페이스 생성
ensure_namespace() {
    if ! kubectl get namespace "$KAFKA_NS" &> /dev/null; then
        log_info "네임스페이스 생성: $KAFKA_NS"
        kubectl create namespace "$KAFKA_NS"
    fi
}

# Pod 대기 (kubectl wait 사용 - 더 효율적)
wait_for_pods() {
    local namespace=$1
    local selector=$2
    local timeout=${3:-120}  # 기본 120초

    log_info "Pod 준비 대기 중... (selector: $selector, timeout: ${timeout}s)"

    if kubectl wait --for=condition=ready pod -l "$selector" -n "$namespace" --timeout="${timeout}s" 2>/dev/null; then
        log_success "Pod 준비 완료"
        return 0
    else
        local pod_count
        pod_count=$(kubectl get pods -n "$namespace" -l "$selector" --no-headers 2>/dev/null | wc -l | tr -d ' ') || true
        if [ "${pod_count:-0}" -eq 0 ]; then
            log_warn "해당 selector의 Pod가 없습니다: $selector"
        else
            log_warn "Pod 준비 타임아웃 (${timeout}s)"
        fi
        return 1
    fi
}

# Kafka 클러스터 대기
wait_for_kafka_cluster() {
    local timeout=${1:-300}  # 기본 300초 (Kafka는 시간이 오래 걸림)

    log_info "Kafka 클러스터 준비 대기 중... (timeout: ${timeout}s)"

    if kubectl wait kafka/c4-kafka --for=condition=Ready -n "$KAFKA_NS" --timeout="${timeout}s" 2>/dev/null; then
        log_success "Kafka 클러스터 준비 완료"
        return 0
    else
        local kafka_exists
        kafka_exists=$(kubectl get kafka c4-kafka -n "$KAFKA_NS" --no-headers 2>/dev/null | wc -l | tr -d ' ') || true
        if [ "${kafka_exists:-0}" -eq 0 ]; then
            log_warn "Kafka 클러스터가 존재하지 않습니다"
        else
            log_warn "Kafka 클러스터 준비 타임아웃 (${timeout}s)"
        fi
        return 1
    fi
}

# 1. Strimzi Operator + Kafka Cluster 배포
deploy_kafka_cluster() {
    log_info "=== Strimzi Operator + Kafka Cluster 배포 ==="

    ensure_namespace

    # Strimzi Operator 설치
    log_info "Strimzi Operator 설치 중..."
    kubectl apply -f "https://strimzi.io/install/latest?namespace=$KAFKA_NS" -n "$KAFKA_NS" 2>/dev/null || true

    # Operator 준비 대기
    wait_for_pods "$KAFKA_NS" "name=strimzi-cluster-operator" 120 || true

    # Kafka Cluster 배포 (manifest 사용)
    local kafka_manifest="${CHARTS_DIR}/kafka-cluster/kafka-cluster.yaml"
    if [ -f "$kafka_manifest" ]; then
        log_info "Kafka Cluster 배포 중..."
        kubectl apply -f "$kafka_manifest" -n "$KAFKA_NS"

        wait_for_kafka_cluster 300 || true
    else
        log_warn "kafka-cluster manifest를 찾을 수 없습니다: $kafka_manifest"
    fi
}

# 2. Schema Registry 배포
deploy_schema_registry() {
    log_info "=== Schema Registry 배포 ==="

    local schema_manifest="${CHARTS_DIR}/schema-registry/schema-registry-deployment.yaml"
    if [ -f "$schema_manifest" ]; then
        kubectl apply -f "$schema_manifest" -n "$KAFKA_NS" || log_warn "Schema Registry 배포 실패"

        wait_for_pods "$KAFKA_NS" "app=cp-schema-registry" 120 || true
    else
        log_warn "schema-registry manifest를 찾을 수 없습니다: $schema_manifest"
    fi
}

# 3. Kafka Topics 배포
deploy_kafka_topics() {
    log_info "=== Kafka Topics 배포 ==="

    if [ -d "${CHARTS_DIR}/kafka-topics" ]; then
        helm upgrade --install kafka-topics "${CHARTS_DIR}/kafka-topics" \
            -n "$KAFKA_NS" --wait --timeout 5m || log_warn "Kafka Topics 배포 실패"

        sleep 5
        local topic_count=$(kubectl get kafkatopic -n "$KAFKA_NS" --no-headers 2>/dev/null | wc -l | tr -d ' ')
        log_info "Kafka Topics 생성됨: ${topic_count}개"
    else
        log_warn "kafka-topics 차트를 찾을 수 없습니다"
    fi
}

# 4. Kafka Connect 배포
deploy_kafka_connect() {
    log_info "=== Kafka Connect 배포 ==="

    if [ -d "${CHARTS_DIR}/kafka-connect" ]; then
        helm upgrade --install kafka-connect "${CHARTS_DIR}/kafka-connect" \
            -n "$KAFKA_NS" --wait --timeout 5m || log_warn "Kafka Connect 배포 실패"

        wait_for_pods "$KAFKA_NS" "strimzi.io/name=c4-kafka-connect-connect" 120 || true
    else
        log_warn "kafka-connect 차트를 찾을 수 없습니다"
    fi
}

# 5. Kafka UI 배포
deploy_kafka_ui() {
    log_info "=== Kafka UI 배포 ==="

    if [ -d "${CHARTS_DIR}/kafka-ui" ]; then
        helm upgrade --install kafka-ui "${CHARTS_DIR}/kafka-ui" \
            -n "$KAFKA_NS" --wait --timeout 5m || log_warn "Kafka UI 배포 실패"

        wait_for_pods "$KAFKA_NS" "app.kubernetes.io/name=kafka-ui" 120 || true

        log_info "Kafka UI 접속: kubectl port-forward -n kafka svc/kafka-ui 8080:8080"
    else
        log_warn "kafka-ui 차트를 찾을 수 없습니다"
    fi
}

# 상태 확인
show_status() {
    echo ""
    log_info "=== Kafka 인프라 상태 ==="
    echo ""

    echo "Kafka Cluster:"
    if kubectl get kafka -n "$KAFKA_NS" 2>/dev/null; then
        :
    else
        echo "  없음"
    fi
    echo ""

    echo "Kafka Pods:"
    local pods
    pods=$(kubectl get pods -n "$KAFKA_NS" --no-headers 2>/dev/null | head -20) || true
    if [ -n "$pods" ]; then
        echo "$pods"
    else
        echo "  없음"
    fi
    echo ""

    echo "Kafka Topics:"
    local topic_count
    topic_count=$(kubectl get kafkatopic -n "$KAFKA_NS" --no-headers 2>/dev/null | wc -l | tr -d ' ') || true
    echo "  ${topic_count:-0}개"
    echo ""

    echo "Kafka Connect:"
    if kubectl get kafkaconnect -n "$KAFKA_NS" 2>/dev/null; then
        :
    else
        echo "  없음"
    fi
    echo ""

    echo "Services:"
    local svcs
    svcs=$(kubectl get svc -n "$KAFKA_NS" --no-headers 2>/dev/null) || true
    if [ -n "$svcs" ]; then
        echo "$svcs"
    else
        echo "  없음"
    fi
}

# 사용법
usage() {
    cat << EOF
사용법: $0 [옵션]

옵션:
  --no-topics    Kafka Topics 배포 건너뛰기
  --no-ui        Kafka UI 배포 건너뛰기
  --no-connect   Kafka Connect 배포 건너뛰기
  --status       상태 확인만
  --help         도움말

예시:
  $0                    # 전체 배포
  $0 --no-ui            # UI 제외 배포
  $0 --status           # 상태 확인

EOF
}

# 메인
main() {
    local deploy_topics=true
    local deploy_ui=true
    local deploy_connect=true
    local status_only=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            --no-topics) deploy_topics=false; shift ;;
            --no-ui) deploy_ui=false; shift ;;
            --no-connect) deploy_connect=false; shift ;;
            --status) status_only=true; shift ;;
            --help|-h) usage; exit 0 ;;
            *) log_error "알 수 없는 옵션: $1"; usage; exit 1 ;;
        esac
    done

    if [ "$status_only" = true ]; then
        show_status
        exit 0
    fi

    log_info "=========================================="
    log_info "Kafka 인프라 배포 시작"
    log_info "=========================================="

    check_prerequisites

    deploy_kafka_cluster
    deploy_schema_registry

    [ "$deploy_topics" = true ] && deploy_kafka_topics
    [ "$deploy_connect" = true ] && deploy_kafka_connect
    [ "$deploy_ui" = true ] && deploy_kafka_ui

    log_success "=========================================="
    log_success "Kafka 인프라 배포 완료"
    log_success "=========================================="

    show_status
}

main "$@"
