#!/bin/bash

# ArgoCD 설치 스크립트
# 이 스크립트는 ArgoCD를 클러스터에 설치하고 App of Apps 패턴을 부트스트랩합니다.

set -euo pipefail

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 설정 변수
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ARGOCD_NAMESPACE="argocd"
ARGOCD_VERSION="${ARGOCD_VERSION:-v2.10.0}"

# 로그 함수
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }

# 환경 감지
detect_environment() {
    log_step "환경 감지 중..."

    # k3d 클러스터 확인
    if kubectl config current-context 2>/dev/null | grep -q "k3d"; then
        ENV="dev"
        log_info "k3d 클러스터 감지됨 (dev 환경)"
    elif kubectl config current-context 2>/dev/null | grep -q "eks"; then
        ENV="prod"
        log_info "EKS 클러스터 감지됨 (prod 환경)"
    else
        log_warn "환경을 자동으로 감지할 수 없습니다."
        read -p "환경을 선택하세요 (dev/prod): " ENV
    fi

    export ENV
}

# 필수 도구 확인
check_prerequisites() {
    log_step "필수 도구 확인 중..."

    local missing_tools=()

    for tool in kubectl helm; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done

    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "다음 도구가 설치되어 있지 않습니다: ${missing_tools[*]}"
        exit 1
    fi

    # 클러스터 연결 확인
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Kubernetes 클러스터에 연결할 수 없습니다."
        exit 1
    fi

    log_info "모든 필수 도구가 설치되어 있습니다."
}

# ArgoCD 네임스페이스 생성
create_namespace() {
    log_step "ArgoCD 네임스페이스 생성 중..."

    kubectl create namespace "$ARGOCD_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

    log_info "네임스페이스 '$ARGOCD_NAMESPACE' 준비됨"
}

# ArgoCD 고정 비밀번호 설정 (개발 환경 전용)
apply_admin_secret() {
    # 개발 환경에서만 고정 비밀번호 적용
    if [ "$ENV" != "dev" ]; then
        log_info "프로덕션 환경에서는 자동 생성된 비밀번호를 사용합니다."
        return 0
    fi

    log_step "ArgoCD 관리자 비밀번호 설정 중 (개발 환경)..."

    local secret_file="${PROJECT_ROOT}/config/dev/argocd-secret.yaml"

    if [ -f "$secret_file" ]; then
        kubectl apply -f "$secret_file"
        log_info "고정 비밀번호가 설정되었습니다. (admin / admin123)"
    else
        log_warn "config/dev/argocd-secret.yaml 파일이 없습니다. 자동 생성된 비밀번호를 사용합니다."
    fi
}

# ArgoCD 설치
install_argocd() {
    log_step "ArgoCD ${ARGOCD_VERSION} 설치 중..."

    # 이미 설치되어 있는지 확인
    if kubectl get deployment argocd-server -n "$ARGOCD_NAMESPACE" &> /dev/null; then
        log_warn "ArgoCD가 이미 설치되어 있습니다."
        read -p "재설치하시겠습니까? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "설치를 건너뜁니다."
            return 0
        fi
    fi

    # 고정 비밀번호 Secret 먼저 적용 (ArgoCD 설치 전)
    apply_admin_secret

    # ArgoCD 매니페스트 적용
    kubectl apply -n "$ARGOCD_NAMESPACE" \
        -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

    log_info "ArgoCD 설치 완료. Pod 준비 대기 중..."

    # Pod 준비 대기
    kubectl wait --for=condition=ready pod \
        -l app.kubernetes.io/name=argocd-server \
        -n "$ARGOCD_NAMESPACE" \
        --timeout=300s

    log_success "ArgoCD가 준비되었습니다."
}

# ArgoCD 관리자 비밀번호 확인
get_admin_password() {
    log_step "ArgoCD 관리자 비밀번호 확인..."

    # argocd-secret이 있으면 고정 비밀번호 사용 중
    if kubectl get secret argocd-secret -n "$ARGOCD_NAMESPACE" &>/dev/null; then
        log_info "고정 비밀번호가 설정되어 있습니다."
        log_info "Username: admin"
        log_info "Password: admin123"
    else
        # 자동 생성된 초기 비밀번호 확인
        local password
        password=$(kubectl -n "$ARGOCD_NAMESPACE" get secret argocd-initial-admin-secret \
            -o jsonpath="{.data.password}" 2>/dev/null | base64 -d)

        if [ -n "$password" ]; then
            log_info "ArgoCD 관리자 비밀번호: $password"
            log_warn "보안을 위해 로그인 후 비밀번호를 변경하세요!"
        else
            log_warn "초기 비밀번호를 찾을 수 없습니다. 이미 변경되었을 수 있습니다."
        fi
    fi
}

# ArgoCD Projects 적용
apply_projects() {
    log_step "ArgoCD Projects 적용 중..."

    local projects_dir="${PROJECT_ROOT}/argocd/projects"

    if [ -d "$projects_dir" ]; then
        for file in "$projects_dir"/*.yaml; do
            if [ -f "$file" ]; then
                log_info "적용 중: $(basename "$file")"
                kubectl apply -f "$file" -n "$ARGOCD_NAMESPACE"
            fi
        done
        log_success "ArgoCD Projects 적용 완료"
    else
        log_warn "Projects 디렉토리를 찾을 수 없습니다: $projects_dir"
    fi
}

# Root Application 적용 (App of Apps)
apply_root_application() {
    log_step "Root Application 적용 중 (App of Apps 패턴)..."

    local root_app="${PROJECT_ROOT}/bootstrap/root-application.yaml"

    if [ -f "$root_app" ]; then
        # 환경에 따라 적절한 Application 적용
        log_info "환경: $ENV"
        kubectl apply -f "$root_app" -n "$ARGOCD_NAMESPACE"
        log_success "Root Application 적용 완료"
    else
        log_warn "Root Application 파일을 찾을 수 없습니다: $root_app"
        log_info "수동으로 ApplicationSet을 적용하세요:"
        log_info "  kubectl apply -f ${PROJECT_ROOT}/argocd/applicationsets/ -n $ARGOCD_NAMESPACE"
    fi
}

# Port forwarding 안내
show_access_info() {
    log_step "접속 정보..."

    echo ""
    log_info "=== ArgoCD 접속 방법 ==="
    echo ""
    log_info "1. Port Forwarding:"
    echo "   kubectl port-forward svc/argocd-server -n $ARGOCD_NAMESPACE 8080:443"
    echo ""
    log_info "2. 브라우저에서 접속:"
    echo "   https://localhost:8080"
    echo ""
    log_info "3. 로그인 정보:"
    echo "   Username: admin"
    echo "   Password: (위에서 출력된 비밀번호)"
    echo ""

    if [ "$ENV" = "dev" ]; then
        log_info "4. (선택) NodePort로 접속:"
        echo "   kubectl patch svc argocd-server -n $ARGOCD_NAMESPACE -p '{\"spec\": {\"type\": \"NodePort\"}}'"
    fi
}

# 메인 함수
main() {
    log_step "=== ArgoCD Bootstrap 시작 ==="

    detect_environment
    check_prerequisites
    create_namespace
    install_argocd
    get_admin_password
    apply_projects
    apply_root_application
    show_access_info

    log_step "=== ArgoCD Bootstrap 완료 ==="
}

# 스크립트 실행
main "$@"
