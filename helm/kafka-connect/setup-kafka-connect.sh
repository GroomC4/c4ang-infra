#!/bin/bash
set -euo pipefail

#################################
# 설정 (환경 변수로 덮어쓸 수 있음)
#################################
KAFKA_NS="${KAFKA_NS:-kafka}"
AWS_REGION="${AWS_REGION:-ap-northeast-2}"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-963403601423}"
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
IMAGE_NAME="${IMAGE_NAME:-kafka-connect-s3}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
FULL_IMAGE_NAME="${ECR_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

# 스크립트 디렉토리 찾기
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# values.yaml에서 ServiceAccount 정보 읽기
VALUES_FILE="${SCRIPT_DIR}/values.yaml"
serviceAccountName=$(grep "^serviceAccountName:" "${VALUES_FILE}" 2>/dev/null | awk '{print $2}' || echo "c4-kafka-connect-connect")
serviceAccountArn=$(grep "^serviceAccountArn:" "${VALUES_FILE}" 2>/dev/null | awk '{print $2}' || echo "arn:aws:iam::${AWS_ACCOUNT_ID}:role/eksctl-c4-eks-cluster-addon-iamserviceaccount-Role1-YQcLCkIlCmbK")

# 색상 출력
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 에러 핸들러
error_exit() {
  echo -e "${RED}❌ 오류 발생: $1${NC}" >&2
  exit 1
}

# 필수 도구 확인
check_requirements() {
  echo -e "${BLUE}📌 필수 도구 확인 중...${NC}"
  
  command -v aws >/dev/null 2>&1 || error_exit "AWS CLI가 설치되어 있지 않습니다."
  command -v docker >/dev/null 2>&1 || error_exit "Docker가 설치되어 있지 않습니다."
  command -v kubectl >/dev/null 2>&1 || error_exit "kubectl이 설치되어 있지 않습니다."
  command -v helm >/dev/null 2>&1 || error_exit "Helm이 설치되어 있지 않습니다."
  command -v jq >/dev/null 2>&1 || error_exit "jq가 설치되어 있지 않습니다. (brew install jq 또는 apt-get install jq)"
  
  # AWS 자격 증명 확인
  aws sts get-caller-identity >/dev/null 2>&1 || error_exit "AWS 자격 증명이 설정되어 있지 않습니다."
  
  # Kubernetes 클러스터 연결 확인
  kubectl cluster-info >/dev/null 2>&1 || error_exit "Kubernetes 클러스터에 연결할 수 없습니다."
  
  echo -e "${GREEN}✅ 모든 필수 도구가 준비되었습니다.${NC}"
  echo
}

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Kafka Connect with S3 Sink Connector 자동 설치 스크립트  ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo
echo -e "${BLUE}📋 설정 정보:${NC}"
echo "   Namespace: ${KAFKA_NS}"
echo "   AWS Region: ${AWS_REGION}"
echo "   AWS Account ID: ${AWS_ACCOUNT_ID}"
echo "   Image: ${FULL_IMAGE_NAME}"
echo "   ServiceAccount: ${serviceAccountName}"
echo "   IAM Role: ${serviceAccountArn}"
echo

# 필수 도구 확인
check_requirements

#################################
# 1) ECR 레지스트리 생성
#################################
echo -e "${BLUE}📌 [1/7] ECR 레지스트리 생성 중...${NC}"
if aws ecr describe-repositories --repository-names ${IMAGE_NAME} --region ${AWS_REGION} >/dev/null 2>&1; then
  echo -e "${YELLOW}⚠️  ECR 레지스트리가 이미 존재합니다: ${IMAGE_NAME}${NC}"
else
  aws ecr create-repository \
    --repository-name ${IMAGE_NAME} \
    --region ${AWS_REGION} \
    --image-scanning-configuration scanOnPush=true \
    --encryption-configuration encryptionType=AES256 \
    || error_exit "ECR 레지스트리 생성 실패"
  echo -e "${GREEN}✅ ECR 레지스트리 생성 완료${NC}"
fi
echo

#################################
# 2) ECR 로그인
#################################
echo -e "${BLUE}📌 [2/7] ECR 로그인 중...${NC}"
aws ecr get-login-password --region ${AWS_REGION} | \
  docker login --username AWS --password-stdin ${ECR_REGISTRY} \
  || error_exit "ECR 로그인 실패"

echo -e "${GREEN}✅ ECR 로그인 완료${NC}"
echo

#################################
# 3) Docker 이미지 빌드 (linux/amd64 플랫폼)
#################################
echo -e "${BLUE}📌 [3/7] Docker 이미지 빌드 중 (linux/amd64)...${NC}"
echo "   Dockerfile: ${SCRIPT_DIR}/Dockerfile"

if [ ! -f "${SCRIPT_DIR}/Dockerfile" ]; then
  error_exit "Dockerfile을 찾을 수 없습니다: ${SCRIPT_DIR}/Dockerfile"
fi

cd "${SCRIPT_DIR}"

# 이미지가 이미 ECR에 있는지 확인 (선택적 스킵)
SKIP_BUILD=false
if docker manifest inspect ${FULL_IMAGE_NAME} >/dev/null 2>&1; then
  echo -e "${YELLOW}⚠️  이미지가 이미 ECR에 존재합니다: ${FULL_IMAGE_NAME}${NC}"
  echo -e "${YELLOW}   이미지를 다시 빌드하려면 환경 변수 FORCE_REBUILD=true를 설정하세요.${NC}"
  if [ "${FORCE_REBUILD:-false}" != "true" ]; then
    echo -e "${YELLOW}   이미지 빌드를 건너뜁니다...${NC}"
    SKIP_BUILD=true
  fi
fi

if [ "${SKIP_BUILD}" = "false" ]; then
  docker build \
    --platform linux/amd64 \
    -t ${IMAGE_NAME}:${IMAGE_TAG} \
    -f Dockerfile . \
    || error_exit "Docker 이미지 빌드 실패"
  
  echo -e "${GREEN}✅ Docker 이미지 빌드 완료${NC}"
else
  echo -e "${GREEN}✅ 이미지 빌드 건너뜀 (이미 존재)${NC}"
fi
echo

#################################
# 4) 이미지 태깅 및 ECR에 푸시
#################################
if [ "${SKIP_BUILD}" = "false" ]; then
  echo -e "${BLUE}📌 [4/7] 이미지 태깅 및 ECR에 푸시 중...${NC}"
  docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${FULL_IMAGE_NAME} \
    || error_exit "이미지 태깅 실패"

  docker push ${FULL_IMAGE_NAME} \
    || error_exit "이미지 푸시 실패"

  echo -e "${GREEN}✅ 이미지 푸시 완료${NC}"
  echo "   Image: ${FULL_IMAGE_NAME}"
else
  echo -e "${BLUE}📌 [4/7] 이미지 푸시 건너뜀 (이미 ECR에 존재)${NC}"
  echo "   Image: ${FULL_IMAGE_NAME}"
fi
echo

#################################
# 5) values.yaml 업데이트
#################################
echo -e "${BLUE}📌 [5/7] values.yaml 업데이트 중...${NC}"
VALUES_FILE="${SCRIPT_DIR}/values.yaml"

# values.yaml이 존재하는지 확인
if [ ! -f "${VALUES_FILE}" ]; then
  error_exit "values.yaml 파일을 찾을 수 없습니다: ${VALUES_FILE}"
fi

# 임시 파일 생성
TMP_VALUES=$(mktemp)
cp "${VALUES_FILE}" "${TMP_VALUES}"

# image 값을 업데이트 (sed를 사용하여 안전하게 업데이트)
if grep -q "^image:" "${TMP_VALUES}"; then
  # 기존 image 라인이 있으면 업데이트
  if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    sed -i '' "s|^image:.*|image: ${FULL_IMAGE_NAME}|" "${TMP_VALUES}"
  else
    # Linux
    sed -i "s|^image:.*|image: ${FULL_IMAGE_NAME}|" "${TMP_VALUES}"
  fi
else
  # image 라인이 없으면 추가
  echo "image: ${FULL_IMAGE_NAME}" >> "${TMP_VALUES}"
fi

# build.outputImage도 업데이트
if grep -q "outputImage:" "${TMP_VALUES}"; then
  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "s|outputImage:.*|outputImage: ${FULL_IMAGE_NAME}|" "${TMP_VALUES}"
  else
    sed -i "s|outputImage:.*|outputImage: ${FULL_IMAGE_NAME}|" "${TMP_VALUES}"
  fi
fi

# 원본 파일에 덮어쓰기
mv "${TMP_VALUES}" "${VALUES_FILE}"

echo -e "${GREEN}✅ values.yaml 업데이트 완료${NC}"
echo

#################################
# 5.5) IAM 역할 Trust Policy 확인 및 업데이트 (IRSA)
#################################
echo -e "${BLUE}📌 [5.5/7] IAM 역할 Trust Policy 확인 중...${NC}"

# IAM 역할 이름 추출 (ARN에서)
IAM_ROLE_NAME=$(echo ${serviceAccountArn} | awk -F'/' '{print $NF}')

# OIDC Provider ID 가져오기 (EKS 클러스터에서)
# EKS 클러스터 이름 찾기 (kubectl context에서 또는 환경 변수에서)
EKS_CLUSTER_NAME="${EKS_CLUSTER_NAME:-$(kubectl config view --minify -o jsonpath='{.clusters[0].name}' 2>/dev/null | sed 's|.*/||' || echo "")}"

if [ -z "${EKS_CLUSTER_NAME}" ]; then
  # kubectl context에서 추출 시도
  CURRENT_CONTEXT=$(kubectl config current-context 2>/dev/null || echo "")
  if [[ "${CURRENT_CONTEXT}" == *"/"* ]]; then
    EKS_CLUSTER_NAME=$(echo "${CURRENT_CONTEXT}" | cut -d'/' -f2)
  else
    EKS_CLUSTER_NAME="${CURRENT_CONTEXT}"
  fi
fi

OIDC_PROVIDER=$(aws eks describe-cluster --name "${EKS_CLUSTER_NAME}" --region ${AWS_REGION} --query 'cluster.identity.oidc.issuer' --output text 2>/dev/null | sed 's|https://||' || echo "")

if [ -n "${OIDC_PROVIDER}" ]; then
  OIDC_ID=$(echo ${OIDC_PROVIDER} | awk -F'/' '{print $NF}')
  OIDC_PROVIDER_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER}"
  
  echo "   OIDC Provider: ${OIDC_PROVIDER_ARN}"
  echo "   ServiceAccount: ${KAFKA_NS}/${serviceAccountName}"
  
  # 현재 trust policy 확인
  CURRENT_POLICY=$(aws iam get-role --role-name ${IAM_ROLE_NAME} --query 'Role.AssumeRolePolicyDocument' --output json 2>/dev/null)
  
  if [ -n "${CURRENT_POLICY}" ]; then
    # ServiceAccount 서브젝트 확인
    EXPECTED_SUBJECT="system:serviceaccount:${KAFKA_NS}:${serviceAccountName}"
    CURRENT_SUBJECT=$(echo ${CURRENT_POLICY} | jq -r '.Statement[0].Condition.StringEquals | to_entries[] | select(.key | contains("sub")) | .value' 2>/dev/null || echo "")
    
    if [ "${CURRENT_SUBJECT}" != "${EXPECTED_SUBJECT}" ]; then
      echo -e "${YELLOW}⚠️  IAM 역할 Trust Policy의 ServiceAccount가 일치하지 않습니다.${NC}"
      echo "   현재: ${CURRENT_SUBJECT}"
      echo "   예상: ${EXPECTED_SUBJECT}"
      echo -e "${YELLOW}   Trust Policy를 업데이트합니다...${NC}"
      
      # Trust Policy 생성
      TRUST_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "${OIDC_PROVIDER_ARN}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${OIDC_PROVIDER}:aud": "sts.amazonaws.com",
          "${OIDC_PROVIDER}:sub": "${EXPECTED_SUBJECT}"
        }
      }
    }
  ]
}
EOF
)
      
      echo "${TRUST_POLICY}" > /tmp/trust-policy.json
      aws iam update-assume-role-policy \
        --role-name ${IAM_ROLE_NAME} \
        --policy-document file:///tmp/trust-policy.json \
        || echo -e "${YELLOW}⚠️  Trust Policy 업데이트 실패 (수동으로 확인 필요)${NC}"
      
      echo -e "${GREEN}✅ Trust Policy 업데이트 완료${NC}"
    else
      echo -e "${GREEN}✅ Trust Policy가 올바르게 설정되어 있습니다.${NC}"
    fi
  else
    echo -e "${YELLOW}⚠️  IAM 역할을 찾을 수 없습니다: ${IAM_ROLE_NAME}${NC}"
    echo "   Trust Policy는 수동으로 설정해야 합니다."
  fi
else
  echo -e "${YELLOW}⚠️  OIDC Provider를 찾을 수 없습니다. Trust Policy는 수동으로 확인하세요.${NC}"
fi

echo

#################################
# 6) Helm으로 Kafka Connect 배포 (KafkaConnector 포함)
#################################
echo -e "${BLUE}📌 [6/7] Helm으로 Kafka Connect 배포 중 (KafkaConnector 포함)...${NC}"
cd "${PROJECT_ROOT}"

# Namespace 확인
kubectl get namespace ${KAFKA_NS} >/dev/null 2>&1 || {
  echo -e "${YELLOW}⚠️  Namespace ${KAFKA_NS}가 존재하지 않습니다. 생성 중...${NC}"
  kubectl create namespace ${KAFKA_NS} || error_exit "Namespace 생성 실패"
}

# Helm Chart 디렉토리 확인
if [ ! -d "./helm/kafka-connect" ]; then
  error_exit "Helm Chart 디렉토리를 찾을 수 없습니다: ./helm/kafka-connect"
fi

# Helm 배포 (KafkaConnector도 함께 배포됨)
echo "   Helm Chart: ./helm/kafka-connect"
echo "   Namespace: ${KAFKA_NS}"
echo

helm upgrade --install kafka-connect ./helm/kafka-connect \
  -n ${KAFKA_NS} \
  --create-namespace \
  --timeout 10m \
  || error_exit "Helm 배포 실패"

echo -e "${GREEN}✅ Helm 배포 완료${NC}"
echo -e "${YELLOW}   ⏳ Kafka Connect 파드가 시작될 때까지 잠시 기다립니다...${NC}"
sleep 15
echo

#################################
# 7) Kafka Connect가 준비될 때까지 대기
#################################
echo -e "${BLUE}📌 [7/7] Kafka Connect 파드가 준비될 때까지 대기 중...${NC}"
if kubectl wait --for=condition=ready pod \
  -l strimzi.io/name=c4-kafka-connect-connect \
  -n ${KAFKA_NS} \
  --timeout=10m 2>/dev/null; then
  echo -e "${GREEN}✅ Kafka Connect 파드 준비 완료${NC}"
else
  echo -e "${YELLOW}⚠️  파드가 준비되지 않았습니다. 상태 확인 중...${NC}"
  kubectl get pods -n ${KAFKA_NS} -l strimzi.io/name=c4-kafka-connect-connect
  echo
  echo -e "${YELLOW}최근 로그:${NC}"
  kubectl logs -n ${KAFKA_NS} -l strimzi.io/name=c4-kafka-connect-connect --tail=50 || true
  echo
  echo -e "${YELLOW}⚠️  파드가 아직 준비되지 않았지만 계속 진행합니다...${NC}"
fi
echo

#################################
# 8) KafkaConnector 상태 확인 (Helm으로 자동 배포됨)
#################################
echo -e "${BLUE}📌 S3 Sink Connector 상태 확인 중...${NC}"
sleep 20

# Connector가 존재하는지 확인
if kubectl get kafkaconnector s3-sink-connector -n ${KAFKA_NS} >/dev/null 2>&1; then
  echo -e "${YELLOW}⏳ S3 Sink Connector가 준비될 때까지 대기 중...${NC}"
  if kubectl wait --for=condition=ready kafkaconnector \
    s3-sink-connector \
    -n ${KAFKA_NS} \
    --timeout=5m 2>/dev/null; then
    echo -e "${GREEN}✅ S3 Sink Connector 준비 완료${NC}"
  else
    echo -e "${YELLOW}⚠️  Connector가 준비되지 않았습니다. 상태 확인 중...${NC}"
    kubectl describe kafkaconnector s3-sink-connector -n ${KAFKA_NS} | tail -30
    echo
    echo -e "${YELLOW}⚠️  Connector가 아직 준비되지 않았지만 계속 진행합니다...${NC}"
  fi
else
  echo -e "${YELLOW}⚠️  S3 Sink Connector가 아직 생성되지 않았습니다.${NC}"
  echo "   values.yaml에서 connector.enabled=true로 설정되어 있는지 확인하세요."
fi

echo

#################################
# 9) 최종 상태 확인
#################################
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                    배포 상태 확인                          ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo

echo -e "${BLUE}📌 Kafka Connect Pods:${NC}"
kubectl get pods -n ${KAFKA_NS} -l strimzi.io/name=c4-kafka-connect-connect

echo
echo -e "${BLUE}📌 Kafka Connect Status:${NC}"
kubectl get kafkaconnect -n ${KAFKA_NS}

echo
echo -e "${BLUE}📌 S3 Sink Connector Status:${NC}"
kubectl get kafkaconnector -n ${KAFKA_NS} 2>/dev/null || echo "   (아직 생성되지 않았습니다)"

echo
echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║          ✅ 모든 배포가 완료되었습니다!                     ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo
echo -e "${BLUE}📝 유용한 명령어:${NC}"
echo "   # 파드 상태 확인"
echo "   kubectl get pods -n ${KAFKA_NS} -l strimzi.io/name=c4-kafka-connect-connect"
echo
echo "   # Connector 상태 확인"
echo "   kubectl get kafkaconnector -n ${KAFKA_NS}"
echo
echo "   # 로그 확인"
echo "   kubectl logs -n ${KAFKA_NS} -l strimzi.io/name=c4-kafka-connect-connect --tail=50"
echo
echo "   # Connector 상세 정보"
echo "   kubectl describe kafkaconnector s3-sink-connector -n ${KAFKA_NS}"
echo

