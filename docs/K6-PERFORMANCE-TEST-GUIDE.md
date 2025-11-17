# k6 성능 테스트 완전 가이드

> C4ang E-commerce 플랫폼 성능 테스트 종합 문서

이 문서는 프로젝트의 k6 성능 테스트에 대한 통합 가이드입니다.

---

## 📚 관련 문서

성능 테스트 관련 모든 문서는 `performance-tests/` 디렉토리에 있습니다:

1. **[README.md](../performance-tests/README.md)** - k6 성능 테스트 전체 가이드
   - k6 소개 및 설치
   - 테스트 구조 설명
   - 실행 방법
   - 결과 분석

2. **[QUICKSTART.md](../performance-tests/QUICKSTART.md)** - 빠른 시작 가이드 (5분)
   - 로컬 환경에서 첫 테스트 실행
   - 주요 명령어
   - 트러블슈팅

3. **[CI-CD-INTEGRATION.md](../performance-tests/CI-CD-INTEGRATION.md)** - CI/CD 통합 가이드
   - GitHub Actions 워크플로우
   - Blue/Green 배포 통합
   - Slack 알림 연동

---

## 🚀 빠른 시작

### 1. k6 설치

```bash
# Makefile 사용 (권장)
make perf-install

# macOS
brew install k6

# Linux
sudo apt-get install k6  # 자세한 설치 방법은 QUICKSTART.md 참고
```

### 2. 로컬 환경 테스트

```bash
# 1. 로컬 k3d 환경 시작
make local-up

# 2. Port Forward (별도 터미널)
export KUBECONFIG=k8s-dev-k3d/kubeconfig/config
kubectl port-forward -n istio-system svc/istio-ingressgateway 8080:80

# 3. 스모크 테스트 실행
make perf-smoke

# 4. 부하 테스트 실행
make perf-load SERVICE=customer
```

### 3. EKS 환경 테스트

```bash
# 1. NLB 주소 설정
export BASE_URL="http://YOUR-NLB-DNS"

# 2. 스모크 테스트
make perf-smoke

# 3. 부하 테스트 (주의: 프로덕션 영향)
make perf-load SERVICE=customer
```

---

## 📁 디렉토리 구조

```
performance-tests/
├── README.md                      # 전체 가이드
├── QUICKSTART.md                  # 빠른 시작
├── CI-CD-INTEGRATION.md           # CI/CD 통합
├── config/                        # 설정 파일
│   ├── common.js                  # 공통 설정
│   └── scenarios.js               # 테스트 시나리오
├── tests/                         # 테스트 스크립트
│   ├── smoke/                     # 스모크 테스트
│   ├── load/                      # 부하 테스트
│   ├── stress/                    # 스트레스 테스트
│   └── integration/               # 통합 시나리오
├── utils/                         # 유틸리티
│   ├── helpers.js                 # 헬퍼 함수
│   └── data-generators.js         # 데이터 생성
├── scripts/                       # 실행 스크립트
│   ├── run-smoke.sh
│   ├── run-load.sh
│   ├── run-stress.sh
│   └── run-all.sh
└── results/                       # 결과 저장
```

---

## 🎯 테스트 시나리오

### 1. 스모크 테스트 (Smoke Test)
- **목적**: 배포 후 빠른 헬스 체크
- **실행**: `make perf-smoke`
- **시간**: 1-2분
- **VUs**: 1-5명

### 2. 부하 테스트 (Load Test)
- **목적**: 정상 트래픽 처리 능력 검증
- **실행**: `make perf-load SERVICE=all`
- **시간**: 10-30분
- **VUs**: 10-200명

### 3. 스트레스 테스트 (Stress Test)
- **목적**: 시스템 한계 파악
- **실행**: `make perf-stress`
- **시간**: 20-60분
- **VUs**: 200-1000명

### 4. 사용자 여정 (User Journey)
- **목적**: 실제 사용자 시나리오 시뮬레이션
- **실행**: `./scripts/run-load.sh user-journey`
- **시간**: 10분
- **시나리오**: 회원가입 → 검색 → 장바구니 → 주문 → 결제

---

## 📊 주요 메트릭

| 메트릭 | 목표 | 설명 |
|--------|------|------|
| `http_req_duration` (P95) | < 500ms | 95% 요청이 500ms 이내 |
| `http_req_failed` | < 1% | 실패율 1% 미만 |
| `http_reqs` | > 100/s | 초당 100개 이상 처리 |
| `vus` | - | 동시 사용자 수 |

---

## 🔄 CI/CD 통합

### GitHub Actions 워크플로우

```yaml
# .github/workflows/performance-test.yml
name: Performance Tests
on:
  workflow_dispatch:
  schedule:
    - cron: '0 2 * * 0'  # 매주 일요일

jobs:
  performance-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Install k6
        run: make perf-install
      - name: Run Tests
        run: make perf-all
```

자세한 내용은 [CI-CD-INTEGRATION.md](../performance-tests/CI-CD-INTEGRATION.md)를 참고하세요.

---

## 🐛 트러블슈팅

### Connection Refused
```bash
# Port Forward 확인
kubectl port-forward -n istio-system svc/istio-ingressgateway 8080:80
```

### Thresholds 실패
```javascript
// Thresholds 완화
thresholds: {
  'http_req_duration': ['p(95)<2000'],  // 2초로 완화
}
```

### 서비스 미응답
```bash
# 서비스 상태 확인
kubectl get pods -n ecommerce
kubectl logs -n ecommerce deploy/customer-api
```

---

## 💡 베스트 프랙티스

1. **스모크 테스트 먼저**: 배포 후 항상 스모크 테스트부터 실행
2. **점진적 부하**: 갑작스런 부하보다 점진적으로 증가
3. **프로덕션 주의**: 프로덕션 환경 테스트 시 영향도 고려
4. **결과 저장**: 테스트 결과는 항상 아티팩트로 저장
5. **임계값 설정**: 명확한 성공 기준(Thresholds) 설정

---

## 📈 다음 단계

1. ✅ 로컬 환경에서 스모크 테스트 실행
2. ✅ 각 서비스별 부하 테스트 작성
3. ✅ CI/CD 파이프라인에 통합
4. ⬜ Prometheus/Grafana 연동
5. ⬜ k6 Cloud 통합 (선택)

---

## 📚 참고 자료

### 내부 문서
- [ARCHITECTURE.md](./ARCHITECTURE.md) - 전체 시스템 아키텍처
- [EKS-ISTIO-DEPLOYMENT-SUMMARY.md](./EKS-ISTIO-DEPLOYMENT-SUMMARY.md) - 배포 가이드

### 외부 자료
- [k6 공식 문서](https://k6.io/docs/)
- [k6 예제 모음](https://k6.io/docs/examples/)
- [성능 테스트 가이드](https://k6.io/docs/testing-guides/)

---

## 🙋 문의

- **작성자**: DevOps Team
- **최종 업데이트**: 2025-11-17
- **관련 문서**: `performance-tests/` 디렉토리

