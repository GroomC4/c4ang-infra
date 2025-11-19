#!/bin/bash

# 도메인 서비스들의 deployment.yaml에 로그 수집 설정을 추가하는 스크립트

SERVICES=("customer-service" "order-service" "payment-service" "product-service" "recommendation-service" "saga-tracker")

for SERVICE in "${SERVICES[@]}"; do
    DEPLOYMENT_FILE="$SERVICE/templates/deployment.yaml"

    if [ -f "$DEPLOYMENT_FILE" ]; then
        echo "Updating $SERVICE deployment for logging..."

        # 이미 업데이트되었는지 확인
        if grep -q "prometheus.io/scrape" "$DEPLOYMENT_FILE"; then
            echo "  - Already updated, skipping..."
            continue
        fi

        # 백업 생성
        cp "$DEPLOYMENT_FILE" "$DEPLOYMENT_FILE.bak"

        # annotations 섹션 찾아서 추가
        sed -i.tmp '/annotations:/a\
        # Prometheus metrics scraping\
        prometheus.io/scrape: "true"\
        prometheus.io/port: "{{ .Values.service.targetPort }}"\
        prometheus.io/path: "/actuator/prometheus"' "$DEPLOYMENT_FILE"

        # labels 섹션에 추가
        sed -i.tmp '/labels:/a\
        # 로그 수집을 위한 추가 레이블\
        app: {{ include "'$SERVICE'.fullname" . }}\
        environment: {{ .Values.environment | default "prod" }}\
        team: "ecommerce"\
        component: "backend"' "$DEPLOYMENT_FILE"

        # 임시 파일 제거
        rm -f "$DEPLOYMENT_FILE.tmp"

        echo "  - Updated successfully"
    else
        echo "Warning: $DEPLOYMENT_FILE not found"
    fi
done

echo "All services updated for logging configuration"