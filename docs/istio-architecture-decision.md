# Istio Gateway API 아키텍처 결정 문서

## 🎯 Executive Summary

MSA 환경에서 Istio Gateway API를 통한 인증/인가 구현을 위해 **하이브리드 중앙-분산 관리 패턴**을 채택했습니다.

## 📊 아키텍처 비교 분석

### 1. 중앙화 관리 (Centralized)

| 장점 | 단점 |
|------|------|
| ✅ 비용 효율적 (단일 NLB/ALB) | ❌ 단일 실패 지점 (SPOF) |
| ✅ 일관된 보안 정책 | ❌ 팀 자율성 제한 |
| ✅ 운영 단순화 | ❌ 변경 시 조율 필요 |
| ✅ TLS 인증서 중앙 관리 | ❌ 커스터마이징 제한 |

**적합한 경우**:
- 소규모~중규모 조직 (< 50 서비스)
- 비용 최적화가 중요
- 표준화된 보안 요구사항

### 2. 분산 관리 (Distributed)

| 장점 | 단점 |
|------|------|
| ✅ 팀 자율성 극대화 | ❌ 높은 인프라 비용 (3-5배) |
| ✅ 장애 격리 | ❌ 관리 복잡도 증가 |
| ✅ 서비스별 커스터마이징 | ❌ 정책 일관성 유지 어려움 |
| ✅ 독립적 스케일링 | ❌ 중복 설정 발생 |

**적합한 경우**:
- 대규모 조직 (> 100 서비스)
- 규제 준수 요구사항 (PCI-DSS, HIPAA)
- 서비스별 SLA 차이

### 3. 하이브리드 (Hybrid) - ✅ 선택

| 장점 | 단점 |
|------|------|
| ✅ 비용과 유연성 균형 | ⚠️ 초기 설계 복잡도 |
| ✅ 점진적 확장 가능 | ⚠️ 두 패턴 모두 이해 필요 |
| ✅ 필요시 분산 전환 용이 | |
| ✅ 팀 자율성 + 중앙 거버넌스 | |

## 🏗️ 선택한 아키텍처: 하이브리드 패턴

### 구성 요소별 책임 분리

```
┌─────────────────────────────────────────┐
│        Platform Team (중앙 관리)         │
├─────────────────────────────────────────┤
│ • Main Gateway (ecommerce-gateway)      │
│ • TLS/Certificate Management            │
│ • Global JWT Authentication            │
│ • Public Endpoints Definition          │
│ • Cross-cutting Security Policies      │
└─────────────────────────────────────────┘
                    ↕
┌─────────────────────────────────────────┐
│       Service Teams (분산 관리)          │
├─────────────────────────────────────────┤
│ • HTTPRoute (Service Routing)          │
│ • Service-specific Authorization       │
│ • Traffic Management (Retry, Timeout)  │
│ • Service-specific Headers             │
│ • Canary/Blue-Green Deployment        │
└─────────────────────────────────────────┘
```

### 구현 세부사항

#### 중앙 관리 영역 (Platform Team)

**위치**: `helm/management-base/istio/`

**관리 항목**:
1. **Gateway 인프라**
   - Main Gateway (공용 API)
   - Webhook Gateway (파트너 연동)
   - Load Balancer 설정

2. **보안 정책**
   - JWT 발급자 및 JWKS URI
   - 전역 public endpoints
   - mTLS 설정
   - Rate limiting

3. **네트워킹**
   - DNS 설정
   - TLS 인증서
   - Cross-namespace routing 정책

#### 분산 관리 영역 (Service Teams)

**위치**: `helm/services/[service-name]/`

**관리 항목**:
1. **라우팅 규칙**
   - HTTPRoute 정의
   - 경로 매핑
   - 헤더 기반 라우팅

2. **서비스별 인가**
   - Role-based access control
   - 서비스 특화 정책
   - API 버전별 접근 제어

3. **트래픽 관리**
   - Circuit breaker
   - Retry 정책
   - Timeout 설정
   - Canary deployment

## 📈 장단점 종합 분석

### 선택한 하이브리드 패턴의 장점

1. **비용 효율성**
   - 공용 Gateway로 80% 비용 절감
   - 필요시만 전용 Gateway 생성 (Payment 등)

2. **운영 효율성**
   - Platform Team: 인프라/보안 집중
   - Service Team: 비즈니스 로직 집중
   - 명확한 책임 경계

3. **확장성**
   - 시작: 중앙 Gateway만 사용
   - 성장: 필요한 서비스만 분리
   - 미래: Ambient Mesh로 전환 가능

4. **보안 일관성**
   - 전역 보안 정책 강제
   - 서비스별 세부 규칙 허용
   - Compliance 요구사항 충족

### 잠재적 단점 및 대응 방안

| 단점 | 대응 방안 |
|------|-----------|
| 초기 설정 복잡도 | • Helm 템플릿 제공<br>• 자동화 스크립트 제공<br>• 상세 문서화 |
| 팀 간 조율 필요 | • GitOps 워크플로우<br>• 명확한 RACI 매트릭스<br>• Self-service 포털 |
| 학습 곡선 | • 내부 교육 프로그램<br>• 베스트 프랙티스 가이드<br>• 샘플 코드 제공 |

## 🚀 구현 로드맵

### Phase 1: Foundation (Week 1-2) ✅ 완료
- [x] 중앙 Gateway 설정
- [x] JWT Authentication 구현
- [x] Global Authorization Policy
- [x] Customer Service 통합

### Phase 2: Service Migration (Week 3-4)
- [ ] Order Service 마이그레이션
- [ ] Product Service 마이그레이션
- [ ] Inventory Service 마이그레이션

### Phase 3: Advanced Features (Week 5-6)
- [ ] Payment Service (전용 Gateway)
- [ ] Rate Limiting 구현
- [ ] Circuit Breaker 설정

### Phase 4: Optimization (Week 7-8)
- [ ] Sidecar Configuration 최적화
- [ ] Observability 강화
- [ ] Performance Tuning

### Phase 5: Future Evolution (2025 Q1)
- [ ] Ambient Mesh 평가
- [ ] Multi-cluster 지원
- [ ] Service Mesh Federation

## 🔧 기술 스택

| 컴포넌트 | 선택 기술 | 버전 | 이유 |
|----------|----------|------|------|
| Service Mesh | Istio | 1.20+ | 업계 표준, 성숙도 |
| Gateway API | K8s Gateway API | v1.0.0 | 표준화, 미래 지향적 |
| 인증 | JWT (RS256) | - | 상태 비저장, 확장성 |
| Configuration | Helm | 3.0+ | 템플릿화, 재사용성 |
| GitOps | ArgoCD/Flux | - | 선언적 배포 |

## 📊 성능 영향 분석

### 메모리 사용량
- **Sidecar 모드**: ~200MB per pod
- **Sidecar + Config 최적화**: ~120MB per pod (40% 감소)
- **Ambient Mesh**: ~20MB per pod (90% 감소)

### 레이턴시
- **Gateway 추가 레이턴시**: ~1-2ms
- **JWT 검증**: ~0.5ms
- **Total overhead**: < 3ms (허용 범위)

### 확장성
- **단일 Gateway**: 10,000 RPS 처리 가능
- **필요시 HPA**: 2-10 replicas auto-scaling
- **Circuit Breaker**: 장애 격리

## 🎯 성공 지표

| 메트릭 | 목표 | 측정 방법 |
|--------|------|-----------|
| 배포 시간 | 30% 단축 | CI/CD 파이프라인 |
| 보안 정책 일관성 | 100% | Policy 감사 |
| 서비스 온보딩 시간 | < 1일 | 팀 피드백 |
| 인증 실패율 | < 0.1% | Prometheus |
| P99 레이턴시 증가 | < 5ms | Grafana |

## 📝 의사결정 근거

### 왜 하이브리드인가?

1. **현재 상황**
   - 중간 규모 시스템 (10-20 서비스)
   - 성장 중인 조직
   - 다양한 보안 요구사항

2. **미래 요구사항**
   - PCI-DSS 준수 (Payment)
   - 멀티 테넌시 지원
   - 글로벌 확장

3. **팀 구조**
   - Platform Team: 5명
   - Service Teams: 3-5명 x 5팀
   - 명확한 역할 분리 필요

### 왜 Gateway API인가?

1. **표준화**: Kubernetes SIG 공식 표준
2. **미래 지향적**: Istio의 권장 방향
3. **이식성**: 벤더 종속성 감소
4. **통합성**: GAMMA로 Service Mesh 통합

## 📚 참고 사례

| 회사 | 패턴 | 규모 | 핵심 교훈 |
|------|------|------|-----------|
| Mercari | 하이브리드 | 1000+ services | Sidecar 최적화 중요 |
| FICO | 분산 | 100+ services | Compliance별 Gateway |
| Amazon | 하이브리드 | 10000+ services | 팀 자율성 + 중앙 거버넌스 |
| Salesforce | 중앙화 + 추상화 | 5000+ services | Helm 템플릿 활용 |

## ✅ 최종 권장사항

1. **즉시 실행**
   - 하이브리드 패턴으로 시작
   - Customer Service부터 점진적 마이그레이션
   - 모니터링 체계 구축

2. **3개월 내 실행**
   - 전체 서비스 마이그레이션
   - Performance tuning
   - Disaster recovery 계획

3. **6개월 후 검토**
   - Ambient Mesh 전환 평가
   - Multi-cluster 필요성 검토
   - 확장성 재평가

## 🔗 관련 문서

- [Istio Gateway 배포 가이드](./istio-gateway-deployment-guide.md)
- [Spring Security 제거 작업 문서](../../c4ang-customer-service/docs/Spring%20Security%20제거%20작업%20문서.md)
- [Helm Charts 사용 가이드](./helm-charts-guide.md)

---

**문서 버전**: 1.0.0
**작성일**: 2024-11-20
**작성자**: Platform Architecture Team
**승인자**: CTO

**다음 리뷰**: 2025-02-20 (3개월 후)