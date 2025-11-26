#!/bin/bash

# Infracost 비용 계산 스크립트
# Terraform 코드를 분석하여 예상 비용을 계산합니다.

set -e

# 색상 정의
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "💰 Infracost 비용 분석을 시작합니다..."

# API 키 확인
if [ -z "$INFRACOST_API_KEY" ]; then
    echo -e "${RED}❌ INFRACOST_API_KEY 환경 변수가 설정되어 있지 않습니다.${NC}"
    echo ""
    echo "다음 명령어로 API 키를 설정하세요:"
    echo "  export INFRACOST_API_KEY=your_api_key"
    echo ""
    echo "또는 .env.infracost 파일을 로드하세요:"
    echo "  source .env.infracost"
    echo ""
    exit 1
fi

# Infracost 설치 확인
if ! command -v infracost &> /dev/null; then
    echo -e "${RED}❌ Infracost가 설치되어 있지 않습니다.${NC}"
    echo ""
    echo "설치 방법:"
    echo "  brew install infracost"
    echo "  또는"
    echo "  ./scripts/infracost-setup.sh"
    echo ""
    exit 1
fi

# 변수 파일 선택
VAR_FILE="${1:-only-rds.tfvars}"

if [ ! -f "$VAR_FILE" ]; then
    echo -e "${YELLOW}⚠️  변수 파일 '$VAR_FILE'을 찾을 수 없습니다.${NC}"
    echo "기본 변수 파일을 사용합니다."
    VAR_FILE=""
fi

# 현재 디렉토리 확인
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

echo ""
echo "📁 프로젝트 디렉토리: $PROJECT_DIR"
if [ -n "$VAR_FILE" ]; then
    echo "📄 변수 파일: $VAR_FILE"
fi
echo ""

# Infracost 실행
if [ -n "$VAR_FILE" ]; then
    echo -e "${GREEN}비용 분석 중...${NC}"
    infracost breakdown \
        --path . \
        --terraform-var-file="$VAR_FILE" \
        --format table \
        --show-skipped
else
    echo -e "${GREEN}비용 분석 중...${NC}"
    infracost breakdown \
        --path . \
        --format table \
        --show-skipped
fi

echo ""
echo -e "${GREEN}✅ 비용 분석이 완료되었습니다!${NC}"
echo ""
echo "추가 옵션:"
echo "  # JSON 형식으로 출력:"
echo "  infracost breakdown --path . --format json"
echo ""
echo "  # HTML 리포트 생성:"
echo "  infracost breakdown --path . --format html > cost-report.html"
echo ""
echo "  # Diff 비교 (변경사항 비용):"
echo "  infracost diff --path . --terraform-var-file=$VAR_FILE"
echo ""

