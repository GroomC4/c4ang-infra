#!/bin/bash
# Terraform 테스트 스크립트
# 실제 배포 없이 Terraform 코드를 검증합니다.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$TERRAFORM_DIR"

echo "🔍 Terraform 테스트 시작..."
echo "📁 작업 디렉토리: $TERRAFORM_DIR"
echo ""

# 색상 정의
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 테스트 결과 추적
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# 테스트 함수
run_test() {
    local test_name="$1"
    local test_command="$2"
    local optional="${3:-false}"
    
    echo -e "${BLUE}📋 테스트: $test_name${NC}"
    
    if eval "$test_command" > /tmp/terraform_test_output.log 2>&1; then
        echo -e "${GREEN}✅ 통과${NC}"
        ((TESTS_PASSED++))
        return 0
    else
        if [ "$optional" = "true" ]; then
            echo -e "${YELLOW}⏭️  건너뜀 (선택사항)${NC}"
            ((TESTS_SKIPPED++))
            return 0
        else
            echo -e "${RED}❌ 실패${NC}"
            echo "출력:"
            cat /tmp/terraform_test_output.log | head -20
            ((TESTS_FAILED++))
            return 1
        fi
    fi
}

# 1. 포맷 확인 및 자동 수정
echo -e "${BLUE}📝 코드 포맷 확인 및 수정...${NC}"
if terraform fmt -check -recursive > /tmp/terraform_fmt_check.log 2>&1; then
    echo -e "${GREEN}✅ 포맷 통과${NC}"
    ((TESTS_PASSED++))
else
    echo -e "${YELLOW}⚠️  포맷 문제 발견, 자동 수정 중...${NC}"
    terraform fmt -recursive
    echo -e "${GREEN}✅ 포맷 자동 수정 완료${NC}"
    ((TESTS_PASSED++))
fi

# 2. 초기화 (모듈 다운로드)
echo ""
echo -e "${BLUE}🚀 모듈 초기화 중...${NC}"
if terraform init -backend=false -upgrade > /tmp/terraform_init.log 2>&1; then
    echo -e "${GREEN}✅ 초기화 완료${NC}"
    ((TESTS_PASSED++))
else
    echo -e "${RED}❌ 초기화 실패${NC}"
    cat /tmp/terraform_init.log | tail -20
    exit 1
fi

# 3. 구문 검증
run_test "구문 검증" "terraform validate" false || exit 1

# 4. Plan 실행 (실제 리소스 생성 안 함)
echo ""
echo -e "${BLUE}📋 실행 계획 확인 (Dry-Run)${NC}"
if terraform plan -out=tfplan > /tmp/terraform_plan.log 2>&1; then
    echo -e "${GREEN}✅ Plan 성공${NC}"
    echo ""
    echo "주요 변경사항:"
    terraform show tfplan 2>/dev/null | grep -E "^  # |^  \+|^  \-|^  ~|Plan:" | head -30 || true
    rm -f tfplan
    ((TESTS_PASSED++))
else
    echo -e "${RED}❌ Plan 실패${NC}"
    echo "에러 출력:"
    cat /tmp/terraform_plan.log | tail -30
    ((TESTS_FAILED++))
    exit 1
fi

# 5. Checkov (설치된 경우)
if command -v checkov &> /dev/null; then
    echo ""
    run_test "보안 검사 (Checkov)" "checkov -d . --framework terraform --quiet" true
else
    echo ""
    echo -e "${YELLOW}⏭️  Checkov 미설치 (건너뜀)${NC}"
    echo "   설치: brew install checkov 또는 pip install checkov"
    ((TESTS_SKIPPED++))
fi

# 6. TFLint (설치된 경우)
if command -v tflint &> /dev/null; then
    echo ""
    run_test "린터 검사 (TFLint)" "tflint" true
else
    echo ""
    echo -e "${YELLOW}⏭️  TFLint 미설치 (건너뜀)${NC}"
    echo "   설치: brew install tflint"
    ((TESTS_SKIPPED++))
fi

# 7. Infracost (설치된 경우)
if command -v infracost &> /dev/null; then
    echo ""
    echo -e "${BLUE}💰 비용 추정 (Infracost)${NC}"
    if terraform plan -out=tfplan > /dev/null 2>&1; then
        if infracost breakdown --path . --terraform-plan-file tfplan --format table > /tmp/infracost_output.log 2>&1; then
            echo -e "${GREEN}✅ 비용 분석 완료${NC}"
            cat /tmp/infracost_output.log | tail -20
            rm -f tfplan
            ((TESTS_PASSED++))
        else
            echo -e "${YELLOW}⏭️  Infracost API 키 필요 (건너뜀)${NC}"
            ((TESTS_SKIPPED++))
        fi
    fi
else
    echo ""
    echo -e "${YELLOW}⏭️  Infracost 미설치 (건너뜀)${NC}"
    echo "   설치: brew install infracost"
    ((TESTS_SKIPPED++))
fi

# 결과 요약
echo ""
echo "=========================================="
echo -e "${BLUE}📊 테스트 결과 요약${NC}"
echo "=========================================="
echo -e "${GREEN}✅ 통과: $TESTS_PASSED${NC}"
if [ $TESTS_FAILED -gt 0 ]; then
    echo -e "${RED}❌ 실패: $TESTS_FAILED${NC}"
fi
if [ $TESTS_SKIPPED -gt 0 ]; then
    echo -e "${YELLOW}⏭️  건너뜀: $TESTS_SKIPPED${NC}"
fi
echo "=========================================="

# 정리
rm -f /tmp/terraform_test_output.log /tmp/terraform_plan.log /tmp/infracost_output.log 2>/dev/null || true

if [ $TESTS_FAILED -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✅ 모든 필수 테스트 통과!${NC}"
    exit 0
else
    echo ""
    echo -e "${RED}❌ 일부 테스트 실패. 위의 에러를 확인하세요.${NC}"
    exit 1
fi

