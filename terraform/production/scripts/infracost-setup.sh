#!/bin/bash

# Infracost 설치 및 설정 스크립트
# macOS용 설치 스크립트

set -e

echo "🚀 Infracost 설정을 시작합니다..."

# 1. Infracost 설치 확인
if command -v infracost &> /dev/null; then
    echo "✅ Infracost가 이미 설치되어 있습니다."
    infracost --version
else
    echo "📦 Infracost를 설치합니다..."
    
    # macOS용 설치 (Homebrew 사용)
    if [[ "$OSTYPE" == "darwin"* ]]; then
        if command -v brew &> /dev/null; then
            echo "Homebrew를 사용하여 설치합니다..."
            brew install infracost
        else
            echo "❌ Homebrew가 설치되어 있지 않습니다."
            echo "다음 명령어로 수동 설치하세요:"
            echo "brew install infracost"
            exit 1
        fi
    else
        echo "다른 운영체제의 경우 다음 명령어로 설치하세요:"
        echo "curl -fsSL https://raw.githubusercontent.com/infracost/infracost/master/scripts/install.sh | sh"
        exit 1
    fi
fi

# 2. API 키 확인
if [ -z "$INFRACOST_API_KEY" ]; then
    echo "⚠️  INFRACOST_API_KEY 환경 변수가 설정되어 있지 않습니다."
    echo ""
    echo "다음 단계를 수행하세요:"
    echo "1. https://www.infracost.io/ 에서 계정 생성"
    echo "2. API 키 발급"
    echo "3. 다음 명령어로 API 키 설정:"
    echo "   export INFRACOST_API_KEY=your_api_key"
    echo ""
    echo "또는 .env.infracost 파일을 생성하세요:"
    echo "   cp .env.infracost.example .env.infracost"
    echo "   # .env.infracost 파일을 편집하여 API 키 입력"
    echo "   source .env.infracost"
    echo ""
else
    echo "✅ INFRACOST_API_KEY가 설정되어 있습니다."
fi

# 3. 설정 파일 확인
if [ ! -f ".infracost.yml" ]; then
    echo "⚠️  .infracost.yml 파일이 없습니다. 생성하세요."
else
    echo "✅ .infracost.yml 설정 파일이 있습니다."
fi

echo ""
echo "✅ 설정이 완료되었습니다!"
echo ""
echo "다음 명령어로 비용을 계산할 수 있습니다:"
echo "  infracost breakdown --path ."
echo ""
echo "변수 파일을 지정하려면:"
echo "  infracost breakdown --path . --terraform-var-file=only-rds.tfvars"
echo ""

