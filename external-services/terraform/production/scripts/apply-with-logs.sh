#!/bin/bash
# Terraform apply with detailed logging

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$TERRAFORM_DIR"

# 색상 정의
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Terraform Apply 시작${NC}"
echo -e "${BLUE}📁 작업 디렉토리: $TERRAFORM_DIR${NC}"
echo ""

# 로그 파일 설정
LOG_FILE="/tmp/terraform_apply_$(date +%Y%m%d_%H%M%S).log"

echo -e "${YELLOW}📝 로그 파일: $LOG_FILE${NC}"
echo ""

# Plan 먼저 실행
echo -e "${BLUE}📋 1. 실행 계획 확인 중...${NC}"
terraform plan -out=tfplan > "$LOG_FILE.plan" 2>&1

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Plan 실패${NC}"
    cat "$LOG_FILE.plan"
    exit 1
fi

echo -e "${GREEN}✅ Plan 완료${NC}"
echo ""

# Plan 요약 표시
echo -e "${BLUE}📊 Plan 요약:${NC}"
terraform show -no-color tfplan | grep -E "^Plan:|will be created|will be destroyed|will be replaced|will be updated" | head -20
echo ""

# 사용자 확인
read -p "$(echo -e ${YELLOW}계속 진행하시겠습니까? [y/N]: ${NC})" -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}취소되었습니다.${NC}"
    rm -f tfplan
    exit 0
fi

echo ""
echo -e "${BLUE}🚀 2. Apply 실행 중...${NC}"
echo -e "${YELLOW}💡 팁: Ctrl+C로 중단할 수 있습니다 (일부 리소스는 이미 생성될 수 있음)${NC}"
echo ""

# Apply 실행 (로그 파일에도 저장하면서 실시간 출력)
terraform apply tfplan 2>&1 | tee "$LOG_FILE"

APPLY_EXIT_CODE=${PIPESTATUS[0]}

echo ""
echo "=========================================="

if [ $APPLY_EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}✅ Apply 성공!${NC}"
    echo ""
    echo -e "${BLUE}📝 전체 로그: $LOG_FILE${NC}"
    
    # MSK 관련 출력 확인
    if grep -q "aws_msk_cluster" "$LOG_FILE"; then
        echo ""
        echo -e "${BLUE}📊 MSK 클러스터 정보:${NC}"
        terraform output msk_cluster_arn 2>/dev/null || echo "MSK 클러스터 ARN 확인 중..."
        terraform output msk_bootstrap_brokers 2>/dev/null || echo "Bootstrap Brokers 확인 중..."
    fi
else
    echo -e "${RED}❌ Apply 실패${NC}"
    echo ""
    echo -e "${BLUE}📝 에러 로그: $LOG_FILE${NC}"
    echo ""
    echo -e "${YELLOW}마지막 50줄:${NC}"
    tail -50 "$LOG_FILE"
    exit 1
fi

# Plan 파일 정리
rm -f tfplan

echo ""
echo -e "${GREEN}✅ 완료!${NC}"

