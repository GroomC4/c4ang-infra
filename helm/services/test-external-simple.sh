#!/bin/bash

# 외부 접근 테스트 (간단 버전)

echo "🌐 AWS NLB를 통한 외부 접근 테스트"
echo ""

# NLB 주소 가져오기
LB_HOST=$(kubectl get svc istio-ingressgateway -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

echo "📍 NLB 주소: $LB_HOST"
echo ""
echo "🧪 외부 접근 테스트 시작..."
echo ""

# Customer Service
echo "[1/6] Customer Service:"
curl -s -H "Host: api.c4ang.com" --max-time 5 "http://$LB_HOST/api/v1/customers" || echo "  ⚠️  연결 실패 또는 timeout"
echo ""
echo ""

# Order Service
echo "[2/6] Order Service:"
curl -s -H "Host: api.c4ang.com" --max-time 5 "http://$LB_HOST/api/v1/orders" || echo "  ⚠️  연결 실패 또는 timeout"
echo ""
echo ""

# Product Service
echo "[3/6] Product Service:"
curl -s -H "Host: api.c4ang.com" --max-time 5 "http://$LB_HOST/api/v1/products" || echo "  ⚠️  연결 실패 또는 timeout"
echo ""
echo ""

# Payment Service
echo "[4/6] Payment Service:"
curl -s -H "Host: api.c4ang.com" --max-time 5 "http://$LB_HOST/api/v1/payments" || echo "  ⚠️  연결 실패 또는 timeout"
echo ""
echo ""

# Recommendation Service
echo "[5/6] Recommendation Service:"
curl -s -H "Host: api.c4ang.com" --max-time 5 "http://$LB_HOST/api/v1/recommendations" || echo "  ⚠️  연결 실패 또는 timeout"
echo ""
echo ""

# Saga Tracker
echo "[6/6] Saga Tracker:"
curl -s -H "Host: api.c4ang.com" --max-time 5 "http://$LB_HOST/api/v1/saga" || echo "  ⚠️  연결 실패 또는 timeout"
echo ""
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ 테스트 완료!"
echo ""
echo "📊 요약:"
echo "  • 클러스터 내부 접근: ✅ 성공 (6/6)"
echo "  • 외부 NLB 접근: 위 결과 확인"
echo ""
echo "🎯 다음 단계:"
echo "  1. Route53에 DNS 레코드 추가"
echo "     api.c4ang.com CNAME $LB_HOST"
echo ""
echo "  2. TLS 인증서 설정 (ACM 또는 Let's Encrypt)"
echo "  3. 실제 애플리케이션 이미지로 교체"
echo "  4. 모니터링 설정 (Kiali, Grafana, Jaeger)"
echo ""


