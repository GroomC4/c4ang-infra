# 멀티플랫폼 Docker 이미지 빌드 가이드

## 배경

로컬 개발 환경(k3d)에서 Apple Silicon Mac(arm64)을 사용하는 경우, 기존 linux/amd64로만 빌드된 이미지는 실행할 수 없습니다.

```
Failed to pull image: no match for platform in manifest: not found
```

이 문제를 해결하기 위해 Docker 이미지를 **멀티플랫폼**(linux/amd64, linux/arm64)으로 빌드해야 합니다.

## 요구사항

### 지원해야 할 플랫폼
- `linux/amd64`: EKS 프로덕션 환경, Intel Mac
- `linux/arm64`: Apple Silicon Mac 로컬 개발 환경

### 대상 서비스
- customer-service
- store-service
- order-service
- payment-service
- product-service
- recommendation-service

## 구현 방법

### 1. Docker Buildx 설정

Docker Buildx는 멀티플랫폼 빌드를 지원하는 Docker CLI 플러그인입니다.

```bash
# Buildx 빌더 생성 (최초 1회)
docker buildx create --name multiplatform-builder --use

# 빌더 시작
docker buildx inspect --bootstrap
```

### 2. Dockerfile 수정 (필요시)

베이스 이미지가 멀티플랫폼을 지원하는지 확인하세요.

```dockerfile
# 권장: 멀티플랫폼 지원 베이스 이미지
FROM eclipse-temurin:21-jre-alpine

# 또는
FROM amazoncorretto:21-alpine
```

> **참고**: `eclipse-temurin`, `amazoncorretto`, `openjdk` 공식 이미지는 대부분 멀티플랫폼을 지원합니다.

### 3. 멀티플랫폼 빌드 및 푸시

```bash
# ECR 로그인
aws ecr get-login-password --region ap-northeast-2 | \
  docker login --username AWS --password-stdin 963403601423.dkr.ecr.ap-northeast-2.amazonaws.com

# 멀티플랫폼 빌드 및 푸시
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --tag 963403601423.dkr.ecr.ap-northeast-2.amazonaws.com/c4ang-customer-service:v1.0.10 \
  --tag 963403601423.dkr.ecr.ap-northeast-2.amazonaws.com/c4ang-customer-service:latest \
  --push \
  .
```

### 4. GitHub Actions 워크플로우 예시

```yaml
name: Build and Push Multi-Platform Image

on:
  push:
    branches: [main]
    tags: ['v*']

env:
  AWS_REGION: ap-northeast-2
  ECR_REGISTRY: 963403601423.dkr.ecr.ap-northeast-2.amazonaws.com
  IMAGE_NAME: c4ang-customer-service

jobs:
  build:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up QEMU
        uses: docker/setup-qemu-action@v3

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ env.AWS_REGION }}

      - name: Login to Amazon ECR
        uses: aws-actions/amazon-ecr-login@v2

      - name: Extract version from tag
        id: version
        run: |
          if [[ "${{ github.ref }}" == refs/tags/* ]]; then
            VERSION=${GITHUB_REF#refs/tags/}
          else
            VERSION=latest
          fi
          echo "version=$VERSION" >> $GITHUB_OUTPUT

      - name: Build and push multi-platform image
        uses: docker/build-push-action@v5
        with:
          context: .
          platforms: linux/amd64,linux/arm64
          push: true
          tags: |
            ${{ env.ECR_REGISTRY }}/${{ env.IMAGE_NAME }}:${{ steps.version.outputs.version }}
            ${{ env.ECR_REGISTRY }}/${{ env.IMAGE_NAME }}:latest
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

## 빌드 확인

이미지가 멀티플랫폼으로 빌드되었는지 확인:

```bash
# 이미지 manifest 확인
docker manifest inspect 963403601423.dkr.ecr.ap-northeast-2.amazonaws.com/c4ang-customer-service:v1.0.10

# 또는 AWS CLI로 확인
aws ecr describe-images \
  --repository-name c4ang-customer-service \
  --image-ids imageTag=v1.0.10 \
  --query 'imageDetails[0].imageManifestMediaType'
```

멀티플랫폼 이미지는 `application/vnd.docker.distribution.manifest.list.v2+json` 또는 `application/vnd.oci.image.index.v1+json` 타입을 가집니다.

## 로컬 테스트

빌드 후 로컬에서 테스트:

```bash
# arm64 Mac에서 테스트
docker run --rm -it \
  963403601423.dkr.ecr.ap-northeast-2.amazonaws.com/c4ang-customer-service:v1.0.10 \
  --version

# 특정 플랫폼 지정 테스트
docker run --rm --platform linux/amd64 \
  963403601423.dkr.ecr.ap-northeast-2.amazonaws.com/c4ang-customer-service:v1.0.10 \
  --version
```

## 주의사항

1. **빌드 시간 증가**: 멀티플랫폼 빌드는 단일 플랫폼 대비 2배 정도 시간이 소요됩니다.

2. **QEMU 에뮬레이션**: GitHub Actions의 ubuntu-latest 러너는 amd64이므로, arm64 빌드 시 QEMU 에뮬레이션을 사용합니다. 네이티브 빌드보다 느릴 수 있습니다.

3. **캐시 활용**: `cache-from`과 `cache-to` 옵션을 사용하여 빌드 캐시를 활용하세요.

4. **베이스 이미지 호환성**: 사용하는 모든 베이스 이미지가 멀티플랫폼을 지원하는지 확인하세요.

## 관련 문서

- [Docker Buildx Documentation](https://docs.docker.com/buildx/working-with-buildx/)
- [GitHub Actions - docker/build-push-action](https://github.com/docker/build-push-action)
- [AWS ECR Multi-architecture Images](https://docs.aws.amazon.com/AmazonECR/latest/userguide/docker-push-multi-architecture-image.html)

## 문의

인프라 관련 문의: c4ang-infra 레포지토리 이슈 등록
