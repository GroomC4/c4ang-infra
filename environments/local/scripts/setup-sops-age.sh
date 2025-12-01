#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
SOPS_CONFIG="${PROJECT_ROOT}/.sops.yaml"
AGE_KEY_DIR="${HOME}/.config/sops/age"
AGE_KEY_FILE="${AGE_KEY_DIR}/keys.txt"

echo "🔐 SOPS Age 키 설정 스크립트"
echo "=================================="
echo ""

# Age 설치 확인
if ! command -v age &> /dev/null; then
    echo "❌ age가 설치되어 있지 않습니다."
    echo "설치 방법:"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "  brew install age"
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo "  sudo apt-get install age  # 또는 해당 배포판의 패키지 매니저 사용"
    else
        echo "  https://github.com/FiloSottile/age 를 참고하여 설치하세요."
    fi
    exit 1
fi

# SOPS 설치 확인
if ! command -v sops &> /dev/null; then
    echo "❌ sops가 설치되어 있지 않습니다."
    echo "설치 방법:"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "  brew install sops"
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo "  sudo apt-get install sops  # 또는 해당 배포판의 패키지 매니저 사용"
    else
        echo "  https://github.com/mozilla/sops 를 참고하여 설치하세요."
    fi
    exit 1
fi

# Age 키 디렉토리 생성
mkdir -p "${AGE_KEY_DIR}"

# Age 키 생성 (이미 있으면 스킵)
if [ ! -f "${AGE_KEY_FILE}" ]; then
    echo "🔑 Age 키 생성 중..."
    age-keygen -o "${AGE_KEY_FILE}"
    echo "✅ Age 키가 생성되었습니다: ${AGE_KEY_FILE}"
else
    echo "ℹ️  Age 키가 이미 존재합니다: ${AGE_KEY_FILE}"
fi

# Age 공개 키 추출
AGE_PUBLIC_KEY=$(grep "public key:" "${AGE_KEY_FILE}" | cut -d' ' -f4)
if [ -z "${AGE_PUBLIC_KEY}" ]; then
    echo "❌ Age 공개 키를 추출할 수 없습니다."
    exit 1
fi

echo "공개 키: ${AGE_PUBLIC_KEY}"
echo ""

# .sops.yaml 생성
echo "📝 .sops.yaml 생성 중..."
cat > "${SOPS_CONFIG}" <<EOF
creation_rules:
  - path_regex: .*secrets\.enc\.yaml$
    age: ${AGE_PUBLIC_KEY}
EOF

echo "✅ .sops.yaml이 생성되었습니다: ${SOPS_CONFIG}"
echo ""
echo "다음 단계:"
echo "1. 시크릿 파일 생성:"
echo "   cp values/postgresql.secrets.yaml.example values/postgresql.secrets.yaml"
echo ""
echo "2. 시크릿 파일 편집:"
echo "   vi values/postgresql.secrets.yaml"
echo ""
echo "3. 시크릿 파일 암호화:"
echo "   sops -e values/postgresql.secrets.yaml > values/postgresql.secrets.enc.yaml"
echo ""
echo "4. 암호화된 파일 편집 (자동 복호화/암호화):"
echo "   sops values/postgresql.secrets.enc.yaml"
echo ""

