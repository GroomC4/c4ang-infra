#!/bin/bash
# 외부 데이터 서비스 종료 스크립트
#
# 사용법:
#   ./stop.sh           # 서비스 종료 (볼륨 유지)
#   ./stop.sh --clean   # 서비스 종료 + 볼륨 삭제

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

# 색상 정의
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

case "${1:-}" in
    --clean)
        log_warn "서비스 종료 및 볼륨 삭제"
        docker-compose down -v
        ;;
    *)
        log_info "서비스 종료 (볼륨 유지)"
        docker-compose down
        ;;
esac

log_info "완료"
