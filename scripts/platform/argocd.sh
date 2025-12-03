#!/bin/bash
# ArgoCD 설치 및 관리 스크립트
# App of Apps 패턴을 사용한 GitOps 부트스트랩
#
# 사용법:
#   ./argocd.sh                    # ArgoCD 설치 및 부트스트랩
#   ./argocd.sh --status           # 상태 확인
#   ./argocd.sh --password         # 관리자 비밀번호 확인
#   ./argocd.sh --uninstall        # ArgoCD 제거

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

# 설정
ARGOCD_NS="argocd"
ARGOCD_VERSION="${ARGOCD_VERSION:-v2.10.0}"

# 로그 함수
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 사전 체크
check_prerequisites() {
    log_info "사전 요구사항 확인 중..."

    command -v kubectl &> /dev/null || { log_error "kubectl이 필요합니다."; exit 1; }
    command -v helm &> /dev/null || { log_error "helm이 필요합니다."; exit 1; }
    kubectl cluster-info &> /dev/null || { log_error "클러스터에 연결할 수 없습니다."; exit 1; }

    log_success "사전 요구사항 확인 완료"
}

# 환경 감지
detect_environment() {
    if kubectl config current-context 2>/dev/null | grep -q "k3d"; then
        echo "dev"
    elif kubectl config current-context 2>/dev/null | grep -q "eks"; then
        echo "prod"
    else
        echo "dev"
    fi
}

# 네임스페이스 생성
ensure_namespace() {
    if ! kubectl get namespace "$ARGOCD_NS" &> /dev/null; then
        log_info "네임스페이스 생성: $ARGOCD_NS"
        kubectl create namespace "$ARGOCD_NS"
    fi
}

# ArgoCD 설치
install_argocd() {
    log_info "=== ArgoCD 설치 시작 ==="

    check_prerequisites
    ensure_namespace

    local env=$(detect_environment)
    log_info "환경: $env"

    # 이미 설치 확인
    if kubectl get deployment argocd-server -n "$ARGOCD_NS" &> /dev/null; then
        log_warn "ArgoCD가 이미 설치되어 있습니다."
        read -p "재설치하시겠습니까? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "설치를 건너뜁니다."
            return 0
        fi
    fi

    # 개발 환경에서만 고정 비밀번호 Secret 적용 (ArgoCD 설치 전)
    if [ "$env" = "dev" ]; then
        local secret_file="${PROJECT_ROOT}/config/dev/argocd-secret.yaml"
        if [ -f "$secret_file" ]; then
            log_info "개발 환경 고정 비밀번호 설정 중..."
            kubectl apply -f "$secret_file"
        fi
    fi

    # ArgoCD 매니페스트 적용
    log_info "ArgoCD ${ARGOCD_VERSION} 설치 중..."
    kubectl apply -n "$ARGOCD_NS" \
        -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

    # Pod 준비 대기
    log_info "ArgoCD Pod 준비 대기 중..."
    kubectl wait --for=condition=ready pod \
        -l app.kubernetes.io/name=argocd-server \
        -n "$ARGOCD_NS" \
        --timeout=300s

    log_success "ArgoCD 설치 완료"

    # Projects 적용
    apply_projects

    # Root Application 적용
    apply_root_application "$env"

    # 초기 비밀번호 출력
    show_password

    # 접속 정보 출력
    show_access_info
}

# ArgoCD Projects 적용
apply_projects() {
    log_info "ArgoCD Projects 적용 중..."

    local projects_dir="${PROJECT_ROOT}/argocd/projects"

    if [ -d "$projects_dir" ]; then
        for file in "$projects_dir"/*.yaml; do
            if [ -f "$file" ]; then
                log_info "적용 중: $(basename "$file")"
                kubectl apply -f "$file" -n "$ARGOCD_NS"
            fi
        done
        log_success "ArgoCD Projects 적용 완료"
    else
        log_warn "Projects 디렉토리를 찾을 수 없습니다: $projects_dir"
    fi
}

# Root Application 적용
apply_root_application() {
    local env=${1:-dev}
    log_info "Root Application 적용 중 (App of Apps 패턴)..."

    local root_app="${PROJECT_ROOT}/bootstrap/root-application.yaml"

    if [ -f "$root_app" ]; then
        kubectl apply -f "$root_app" -n "$ARGOCD_NS"
        log_success "Root Application 적용 완료"
    else
        log_warn "Root Application 파일을 찾을 수 없습니다: $root_app"
        log_info "수동으로 ApplicationSet을 적용하세요:"
        echo "  kubectl apply -f ${PROJECT_ROOT}/argocd/applicationsets/ -n $ARGOCD_NS"
    fi
}

# 관리자 비밀번호 확인
show_password() {
    log_info "ArgoCD 관리자 비밀번호 확인 중..."

    # argocd-secret이 있으면 고정 비밀번호 사용 중
    if kubectl get secret argocd-secret -n "$ARGOCD_NS" &>/dev/null; then
        echo ""
        log_info "고정 비밀번호가 설정되어 있습니다."
        log_info "Username: admin"
        log_info "Password: admin123"
    else
        local password
        password=$(kubectl -n "$ARGOCD_NS" get secret argocd-initial-admin-secret \
            -o jsonpath="{.data.password}" 2>/dev/null | base64 -d) || true

        if [ -n "$password" ]; then
            echo ""
            log_info "관리자 비밀번호: $password"
            log_warn "보안을 위해 로그인 후 비밀번호를 변경하세요!"
        else
            log_warn "초기 비밀번호를 찾을 수 없습니다. 이미 변경되었을 수 있습니다."
        fi
    fi
}

# ArgoCD 제거
uninstall_argocd() {
    log_info "=== ArgoCD 제거 시작 ==="

    read -p "ArgoCD를 제거하시겠습니까? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "제거를 취소합니다."
        return 0
    fi

    # Root Application 제거
    if kubectl get application root-application -n "$ARGOCD_NS" &> /dev/null; then
        log_info "Root Application 제거 중..."
        kubectl delete application root-application -n "$ARGOCD_NS" --ignore-not-found=true
    fi

    # ArgoCD 제거
    log_info "ArgoCD 매니페스트 제거 중..."
    kubectl delete -n "$ARGOCD_NS" \
        -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml" \
        --ignore-not-found=true || true

    # 네임스페이스 제거
    log_info "네임스페이스 제거 중..."
    kubectl delete namespace "$ARGOCD_NS" --ignore-not-found=true

    log_success "=== ArgoCD 제거 완료 ==="
}

# 상태 확인
show_status() {
    echo ""
    log_info "=== ArgoCD 상태 ==="
    echo ""

    echo "ArgoCD Pods:"
    local pods
    pods=$(kubectl get pods -n "$ARGOCD_NS" --no-headers 2>/dev/null) || true
    if [ -n "$pods" ]; then
        kubectl get pods -n "$ARGOCD_NS" 2>/dev/null
    else
        echo "  없음"
    fi
    echo ""

    echo "ArgoCD Services:"
    local svcs
    svcs=$(kubectl get svc -n "$ARGOCD_NS" --no-headers 2>/dev/null) || true
    if [ -n "$svcs" ]; then
        kubectl get svc -n "$ARGOCD_NS" 2>/dev/null
    else
        echo "  없음"
    fi
    echo ""

    echo "Applications:"
    local apps
    apps=$(kubectl get applications -n "$ARGOCD_NS" --no-headers 2>/dev/null) || true
    if [ -n "$apps" ]; then
        kubectl get applications -n "$ARGOCD_NS" 2>/dev/null
    else
        echo "  없음"
    fi
    echo ""

    echo "ApplicationSets:"
    local appsets
    appsets=$(kubectl get applicationsets -n "$ARGOCD_NS" --no-headers 2>/dev/null) || true
    if [ -n "$appsets" ]; then
        kubectl get applicationsets -n "$ARGOCD_NS" 2>/dev/null
    else
        echo "  없음"
    fi
}

# 접속 정보 출력
show_access_info() {
    echo ""
    log_info "=== ArgoCD 접속 방법 ==="
    echo ""
    echo "1. Port Forwarding:"
    echo "   kubectl port-forward svc/argocd-server -n $ARGOCD_NS 8080:443"
    echo ""
    echo "2. 브라우저에서 접속:"
    echo "   https://localhost:8080"
    echo ""
    echo "3. 로그인 정보:"
    echo "   Username: admin"
    echo "   Password: (위에서 출력된 비밀번호)"
    echo ""
}

# 사용법
usage() {
    cat << EOF
사용법: $0 [옵션]

옵션:
  (없음)         ArgoCD 설치 및 부트스트랩
  --status       상태 확인만
  --password     관리자 비밀번호 확인
  --uninstall    ArgoCD 제거
  --help         도움말

예시:
  $0                    # ArgoCD 설치
  $0 --status           # 상태 확인
  $0 --password         # 비밀번호 확인
  $0 --uninstall        # ArgoCD 제거

환경 변수:
  ARGOCD_VERSION    ArgoCD 버전 (기본: v2.10.0)

EOF
}

# 메인
main() {
    local action="install"

    while [[ $# -gt 0 ]]; do
        case $1 in
            --status) action="status"; shift ;;
            --password) action="password"; shift ;;
            --uninstall) action="uninstall"; shift ;;
            --help|-h) usage; exit 0 ;;
            *) log_error "알 수 없는 옵션: $1"; usage; exit 1 ;;
        esac
    done

    case $action in
        install) install_argocd ;;
        status) show_status ;;
        password) show_password ;;
        uninstall) uninstall_argocd ;;
    esac
}

main "$@"
