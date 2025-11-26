#!/bin/bash
# 시크릿 관리 스크립트 (SOPS + Age)
# Age 키 생성 및 SOPS 설정
#
# 사용법:
#   ./secrets.sh                    # Age 키 생성 및 SOPS 설정
#   ./secrets.sh --encrypt FILE     # 파일 암호화
#   ./secrets.sh --decrypt FILE     # 파일 복호화
#   ./secrets.sh --status           # 상태 확인

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
AGE_KEY_DIR="$HOME/.config/sops/age"
AGE_KEY_FILE="$AGE_KEY_DIR/keys.txt"
SOPS_CONFIG="${PROJECT_ROOT}/.sops.yaml"

# 로그 함수
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Age 설치 확인
check_age() {
    if ! command -v age &> /dev/null; then
        log_error "Age가 설치되어 있지 않습니다."
        log_info "설치 방법:"
        echo "  macOS: brew install age"
        echo "  Linux: curl -LO https://github.com/FiloSottile/age/releases/latest/download/age-v1.1.1-linux-amd64.tar.gz"
        exit 1
    fi
    log_success "Age: $(age --version)"
}

# SOPS 설치 확인
check_sops() {
    if ! command -v sops &> /dev/null; then
        log_error "SOPS가 설치되어 있지 않습니다."
        log_info "설치 방법:"
        echo "  macOS: brew install sops"
        echo "  Linux: https://github.com/mozilla/sops/releases"
        exit 1
    fi
    log_success "SOPS: $(sops --version)"
}

# 사전 체크
check_prerequisites() {
    log_info "사전 요구사항 확인 중..."
    check_age
    check_sops
    log_success "사전 요구사항 확인 완료"
}

# Age 키 생성
create_age_key() {
    log_info "=== Age 키 설정 ==="

    # 디렉토리 생성
    mkdir -p "$AGE_KEY_DIR"

    # 키 존재 확인
    if [ -f "$AGE_KEY_FILE" ]; then
        log_warn "Age 키가 이미 존재합니다: $AGE_KEY_FILE"
        read -p "기존 키를 사용하시겠습니까? (Y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Nn]$ ]]; then
            log_info "새 키를 생성합니다."
            age-keygen -o "$AGE_KEY_FILE"
        fi
    else
        log_info "새 Age 키 생성: $AGE_KEY_FILE"
        age-keygen -o "$AGE_KEY_FILE"
    fi

    # 공개 키 추출
    local public_key
    public_key=$(grep "public key" "$AGE_KEY_FILE" | awk '{print $4}')

    if [ -z "$public_key" ]; then
        log_error "공개 키를 추출할 수 없습니다."
        exit 1
    fi

    echo ""
    log_success "Age 공개 키: $public_key"
    log_warn "개인 키는 안전하게 보관하세요!"
    echo ""

    # .sops.yaml 업데이트
    update_sops_config "$public_key"
}

# .sops.yaml 업데이트
update_sops_config() {
    local public_key=$1

    log_info ".sops.yaml 파일 업데이트 중..."

    if [ ! -f "$SOPS_CONFIG" ]; then
        log_warn ".sops.yaml 파일이 없습니다. 생성합니다."
        cat > "$SOPS_CONFIG" << EOF
creation_rules:
  # 로컬 환경 시크릿
  - path_regex: config/local/.*\.secrets\.yaml$
    age: '$public_key'

  # 테스트 환경 시크릿
  - path_regex: config/test/.*\.secrets\.yaml$
    age: '$public_key'

  # 프로덕션 환경 시크릿 (AWS KMS 사용 권장)
  - path_regex: config/prod/.*\.secrets\.yaml$
    age: '$public_key'
EOF
        log_success ".sops.yaml 파일 생성됨"
    else
        # 기존 파일에서 age 키 교체
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "s/age: 'age1[^']*'/age: '$public_key'/g" "$SOPS_CONFIG"
        else
            sed -i "s/age: 'age1[^']*'/age: '$public_key'/g" "$SOPS_CONFIG"
        fi
        log_success ".sops.yaml 파일 업데이트됨"
    fi
}

# 파일 암호화
encrypt_file() {
    local file=$1

    if [ ! -f "$file" ]; then
        log_error "파일을 찾을 수 없습니다: $file"
        exit 1
    fi

    local output="${file%.yaml}.enc.yaml"

    log_info "암호화 중: $file -> $output"
    sops -e "$file" > "$output"

    log_success "암호화 완료: $output"
    log_warn "원본 파일($file)은 안전하게 삭제하거나 .gitignore에 추가하세요."
}

# 파일 복호화
decrypt_file() {
    local file=$1

    if [ ! -f "$file" ]; then
        log_error "파일을 찾을 수 없습니다: $file"
        exit 1
    fi

    local output="${file%.enc.yaml}.yaml"

    log_info "복호화 중: $file -> $output"
    sops -d "$file" > "$output"

    log_success "복호화 완료: $output"
}

# 상태 확인
show_status() {
    echo ""
    log_info "=== 시크릿 관리 상태 ==="
    echo ""

    # Age 키 상태
    echo "Age 키:"
    if [ -f "$AGE_KEY_FILE" ]; then
        local public_key
        public_key=$(grep "public key" "$AGE_KEY_FILE" | awk '{print $4}')
        echo "  상태: 존재함"
        echo "  경로: $AGE_KEY_FILE"
        echo "  공개 키: $public_key"
    else
        echo "  상태: 없음"
        echo "  './secrets.sh'를 실행하여 생성하세요."
    fi
    echo ""

    # SOPS 설정
    echo ".sops.yaml 설정:"
    if [ -f "$SOPS_CONFIG" ]; then
        echo "  상태: 존재함"
        echo "  경로: $SOPS_CONFIG"
    else
        echo "  상태: 없음"
    fi
    echo ""

    # 암호화된 파일 목록
    echo "암호화된 시크릿 파일:"
    local enc_files
    enc_files=$(find "${PROJECT_ROOT}/config" -name "*.enc.yaml" 2>/dev/null || true)
    if [ -n "$enc_files" ]; then
        echo "$enc_files" | while read -r f; do
            echo "  - ${f#$PROJECT_ROOT/}"
        done
    else
        echo "  없음"
    fi
}

# 초기화 (Age 키 생성 + SOPS 설정)
initialize() {
    log_info "=== 시크릿 관리 초기화 ==="
    echo ""

    check_prerequisites
    create_age_key

    echo ""
    log_success "=== 초기화 완료 ==="
    echo ""
    log_info "다음 단계:"
    echo "1. 시크릿 파일 생성:"
    echo "   예: config/local/postgresql.secrets.yaml"
    echo ""
    echo "2. 시크릿 파일 암호화:"
    echo "   ./secrets.sh --encrypt config/local/postgresql.secrets.yaml"
    echo ""
    echo "3. 원본 파일 삭제 또는 .gitignore에 추가"
    echo ""
}

# 사용법
usage() {
    cat << EOF
사용법: $0 [옵션]

옵션:
  (없음)              Age 키 생성 및 SOPS 설정 초기화
  --encrypt FILE      파일 암호화 (.enc.yaml 생성)
  --decrypt FILE      파일 복호화
  --status            상태 확인
  --help              도움말

예시:
  $0                                           # 초기화
  $0 --encrypt config/local/secrets.yaml       # 암호화
  $0 --decrypt config/local/secrets.enc.yaml   # 복호화
  $0 --status                                  # 상태 확인

시크릿 파일 명명 규칙:
  - 평문: *.secrets.yaml
  - 암호화: *.secrets.enc.yaml

EOF
}

# 메인
main() {
    local action="init"
    local target_file=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --encrypt)
                action="encrypt"
                target_file="${2:-}"
                shift 2
                ;;
            --decrypt)
                action="decrypt"
                target_file="${2:-}"
                shift 2
                ;;
            --status)
                action="status"
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

    case $action in
        init) initialize ;;
        encrypt)
            if [ -z "$target_file" ]; then
                log_error "--encrypt 옵션에는 파일 경로가 필요합니다."
                exit 1
            fi
            check_prerequisites
            encrypt_file "$target_file"
            ;;
        decrypt)
            if [ -z "$target_file" ]; then
                log_error "--decrypt 옵션에는 파일 경로가 필요합니다."
                exit 1
            fi
            check_prerequisites
            decrypt_file "$target_file"
            ;;
        status) show_status ;;
    esac
}

main "$@"
