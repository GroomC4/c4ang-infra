#!/bin/bash
# 이게 메인입니다!!! Kafka 인프라 전체 배포 스크립트
# DEPLOYMENT_ORDER.md에 따른 순차 배포

set -euo pipefail

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 로그 함수
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# 에러 핸들러
error_exit() {
    log_error "$1"
    exit 1
}

# 사전 체크
check_prerequisites() {
    log_info "사전 요구사항 확인 중..."
    
    # kubectl 확인
    if ! command -v kubectl &> /dev/null; then
        error_exit "kubectl이 설치되어 있지 않습니다."
    fi
    
    # helm 확인
    if ! command -v helm &> /dev/null; then
        error_exit "helm이 설치되어 있지 않습니다."
    fi
    
    # Kubernetes 연결 확인
    if ! kubectl cluster-info &> /dev/null; then
        error_exit "Kubernetes 클러스터에 연결할 수 없습니다."
    fi
    
    log_success "사전 요구사항 확인 완료"
}

# Kafka 클러스터 상태 확인
wait_for_kafka_cluster() {
    local max_attempts=60
    local attempt=0
    
    log_info "Kafka 클러스터가 준비될 때까지 대기 중..."
    
    while [ $attempt -lt $max_attempts ]; do
        if kubectl get kafka c4-kafka -n kafka -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; then
            log_success "Kafka 클러스터가 준비되었습니다"
            return 0
        fi
        
        attempt=$((attempt + 1))
        echo -n "."
        sleep 5
    done
    
    log_warning "Kafka 클러스터 준비 시간이 초과되었습니다. 계속 진행합니다..."
}

# Pod가 Ready 상태가 될 때까지 대기
wait_for_pods() {
    local namespace=$1
    local selector=$2
    local max_attempts=60
    local attempt=0
    
    log_info "Pod가 준비될 때까지 대기 중... (namespace: $namespace, selector: $selector)"
    
    while [ $attempt -lt $max_attempts ]; do
        local ready_count=$(kubectl get pods -n "$namespace" -l "$selector" -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -o "True" | wc -l | tr -d ' ')
        local total_count=$(kubectl get pods -n "$namespace" -l "$selector" --no-headers 2>/dev/null | wc -l | tr -d ' ')
        
        if [ "$ready_count" -gt 0 ] && [ "$ready_count" -eq "$total_count" ]; then
            log_success "모든 Pod가 준비되었습니다 ($ready_count/$total_count)"
            return 0
        fi
        
        attempt=$((attempt + 1))
        echo -n "."
        sleep 5
    done
    
    log_warning "Pod 준비 시간이 초과되었습니다. 계속 진행합니다..."
}

# 메인 배포 함수
main() {
    local deploy_topics=${1:-true}
    local deploy_ui=${2:-true}
    
    echo ""
    log_info "=========================================="
    log_info "Kafka 인프라 배포 시작"
    log_info "=========================================="
    echo ""
    
    # 현재 디렉토리 확인
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    cd "$SCRIPT_DIR" || error_exit "스크립트 디렉토리로 이동할 수 없습니다"
    
    # 사전 체크
    check_prerequisites
    
    # 1️⃣ Strimzi Operator + Kafka Cluster + Schema Registry 배포
    echo ""
    log_info "[1/4] Strimzi Operator + Kafka Cluster + Schema Registry 배포 중..."
    if [ -f "./setup-eks-kafka.sh" ]; then
        bash ./setup-eks-kafka.sh || error_exit "Kafka Operator 및 Cluster 배포 실패"
        
        # Kafka 클러스터 준비 대기
        wait_for_kafka_cluster
        
        # Schema Registry 확인
        log_info "Schema Registry 상태 확인 중..."
        wait_for_pods "kafka" "app=cp-schema-registry"
        
        if kubectl get svc -n kafka schema-registry-cp-schema-registry &>/dev/null; then
            log_success "Schema Registry가 배포되었습니다"
            log_info "  - 같은 네임스페이스: http://schema-registry-cp-schema-registry:8081"
            log_info "  - 다른 네임스페이스: http://schema-registry-cp-schema-registry.kafka:8081"
        else
            log_warning "Schema Registry Service를 찾을 수 없습니다"
        fi
    else
        error_exit "setup-eks-kafka.sh 파일을 찾을 수 없습니다"
    fi
    
    # 2️⃣ Kafka Topics 배포 (Helm으로 배포)
    if [ "$deploy_topics" = "true" ]; then
        echo ""
        log_info "[2/4] Kafka Topics 배포 중 (Helm)..."
        if [ -d "./kafka-topics" ]; then
            # Helm Chart 디렉토리로 이동
            cd kafka-topics || {
                log_warning "kafka-topics 디렉토리로 이동할 수 없습니다. 건너뜁니다."
                cd ..
            }
            
            # Helm dependency build (필요한 경우)
            if [ -f "Chart.yaml" ] && grep -q "dependencies:" Chart.yaml 2>/dev/null; then
                log_info "Helm dependencies 빌드 중..."
                helm dependency build || log_warning "Dependency build 실패 (계속 진행)"
            fi
            
            # 상위 디렉토리로 돌아가기
            cd .. || error_exit "상위 디렉토리로 이동할 수 없습니다"
            
            # Helm으로 Kafka Topics 배포
            log_info "Helm으로 Kafka Topics 배포 중..."
            if helm upgrade --install kafka-topics ./kafka-topics -n kafka --wait --timeout 5m; then
                log_success "Kafka Topics Helm 배포 완료"
                
                # 토픽 생성 확인
                log_info "Kafka Topics 생성 확인 중..."
                sleep 10  # KafkaTopic 리소스가 생성될 시간 대기
                
                # 안전하게 토픽 개수 확인
                local topic_count=0
                if kubectl get kafkatopic -n kafka --no-headers 2>/dev/null | grep -q .; then
                    topic_count=$(kubectl get kafkatopic -n kafka --no-headers 2>/dev/null | wc -l | tr -d '[:space:]')
                    topic_count=${topic_count:-0}
                fi
                
                if [ "${topic_count:-0}" -gt 0 ]; then
                    log_success "Kafka Topics가 생성되었습니다 ($topic_count개)"
                    log_info "  토픽 목록 확인: kubectl get kafkatopic -n kafka"
                else
                    log_warning "Kafka Topics를 찾을 수 없습니다. 잠시 후 다시 확인하세요."
                fi
            else
                log_warning "Kafka Topics Helm 배포 실패 (계속 진행)"
            fi
        else
            log_warning "kafka-topics 디렉토리를 찾을 수 없습니다. 건너뜁니다."
        fi
    else
        log_info "[2/4] Kafka Topics 배포 건너뛰기 (선택사항)"
    fi
    
    # 3️⃣ Kafka Connect + S3 Sink Connector 배포
    echo ""
    log_info "[3/4] Kafka Connect + S3 Sink Connector 배포 중..."
    if [ -d "./kafka-connect" ] && [ -f "./kafka-connect/setup-kafka-connect.sh" ]; then
        cd kafka-connect || error_exit "kafka-connect 디렉토리로 이동할 수 없습니다"
        bash ./setup-kafka-connect.sh || error_exit "Kafka Connect 배포 실패"
        cd .. || error_exit "상위 디렉토리로 이동할 수 없습니다"
        
        # Kafka Connect 준비 대기
        wait_for_pods "kafka" "strimzi.io/name=c4-kafka-connect-connect"
        
        # S3 Sink Connector 확인
        sleep 5
        if kubectl get kafkaconnector -n kafka &>/dev/null; then
            log_success "Kafka Connect 및 S3 Sink Connector가 배포되었습니다"
        else
            log_warning "Kafka Connector를 찾을 수 없습니다"
        fi
    else
        log_warning "kafka-connect 디렉토리 또는 setup-kafka-connect.sh를 찾을 수 없습니다. 건너뜁니다."
    fi
    
    # 4️⃣ Kafka UI 배포 (선택사항)
    if [ "$deploy_ui" = "true" ]; then
        echo ""
        log_info "[4/4] Kafka UI 배포 중..."
        if [ -d "./kafka-ui" ]; then
            helm upgrade --install kafka-ui ./kafka-ui -n kafka --wait || log_warning "Kafka UI 배포 실패 (계속 진행)"
            
            # Kafka UI 준비 대기
            wait_for_pods "kafka" "app.kubernetes.io/name=kafka-ui"
            
            if kubectl get svc -n kafka kafka-ui &>/dev/null; then
                log_success "Kafka UI가 배포되었습니다"
                log_info "  - 포트 포워딩: kubectl port-forward -n kafka svc/kafka-ui 8080:8080"
                log_info "  - 브라우저에서 http://localhost:8080 접속"
            else
                log_warning "Kafka UI Service를 찾을 수 없습니다"
            fi
        else
            log_warning "kafka-ui 디렉토리를 찾을 수 없습니다. 건너뜁니다."
        fi
    else
        log_info "[4/4] Kafka UI 배포 건너뛰기 (선택사항)"
    fi
    
    # 배포 완료 요약
    echo ""
    log_info "=========================================="
    log_success "Kafka 인프라 배포 완료!"
    log_info "=========================================="
    echo ""
    
    log_info "배포 상태 확인:"
    echo ""
    echo "  # Kafka Cluster"
    echo "  kubectl get kafka -n kafka"
    echo ""
    echo "  # Kafka Pods"
    echo "  kubectl get pods -n kafka"
    echo ""
    echo "  # Kafka Topics"
    echo "  kubectl get kafkatopic -n kafka"
    echo ""
    echo "  # Schema Registry"
    echo "  kubectl get pods -n kafka -l app=cp-schema-registry"
    echo "  kubectl get svc -n kafka schema-registry-cp-schema-registry"
    echo ""
    echo "  # Kafka Connect"
    echo "  kubectl get kafkaconnect -n kafka"
    echo "  kubectl get pods -n kafka -l strimzi.io/name=c4-kafka-connect-connect"
    echo ""
    echo "  # S3 Sink Connector"
    echo "  kubectl get kafkaconnector -n kafka"
    echo ""
    if [ "$deploy_ui" = "true" ]; then
        echo "  # Kafka UI"
        echo "  kubectl get pods -n kafka -l app.kubernetes.io/name=kafka-ui"
        echo "  kubectl get svc -n kafka kafka-ui"
        echo ""
    fi
}

# 사용법 출력
usage() {
    cat << EOF
사용법: $0 [옵션]

옵션:
  --no-topics    Kafka Topics 배포 건너뛰기
  --no-ui        Kafka UI 배포 건너뛰기
  --help         이 도움말 표시

예시:
  $0                    # 전체 배포 (Topics + UI 포함)
  $0 --no-topics        # Topics 제외하고 배포
  $0 --no-ui            # UI 제외하고 배포
  $0 --no-topics --no-ui # Topics와 UI 제외하고 배포

EOF
}

# 인자 파싱
deploy_topics=true
deploy_ui=true

while [[ $# -gt 0 ]]; do
    case $1 in
        --no-topics)
            deploy_topics=false
            shift
            ;;
        --no-ui)
            deploy_ui=false
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            log_error "알 수 없는 옵션: $1"
            usage
            exit 1
            ;;
    esac
done

# 메인 실행
main "$deploy_topics" "$deploy_ui"

