#!/bin/bash
# EKS Istio 테스트 배포 스크립트

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

NAMESPACE=${NAMESPACE:-ecommerce}
DRY_RUN=${DRY_RUN:-false}

echo "=========================================="
echo "EKS Istio 테스트 배포"
echo "Namespace: $NAMESPACE"
echo "Dry-run: $DRY_RUN"
echo "=========================================="
echo ""

# Namespace 확인
echo "📋 Checking namespace..."
if ! kubectl get namespace $NAMESPACE &> /dev/null; then
    echo -e "${YELLOW}⚠️  Namespace '$NAMESPACE' does not exist. Creating...${NC}"
    kubectl create namespace $NAMESPACE
fi

# Istio injection label 확인
ISTIO_LABEL=$(kubectl get namespace $NAMESPACE -o jsonpath='{.metadata.labels.istio-injection}' 2>/dev/null || echo "")
if [ "$ISTIO_LABEL" != "enabled" ]; then
    echo -e "${YELLOW}⚠️  Istio injection not enabled for namespace. Enabling...${NC}"
    kubectl label namespace $NAMESPACE istio-injection=enabled --overwrite
fi

echo -e "${GREEN}✓ Namespace ready${NC}"
echo ""

# 서비스 목록
SERVICES=(
    "customer-service"
    "order-service"
    "product-service"
    "payment-service"
    "recommendation-service"
    "saga-tracker"
)

# Dry-run 검증
if [ "$DRY_RUN" = "true" ]; then
    echo "🔍 Dry-run mode: Validating manifests..."
    echo ""
    
    for SERVICE in "${SERVICES[@]}"; do
        echo "Validating $SERVICE..."
        
        if [ -f "$SERVICE/values-eks-test.yaml" ]; then
            VALUES_FILE="values-eks-test.yaml"
        else
            VALUES_FILE="values.yaml"
            echo -e "${YELLOW}⚠️  No values-eks-test.yaml found, using default values.yaml${NC}"
        fi
        
        helm template $SERVICE \
            ./$SERVICE \
            -f ./$SERVICE/$VALUES_FILE \
            --namespace $NAMESPACE \
            --dry-run \
            --debug > /tmp/${SERVICE}-manifest.yaml
        
        # YAML 구문 검증
        if kubectl apply --dry-run=client -f /tmp/${SERVICE}-manifest.yaml &> /dev/null; then
            echo -e "${GREEN}✓ $SERVICE manifest is valid${NC}"
        else
            echo -e "${RED}✗ $SERVICE manifest has errors${NC}"
            kubectl apply --dry-run=client -f /tmp/${SERVICE}-manifest.yaml
            exit 1
        fi
        echo ""
    done
    
    echo -e "${GREEN}✅ All manifests are valid!${NC}"
    echo "To deploy, run: DRY_RUN=false ./deploy-test-eks.sh"
    exit 0
fi

# 실제 배포
echo "🚀 Deploying services to EKS..."
echo ""

for SERVICE in "${SERVICES[@]}"; do
    echo "Deploying $SERVICE..."
    
    if [ -f "$SERVICE/values-eks-test.yaml" ]; then
        VALUES_FILE="values-eks-test.yaml"
        echo "Using EKS test configuration"
    else
        VALUES_FILE="values.yaml"
        echo -e "${YELLOW}⚠️  No values-eks-test.yaml found, using default values.yaml${NC}"
    fi
    
    helm upgrade --install $SERVICE \
        ./$SERVICE \
        -f ./$SERVICE/$VALUES_FILE \
        --namespace $NAMESPACE \
        --create-namespace \
        --wait \
        --timeout 5m
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ $SERVICE deployed successfully${NC}"
    else
        echo -e "${RED}✗ $SERVICE deployment failed${NC}"
        exit 1
    fi
    echo ""
done

echo ""
echo "=========================================="
echo -e "${GREEN}✅ All services deployed successfully!${NC}"
echo "=========================================="
echo ""

# 배포 상태 확인
echo "📊 Checking deployment status..."
echo ""
kubectl get pods -n $NAMESPACE
echo ""
kubectl get svc -n $NAMESPACE
echo ""

# Istio resources 확인
echo "🔍 Checking Istio resources..."
echo ""
echo "VirtualServices:"
kubectl get virtualservices -n $NAMESPACE
echo ""
echo "DestinationRules:"
kubectl get destinationrules -n $NAMESPACE
echo ""
echo "HTTPRoutes:"
kubectl get httproutes -n $NAMESPACE
echo ""

# 유용한 명령어 출력
echo "=========================================="
echo "📝 Useful commands:"
echo "=========================================="
echo ""
echo "# Check pod details:"
echo "kubectl get pods -n $NAMESPACE -o wide"
echo ""
echo "# Check pod logs (with istio-proxy):"
echo "kubectl logs -n $NAMESPACE <pod-name> -c <service-name>"
echo "kubectl logs -n $NAMESPACE <pod-name> -c istio-proxy"
echo ""
echo "# Check Istio injection:"
echo "kubectl describe pod -n $NAMESPACE <pod-name> | grep istio-proxy"
echo ""
echo "# Test service endpoint:"
echo "kubectl exec -n $NAMESPACE <pod-name> -- curl http://<service-name>:8080/api/v1/<endpoint>"
echo ""

