#!/bin/bash
set -euo pipefail

# 설정
AWS_REGION="ap-northeast-2"
AWS_ACCOUNT_ID="963403601423"
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
IMAGE_NAME="kafka-connect-s3"
IMAGE_TAG="latest"
FULL_IMAGE_NAME="${ECR_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

echo "🚀 Building Kafka Connect S3 image..."
echo "   Image: ${FULL_IMAGE_NAME}"
echo

# ECR 레지스트리 생성
echo "📌 Creating ECR repository if not exists..."
aws ecr describe-repositories --repository-names ${IMAGE_NAME} --region ${AWS_REGION} >/dev/null 2>&1 || \
aws ecr create-repository --repository-name ${IMAGE_NAME} --region ${AWS_REGION}

# ECR 로그인
echo "📌 Logging in to ECR..."
aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${ECR_REGISTRY}

# 이미지 빌드 (linux/amd64 플랫폼)
echo "📌 Building Docker image (linux/amd64)..."
docker build --platform linux/amd64 -t ${IMAGE_NAME}:${IMAGE_TAG} -f Dockerfile .

# 이미지 태깅
echo "📌 Tagging image..."
docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${FULL_IMAGE_NAME}

# 이미지 푸시
echo "📌 Pushing image to ECR..."
docker push ${FULL_IMAGE_NAME}

echo
echo "✅ Image built and pushed successfully!"
echo "   Image: ${FULL_IMAGE_NAME}"
echo
echo "📝 Update values.yaml:"
echo "   build:"
echo "     enabled: false  # or true to use Strimzi build"
echo "   image: ${FULL_IMAGE_NAME}"

