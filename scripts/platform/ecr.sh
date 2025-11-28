#!/bin/bash
# =============================================================================
# ECR Secret 관리 스크립트
# =============================================================================
#
# AWS ECR 이미지 Pull을 위한 docker-registry Secret 생성/갱신
# 로컬 ~/.aws/credentials를 사용하여 ECR 토큰을 발급받아 Secret 생성
#
# 사용법:
#   ./ecr.sh                    # Secret 생성/갱신
#   ./ecr.sh --status           # 상태 확인 (만료 시간 포함)
#   ./ecr.sh --delete           # Secret 삭제
#   ./ecr.sh --help             # 도움말

set -euo pipefail

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 스크립트 경로
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# 설정
ECR_REGISTRY="${ECR_REGISTRY:-963403601423.dkr.ecr.ap-northeast-2.amazonaws.com}"
AWS_REGION="${AWS_REGION:-ap-northeast-2}"
SECRET_NAME="${ECR_SECRET_NAME:-ecr-secret}"
NAMESPACE="${NAMESPACE:-ecommerce}"
KUBECONFIG_FILE="${PROJECT_ROOT}/k8s-dev-k3d/kubeconfig/config"

# 로그 함수
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "\n${GREEN}▶${NC} $1"; }

# =============================================================================
# 사전 요구사항 확인
# =============================================================================

check_prerequisites() {
    log_info "사전 요구사항 확인 중..."

    local missing=()

    # AWS CLI 확인
    if ! command -v aws &>/dev/null; then
        missing+=("aws-cli")
    fi

    # kubectl 확인
    if ! command -v kubectl &>/dev/null; then
        missing+=("kubectl")
    fi

    if [ ${#missing[@]} -gt 0 ]; then
        log_error "다음 도구가 필요합니다: ${missing[*]}"
        echo ""
        echo "설치 방법 (macOS):"
        echo "  brew install awscli kubectl"
        exit 1
    fi

    # AWS 자격증명 확인
    if ! aws sts get-caller-identity &>/dev/null; then
        log_error "AWS 자격증명이 설정되지 않았거나 만료되었습니다."
        echo ""
        echo "AWS 자격증명 설정:"
        echo "  aws configure"
        echo "  또는"
        echo "  aws sso login --profile <profile-name>"
        exit 1
    fi

    log_success "사전 요구사항 확인 완료"
}

# kubeconfig 설정
setup_kubeconfig() {
    if [ -f "${KUBECONFIG_FILE}" ]; then
        export KUBECONFIG="${KUBECONFIG_FILE}"
    fi

    # 클러스터 연결 확인
    if ! kubectl cluster-info &>/dev/null; then
        log_error "Kubernetes 클러스터에 연결할 수 없습니다."
        echo ""
        echo "k3d 클러스터가 실행 중인지 확인하세요:"
        echo "  k3d cluster list"
        echo "  ./scripts/bootstrap/local.sh --up"
        exit 1
    fi
}

# =============================================================================
# ECR Secret 관리
# =============================================================================

create_or_update_secret() {
    log_step "ECR Secret 생성/갱신"

    check_prerequisites
    setup_kubeconfig

    # 네임스페이스 존재 확인
    if ! kubectl get namespace "${NAMESPACE}" &>/dev/null; then
        log_info "네임스페이스 생성: ${NAMESPACE}"
        kubectl create namespace "${NAMESPACE}"
    fi

    # ECR 토큰 발급
    log_info "ECR 토큰 발급 중..."
    local ecr_token
    ecr_token=$(aws ecr get-login-password --region "${AWS_REGION}")

    if [ -z "$ecr_token" ]; then
        log_error "ECR 토큰 발급 실패"
        exit 1
    fi

    # 기존 Secret 삭제 (있으면)
    if kubectl get secret "${SECRET_NAME}" -n "${NAMESPACE}" &>/dev/null; then
        log_info "기존 Secret 삭제 중..."
        kubectl delete secret "${SECRET_NAME}" -n "${NAMESPACE}"
    fi

    # 새 Secret 생성
    log_info "새 Secret 생성 중..."
    kubectl create secret docker-registry "${SECRET_NAME}" \
        --docker-server="${ECR_REGISTRY}" \
        --docker-username=AWS \
        --docker-password="${ecr_token}" \
        -n "${NAMESPACE}"

    # 생성 시간 annotation 추가
    local created_at
    created_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    kubectl annotate secret "${SECRET_NAME}" -n "${NAMESPACE}" \
        "ecr-secret/created-at=${created_at}" \
        --overwrite

    log_success "ECR Secret 생성 완료: ${SECRET_NAME} (namespace: ${NAMESPACE})"
    echo ""
    log_info "토큰 유효 시간: 12시간"
    log_info "만료 예상 시간: $(date -v+12H '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -d '+12 hours' '+%Y-%m-%d %H:%M:%S')"
}

delete_secret() {
    log_step "ECR Secret 삭제"

    setup_kubeconfig

    if kubectl get secret "${SECRET_NAME}" -n "${NAMESPACE}" &>/dev/null; then
        kubectl delete secret "${SECRET_NAME}" -n "${NAMESPACE}"
        log_success "Secret 삭제됨: ${SECRET_NAME}"
    else
        log_info "Secret이 존재하지 않습니다: ${SECRET_NAME}"
    fi
}

show_status() {
    echo ""
    log_info "=== ECR Secret 상태 ==="
    echo ""

    # kubeconfig 설정
    if [ -f "${KUBECONFIG_FILE}" ]; then
        export KUBECONFIG="${KUBECONFIG_FILE}"
    fi

    # 클러스터 연결 확인
    echo -e "${CYAN}[클러스터 연결]${NC}"
    if kubectl cluster-info &>/dev/null; then
        echo "  상태: 연결됨"
    else
        echo "  상태: 연결 불가"
        echo "  k3d 클러스터를 먼저 시작하세요."
        return
    fi
    echo ""

    # Secret 상태
    echo -e "${CYAN}[ECR Secret]${NC}"
    if kubectl get secret "${SECRET_NAME}" -n "${NAMESPACE}" &>/dev/null; then
        echo "  이름: ${SECRET_NAME}"
        echo "  네임스페이스: ${NAMESPACE}"

        # 생성 시간 확인
        local created_at
        created_at=$(kubectl get secret "${SECRET_NAME}" -n "${NAMESPACE}" \
            -o jsonpath='{.metadata.annotations.ecr-secret/created-at}' 2>/dev/null || echo "")

        if [ -n "$created_at" ]; then
            echo "  생성 시간: ${created_at}"

            # 만료 시간 계산 (macOS와 Linux 호환)
            local created_epoch
            local expires_epoch
            local now_epoch
            local remaining

            if [[ "$OSTYPE" == "darwin"* ]]; then
                created_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "${created_at}" "+%s" 2>/dev/null || echo "0")
            else
                created_epoch=$(date -d "${created_at}" "+%s" 2>/dev/null || echo "0")
            fi

            if [ "$created_epoch" != "0" ]; then
                expires_epoch=$((created_epoch + 43200))  # 12시간 = 43200초
                now_epoch=$(date +%s)
                remaining=$((expires_epoch - now_epoch))

                if [ $remaining -gt 0 ]; then
                    local hours=$((remaining / 3600))
                    local minutes=$(((remaining % 3600) / 60))
                    echo -e "  남은 시간: ${GREEN}${hours}시간 ${minutes}분${NC}"
                else
                    echo -e "  상태: ${RED}만료됨${NC}"
                    echo ""
                    log_warn "Secret을 갱신하세요: ./scripts/platform/ecr.sh"
                fi
            fi
        else
            echo "  생성 시간: 알 수 없음"
        fi
    else
        echo "  상태: 없음"
        echo ""
        log_info "Secret 생성: ./scripts/platform/ecr.sh"
    fi
    echo ""

    # AWS 자격증명 상태
    echo -e "${CYAN}[AWS 자격증명]${NC}"
    if aws sts get-caller-identity &>/dev/null; then
        local identity
        identity=$(aws sts get-caller-identity --query 'Arn' --output text 2>/dev/null)
        echo "  상태: 유효함"
        echo "  계정: ${identity}"
    else
        echo -e "  상태: ${RED}설정 안 됨 또는 만료${NC}"
        echo "  'aws configure' 또는 'aws sso login'을 실행하세요."
    fi
    echo ""

    # ECR 레지스트리 정보
    echo -e "${CYAN}[ECR 레지스트리]${NC}"
    echo "  주소: ${ECR_REGISTRY}"
    echo "  리전: ${AWS_REGION}"
}

# =============================================================================
# 사용법
# =============================================================================

usage() {
    cat << EOF
ECR Secret 관리 스크립트

사용법: $0 [옵션]

옵션:
  (없음)          ECR Secret 생성/갱신
  --status        상태 확인 (만료 시간 포함)
  --delete        Secret 삭제
  --help          도움말

설명:
  AWS ECR에서 이미지를 pull하기 위한 docker-registry Secret을 생성합니다.
  로컬 ~/.aws/credentials를 사용하여 ECR 토큰을 발급받습니다.

  ECR 토큰은 12시간 후 만료됩니다.
  만료 시 이 스크립트를 다시 실행하여 갱신하세요.

환경 변수:
  ECR_REGISTRY      ECR 레지스트리 주소 (기본: 963403601423.dkr.ecr.ap-northeast-2.amazonaws.com)
  AWS_REGION        AWS 리전 (기본: ap-northeast-2)
  ECR_SECRET_NAME   Secret 이름 (기본: ecr-secret)
  NAMESPACE         네임스페이스 (기본: ecommerce)

예시:
  $0                 # Secret 생성/갱신
  $0 --status        # 상태 확인
  $0 --delete        # Secret 삭제

  # 다른 네임스페이스에 생성
  NAMESPACE=other-ns $0

EOF
}

# =============================================================================
# 메인
# =============================================================================

main() {
    local action="create"

    while [[ $# -gt 0 ]]; do
        case $1 in
            --status) action="status"; shift ;;
            --delete) action="delete"; shift ;;
            --help|-h) usage; exit 0 ;;
            *) log_error "알 수 없는 옵션: $1"; usage; exit 1 ;;
        esac
    done

    case $action in
        create) create_or_update_secret ;;
        status) show_status ;;
        delete) delete_secret ;;
    esac
}

main "$@"
