#!/bin/bash
# 기존 S3 버킷 import 스크립트

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$TERRAFORM_DIR"

BUCKET_NAME="c4-tracking-log"

echo "🔧 기존 S3 버킷 Import: $BUCKET_NAME"
echo ""

# 버킷 존재 확인
if ! aws s3 ls "s3://$BUCKET_NAME" &>/dev/null; then
    echo "❌ 버킷이 존재하지 않습니다: $BUCKET_NAME"
    echo "   새로 생성됩니다."
    exit 0
fi

echo "✅ 기존 버킷 확인됨: $BUCKET_NAME"
echo ""

# Import 실행
echo "📥 Terraform 상태에 추가 중..."

# 메인 버킷 리소스 import
if terraform import aws_s3_bucket.tracking_log[0] "$BUCKET_NAME" 2>/dev/null; then
    echo "✅ 버킷 import 성공"
else
    echo "⚠️  버킷 import 실패 (이미 존재하거나 다른 이유)"
fi

# 관련 리소스 import (있는 경우)
echo ""
echo "📥 관련 리소스 import 시도..."

terraform import aws_s3_bucket_versioning.tracking_log_versioning[0] "$BUCKET_NAME" 2>/dev/null && echo "✅ Versioning import 성공" || echo "⏭️  Versioning import 건너뜀"
terraform import aws_s3_bucket_server_side_encryption_configuration.tracking_log_encryption[0] "$BUCKET_NAME" 2>/dev/null && echo "✅ Encryption import 성공" || echo "⏭️  Encryption import 건너뜀"
terraform import aws_s3_bucket_public_access_block.tracking_log_pab[0] "$BUCKET_NAME" 2>/dev/null && echo "✅ Public Access Block import 성공" || echo "⏭️  Public Access Block import 건너뜀"

echo ""
echo "✅ Import 완료!"
echo ""
echo "다음 단계:"
echo "  terraform plan  # 변경사항 확인"
echo "  terraform apply # 적용"

