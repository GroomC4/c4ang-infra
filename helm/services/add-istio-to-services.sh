#!/bin/bash
# 모든 서비스에 Istio 리소스 추가

SERVICES=("order-service" "product-service" "payment-service" "recommendation-service" "saga-tracker")

for SERVICE in "${SERVICES[@]}"; do
  echo "Adding Istio resources to $SERVICE..."
  
  SERVICE_NAME=$(echo $SERVICE | sed 's/-service//')
  SERVICE_PATH="helm/services/$SERVICE"
  
  # Service name을 카멜케이스로 변환 (order-service -> orderService)
  if [ "$SERVICE" == "saga-tracker" ]; then
    HELPER_NAME="saga-tracker"
    SERVICE_DISPLAY="Saga Tracker"
  else
    HELPER_NAME="${SERVICE_NAME}-service"
    SERVICE_DISPLAY="${SERVICE_NAME^} Service"
  fi
  
  # Path prefix 결정
  case $SERVICE in
    "order-service")
      PATH_PREFIX="/api/v1/orders"
      ;;
    "product-service")
      PATH_PREFIX="/api/v1/products"
      ;;
    "payment-service")
      PATH_PREFIX="/api/v1/payments"
      ;;
    "recommendation-service")
      PATH_PREFIX="/api/v1/recommendations"
      ;;
    "saga-tracker")
      PATH_PREFIX="/api/v1/saga"
      ;;
  esac
  
  # VirtualService 생성
  cat > "$SERVICE_PATH/templates/virtualservice.yaml" <<EOF
{{- if .Values.istio.enabled }}
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: {{ include "$HELPER_NAME.fullname" . }}-vs
  labels:
    {{- include "$HELPER_NAME.labels" . | nindent 4 }}
spec:
  hosts:
    - {{ include "$HELPER_NAME.fullname" . }}
  http:
    - match:
        - uri:
            prefix: {{ .Values.istio.pathPrefix | default "$PATH_PREFIX" }}
      route:
        - destination:
            host: {{ include "$HELPER_NAME.fullname" . }}
            port:
              number: {{ .Values.service.port }}
      timeout: {{ .Values.istio.timeout | default "30s" }}
      retries:
        attempts: {{ .Values.istio.retries.attempts | default 3 }}
        perTryTimeout: {{ .Values.istio.retries.perTryTimeout | default "10s" }}
        retryOn: {{ .Values.istio.retries.retryOn | default "5xx,reset,connect-failure,refused-stream" }}
{{- end }}
EOF

  # DestinationRule 생성
  cat > "$SERVICE_PATH/templates/destinationrule.yaml" <<EOF
{{- if .Values.istio.enabled }}
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: {{ include "$HELPER_NAME.fullname" . }}-dr
  labels:
    {{- include "$HELPER_NAME.labels" . | nindent 4 }}
spec:
  host: {{ include "$HELPER_NAME.fullname" . }}
  trafficPolicy:
    connectionPool:
      tcp:
        maxConnections: {{ .Values.istio.trafficPolicy.connectionPool.tcp.maxConnections | default 100 }}
      http:
        http1MaxPendingRequests: {{ .Values.istio.trafficPolicy.connectionPool.http.http1MaxPendingRequests | default 50 }}
        http2MaxRequests: {{ .Values.istio.trafficPolicy.connectionPool.http.http2MaxRequests | default 100 }}
        maxRequestsPerConnection: {{ .Values.istio.trafficPolicy.connectionPool.http.maxRequestsPerConnection | default 2 }}
    outlierDetection:
      consecutive5xxErrors: {{ .Values.istio.trafficPolicy.outlierDetection.consecutive5xxErrors | default 5 }}
      interval: {{ .Values.istio.trafficPolicy.outlierDetection.interval | default "10s" }}
      baseEjectionTime: {{ .Values.istio.trafficPolicy.outlierDetection.baseEjectionTime | default "30s" }}
      maxEjectionPercent: {{ .Values.istio.trafficPolicy.outlierDetection.maxEjectionPercent | default 50 }}
      minHealthPercent: {{ .Values.istio.trafficPolicy.outlierDetection.minHealthPercent | default 40 }}
{{- end }}
EOF

  # HTTPRoute 생성
  cat > "$SERVICE_PATH/templates/httproute.yaml" <<EOF
{{- if and .Values.istio.enabled .Values.istio.gatewayAPI.enabled }}
# Kubernetes Gateway API HTTPRoute
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: {{ include "$HELPER_NAME.fullname" . }}-route
  labels:
    {{- include "$HELPER_NAME.labels" . | nindent 4 }}
spec:
  parentRefs:
    - name: {{ .Values.istio.gatewayAPI.gatewayName | default "ecommerce-gateway" }}
      namespace: {{ .Values.istio.gatewayAPI.gatewayNamespace | default "ecommerce" }}
  hostnames:
    {{- range .Values.istio.gatewayAPI.hostnames }}
    - {{ . | quote }}
    {{- end }}
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: {{ .Values.istio.pathPrefix | default "$PATH_PREFIX" }}
      backendRefs:
        - name: {{ include "$HELPER_NAME.fullname" . }}
          port: {{ .Values.service.port }}
          weight: 100
{{- end }}
EOF

  echo "✓ $SERVICE_DISPLAY Istio resources created"
done

echo ""
echo "All Istio resources created successfully!"
echo "Next steps:"
echo "1. Add Istio configuration to values.yaml for each service"
echo "2. Update deployments to support Istio sidecar injection"
echo "3. Create EKS test values files"

