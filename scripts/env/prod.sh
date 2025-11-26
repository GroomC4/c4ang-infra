#!/bin/bash
# =============================================================================
# AWS 프로덕션 환경 초기화 스크립트
# =============================================================================
#
# 전체 플로우:
#   1. External Services 프로비저닝 (Terraform - RDS, ElastiCache, MSK)
#   2. EKS 클러스터 연결 설정
#   3. ArgoCD Bootstrap (App of Apps)
#
# 사전 요구사항:
#   - AWS CLI 설정 완료 (aws configure)
#   - Terraform 설치
#   - kubectl, helm 설치
#   - c4ang-terraform으로 VPC, EKS 생성 완료
#
# 사용법:
#   ./prod.sh                 # 전체 환경 초기화
#   ./prod.sh --plan          # Terraform plan만 실행
#   ./prod.sh --apply         # Terraform apply만 실행
#   ./prod.sh --bootstrap     # ArgoCD bootstrap만 실행
#   ./prod.sh --status        # 상태 확인
#   ./prod.sh --destroy       # 환경 삭제 (주의!)
#   ./prod.sh --help          # 도움말

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
AWS_REGION="${AWS_REGION:-ap-northeast-2}"
EKS_CLUSTER_NAME="${EKS_CLUSTER_NAME:-c4ang-prod-eks}"
TERRAFORM_DIR="${PROJECT_ROOT}/external-services/aws"
NAMESPACE="ecommerce"

# 로그 함수
log_header() { echo -e "\n${CYAN}========================================${NC}"; echo -e "${CYAN}  $1${NC}"; echo -e "${CYAN}========================================${NC}\n"; }
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "\n${GREEN}▶${NC} $1"; }

# =============================================================================
# Prerequisites
# =============================================================================

check_prerequisites() {
    log_info "사전 요구사항 확인 중..."

    local missing=()

    command -v aws &>/dev/null || missing+=("aws-cli")
    command -v terraform &>/dev/null || missing+=("terraform")
    command -v kubectl &>/dev/null || missing+=("kubectl")
    command -v helm &>/dev/null || missing+=("helm")

    if [ ${#missing[@]} -gt 0 ]; then
        log_error "다음 도구가 필요합니다: ${missing[*]}"
        echo ""
        echo "설치 방법 (macOS):"
        echo "  brew install awscli terraform kubectl helm"
        exit 1
    fi

    # AWS 자격 증명 확인
    if ! aws sts get-caller-identity &>/dev/null; then
        log_error "AWS 자격 증명이 설정되지 않았습니다."
        log_info "aws configure 명령어로 자격 증명을 설정하세요."
        exit 1
    fi

    log_success "사전 요구사항 확인 완료"

    # AWS 계정 정보 출력
    local account_id
    account_id=$(aws sts get-caller-identity --query Account --output text)
    log_info "AWS Account: ${account_id}"
    log_info "AWS Region: ${AWS_REGION}"
}

# =============================================================================
# Phase 1: External Services (Terraform)
# =============================================================================

terraform_init() {
    log_step "Terraform 초기화"

    cd "${TERRAFORM_DIR}"

    if [ ! -f "terraform.tfvars" ]; then
        log_warn "terraform.tfvars 파일이 없습니다."
        if [ -f "terraform.tfvars.example" ]; then
            log_info "terraform.tfvars.example을 복사하고 값을 수정하세요."
            echo ""
            echo "필수 설정:"
            echo "  - vpc_id: VPC ID (c4ang-terraform 출력값)"
            echo "  - database_subnet_ids: 데이터베이스 서브넷 ID 목록"
            echo "  - eks_node_security_group_id: EKS 노드 보안 그룹 ID"
            echo "  - rds_master_password: RDS 마스터 비밀번호"
            echo ""
            read -p "terraform.tfvars.example을 복사하시겠습니까? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                cp terraform.tfvars.example terraform.tfvars
                log_info "terraform.tfvars 파일을 수정하고 다시 실행하세요."
            fi
        fi
        exit 1
    fi

    terraform init

    cd "${PROJECT_ROOT}"
    log_success "Terraform 초기화 완료"
}

terraform_plan() {
    log_step "Phase 1: External Services - Terraform Plan"

    cd "${TERRAFORM_DIR}"

    terraform plan -out=tfplan

    cd "${PROJECT_ROOT}"
    log_success "Terraform Plan 완료"
    log_info "적용하려면: $0 --apply"
}

terraform_apply() {
    log_step "Phase 1: External Services - Terraform Apply"

    cd "${TERRAFORM_DIR}"

    if [ -f "tfplan" ]; then
        log_info "저장된 plan 적용 중..."
        terraform apply tfplan
        rm -f tfplan
    else
        log_info "Terraform apply 실행 중..."
        terraform apply
    fi

    # 출력값 저장
    log_info "Terraform 출력값 저장 중..."
    terraform output -json > terraform-outputs.json

    cd "${PROJECT_ROOT}"
    log_success "External Services 프로비저닝 완료"

    # ExternalName Service 값 업데이트 안내
    echo ""
    log_info "다음 단계:"
    echo "  1. Terraform 출력값 확인: cat ${TERRAFORM_DIR}/terraform-outputs.json"
    echo "  2. config/prod/external-services.yaml 업데이트"
    echo "  3. ArgoCD 동기화"
}

terraform_destroy() {
    log_step "External Services - Terraform Destroy"

    read -p "프로덕션 외부 서비스를 삭제합니다. 정말 계속하시겠습니까? (yes/NO): " -r
    if [[ ! $REPLY == "yes" ]]; then
        log_info "취소되었습니다."
        return 0
    fi

    cd "${TERRAFORM_DIR}"

    terraform destroy

    rm -f terraform-outputs.json tfplan

    cd "${PROJECT_ROOT}"
    log_success "External Services 삭제 완료"
}

# =============================================================================
# Phase 2: EKS Cluster Connection
# =============================================================================

connect_eks() {
    log_step "Phase 2: EKS 클러스터 연결"

    # kubeconfig 업데이트
    log_info "kubeconfig 업데이트 중..."
    aws eks update-kubeconfig \
        --name "${EKS_CLUSTER_NAME}" \
        --region "${AWS_REGION}"

    # 연결 확인
    if ! kubectl cluster-info &>/dev/null; then
        log_error "EKS 클러스터에 연결할 수 없습니다."
        log_info "EKS 클러스터가 실행 중인지 확인하세요:"
        echo "  aws eks describe-cluster --name ${EKS_CLUSTER_NAME} --region ${AWS_REGION}"
        exit 1
    fi

    log_success "EKS 클러스터 연결 성공"

    # 클러스터 정보
    kubectl cluster-info | head -1

    # 네임스페이스 생성
    kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
    log_success "네임스페이스 준비 완료: ${NAMESPACE}"
}

# =============================================================================
# Phase 3: ArgoCD Bootstrap
# =============================================================================

bootstrap_argocd() {
    log_step "Phase 3: ArgoCD Bootstrap (App of Apps)"

    # ArgoCD 스크립트 실행
    local argocd_script="${PROJECT_ROOT}/scripts/platform/argocd.sh"

    if [ -f "${argocd_script}" ]; then
        bash "${argocd_script}"
    else
        log_error "ArgoCD 스크립트를 찾을 수 없습니다: ${argocd_script}"
        exit 1
    fi

    log_success "ArgoCD Bootstrap 완료"
}

# =============================================================================
# Status
# =============================================================================

show_status() {
    log_header "프로덕션 환경 상태"

    # AWS 계정
    echo -e "${CYAN}[AWS Account]${NC}"
    if aws sts get-caller-identity &>/dev/null; then
        aws sts get-caller-identity --query '{Account:Account,Arn:Arn}' --output table
    else
        echo "  AWS 자격 증명 없음"
    fi
    echo ""

    # Terraform State
    echo -e "${CYAN}[Terraform State]${NC}"
    if [ -d "${TERRAFORM_DIR}" ] && [ -f "${TERRAFORM_DIR}/terraform.tfstate" ]; then
        cd "${TERRAFORM_DIR}"
        echo "  State 파일: 존재함"
        echo "  리소스 수: $(terraform state list 2>/dev/null | wc -l | tr -d ' ')"
        cd "${PROJECT_ROOT}"
    else
        echo "  State 파일: 없음"
    fi
    echo ""

    # EKS Cluster
    echo -e "${CYAN}[EKS Cluster]${NC}"
    if aws eks describe-cluster --name "${EKS_CLUSTER_NAME}" --region "${AWS_REGION}" &>/dev/null; then
        aws eks describe-cluster \
            --name "${EKS_CLUSTER_NAME}" \
            --region "${AWS_REGION}" \
            --query 'cluster.{Name:name,Status:status,Version:version}' \
            --output table
    else
        echo "  클러스터 없음 또는 접근 불가"
    fi
    echo ""

    # Kubernetes Resources
    echo -e "${CYAN}[Kubernetes]${NC}"
    if kubectl cluster-info &>/dev/null; then
        echo "Nodes:"
        kubectl get nodes 2>/dev/null || echo "  노드 없음"
        echo ""

        echo "ArgoCD:"
        if kubectl get namespace argocd &>/dev/null; then
            kubectl get pods -n argocd --no-headers 2>/dev/null | head -5 || echo "  Pod 없음"
        else
            echo "  미설치"
        fi
        echo ""

        echo "Applications:"
        kubectl get applications -n argocd --no-headers 2>/dev/null || echo "  없음"
    else
        echo "  클러스터 연결 불가"
    fi
    echo ""

    # RDS Instances
    echo -e "${CYAN}[RDS Instances]${NC}"
    aws rds describe-db-instances \
        --region "${AWS_REGION}" \
        --query "DBInstances[?contains(DBInstanceIdentifier, 'c4ang')].{ID:DBInstanceIdentifier,Status:DBInstanceStatus,Engine:Engine}" \
        --output table 2>/dev/null || echo "  RDS 인스턴스 없음"
    echo ""

    # ElastiCache
    echo -e "${CYAN}[ElastiCache]${NC}"
    aws elasticache describe-cache-clusters \
        --region "${AWS_REGION}" \
        --query "CacheClusters[?contains(CacheClusterId, 'c4ang')].{ID:CacheClusterId,Status:CacheClusterStatus,Engine:Engine}" \
        --output table 2>/dev/null || echo "  ElastiCache 없음"
}

# =============================================================================
# Main Actions
# =============================================================================

full_init() {
    log_header "프로덕션 환경 전체 초기화"

    check_prerequisites

    # Phase 1: Terraform
    terraform_init
    terraform_plan

    echo ""
    read -p "Terraform plan을 적용하시겠습니까? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        terraform_apply
    else
        log_info "Terraform apply를 건너뜁니다."
        log_info "나중에 적용하려면: $0 --apply"
    fi

    # Phase 2: EKS
    connect_eks

    # Phase 3: ArgoCD
    bootstrap_argocd

    log_header "초기화 완료"
    show_status
}

usage() {
    cat << EOF
AWS 프로덕션 환경 관리 스크립트

사용법: $0 [옵션]

옵션:
  (없음)          전체 환경 초기화
  --plan          Terraform plan만 실행
  --apply         Terraform apply만 실행
  --connect       EKS 연결만 설정
  --bootstrap     ArgoCD bootstrap만 실행
  --status        현재 상태 확인
  --destroy       환경 삭제 (주의!)
  --help          도움말

전체 플로우:
  1. External Services (Terraform)
     - RDS PostgreSQL (5개)
     - ElastiCache Redis (2개)
     - MSK Kafka (선택적)

  2. EKS 클러스터 연결
     - kubeconfig 설정
     - 네임스페이스 생성

  3. ArgoCD Bootstrap
     - App of Apps 패턴
     - ApplicationSet으로 환경별 자동 배포

사전 요구사항:
  - AWS CLI 설정 (aws configure)
  - c4ang-terraform으로 VPC, EKS 생성 완료
  - external-services/aws/terraform.tfvars 설정

예시:
  $0                 # 전체 환경 구축
  $0 --plan          # Terraform 계획 확인
  $0 --apply         # Terraform 적용
  $0 --status        # 상태 확인
  $0 --destroy       # 환경 삭제

환경 변수:
  AWS_REGION          AWS 리전 (기본: ap-northeast-2)
  EKS_CLUSTER_NAME    EKS 클러스터 이름 (기본: c4ang-prod-eks)

EOF
}

# =============================================================================
# Main
# =============================================================================

main() {
    local action="init"

    while [[ $# -gt 0 ]]; do
        case $1 in
            --plan) action="plan"; shift ;;
            --apply) action="apply"; shift ;;
            --connect) action="connect"; shift ;;
            --bootstrap) action="bootstrap"; shift ;;
            --status) action="status"; shift ;;
            --destroy) action="destroy"; shift ;;
            --help|-h) usage; exit 0 ;;
            *) log_error "알 수 없는 옵션: $1"; usage; exit 1 ;;
        esac
    done

    case $action in
        init)
            full_init
            ;;
        plan)
            check_prerequisites
            terraform_init
            terraform_plan
            ;;
        apply)
            check_prerequisites
            terraform_apply
            ;;
        connect)
            check_prerequisites
            connect_eks
            ;;
        bootstrap)
            bootstrap_argocd
            ;;
        status)
            show_status
            ;;
        destroy)
            check_prerequisites
            terraform_destroy
            ;;
    esac
}

main "$@"
