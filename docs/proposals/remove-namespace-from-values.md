# 제안서: Helm values.yaml에서 namespace 필드 제거

## 개요

현재 Helm 차트의 `values.yaml` 파일에 `namespace` 필드가 포함되어 있습니다. 이 문서는 해당 필드를 제거하고 namespace 관리를 ArgoCD Application 레벨로 일원화하는 것을 제안합니다.

## 현재 상태

### 중복된 namespace 설정

현재 namespace가 두 곳에서 정의되고 있습니다:

**1. values.yaml (Helm 차트)**
```yaml
# charts/argo-rollouts/values.yaml
namespace: argo-rollouts
```

**2. ArgoCD Application**
```yaml
# ArgoCD Application spec
spec:
  destination:
    namespace: argo-rollouts
    server: https://kubernetes.default.svc
```

### 영향받는 차트

| 차트 | values.yaml 내 namespace |
|------|-------------------------|
| argo-rollouts | `namespace: argo-rollouts` |
| external-services | `namespace: ecommerce` |
| istio | `namespace: istio-system` |
| monitoring | `namespace: monitoring` |
| (기타 서비스 차트) | 각각 정의됨 |

## 문제점

### 1. 설정 중복
- 동일한 정보가 두 곳에서 관리됨
- 변경 시 양쪽 모두 수정 필요

### 2. 불일치 위험
- values.yaml과 ArgoCD Application의 namespace가 다를 경우 예기치 않은 동작 발생 가능
- 디버깅 시 혼란 야기

### 3. Helm 표준 관행과 불일치
- Helm에서는 namespace를 `helm install -n <namespace>` 옵션으로 지정하는 것이 표준
- values.yaml의 namespace는 Helm 자체에서 사용되지 않고, 템플릿에서 참조하는 경우에만 의미 있음

## 제안 사항

### 변경 내용

1. **values.yaml에서 namespace 필드 제거**
2. **ArgoCD Application에서만 namespace 관리**
3. **템플릿에서 `.Release.Namespace` 사용**

### 변경 전

```yaml
# values.yaml
namespace: argo-rollouts

# templates/some-resource.yaml
metadata:
  namespace: {{ .Values.namespace }}
```

### 변경 후

```yaml
# values.yaml
# (namespace 필드 없음)

# templates/some-resource.yaml
metadata:
  namespace: {{ .Release.Namespace }}
```

## 구현 계획

### Phase 1: 템플릿 수정
1. 모든 차트의 템플릿에서 `{{ .Values.namespace }}`를 `{{ .Release.Namespace }}`로 변경
2. 단위 테스트 수행

### Phase 2: values.yaml 정리
1. 각 차트의 values.yaml에서 namespace 필드 제거
2. config/local/*.yaml, config/prod/*.yaml에서 namespace 필드 제거

### Phase 3: 문서화
1. 차트 사용 가이드 업데이트
2. ArgoCD Application 생성 가이드에 namespace 설정 방법 명시

## 영향 분석

### 장점
- **단일 진실 공급원(Single Source of Truth)**: namespace는 ArgoCD Application에서만 관리
- **Helm 표준 준수**: `.Release.Namespace` 사용은 Helm 커뮤니티 표준
- **유지보수 용이**: 변경 포인트 감소

### 단점
- **마이그레이션 작업 필요**: 기존 차트 및 설정 파일 수정 필요
- **일시적 혼란 가능**: 전환 기간 동안 팀원 교육 필요

### 위험 요소
- 템플릿에서 namespace를 직접 참조하는 경우 누락 시 오류 발생
- 마이그레이션 중 일부 차트만 변경 시 불일치 발생

## 마이그레이션 체크리스트

- [ ] 영향받는 모든 차트 목록 작성
- [ ] 각 차트의 템플릿에서 `.Values.namespace` 사용 여부 확인
- [ ] `.Release.Namespace`로 변경
- [ ] 로컬 환경에서 테스트
- [ ] values.yaml에서 namespace 제거
- [ ] config/local/*.yaml에서 namespace 제거
- [ ] config/prod/*.yaml에서 namespace 제거
- [ ] ArgoCD에서 전체 sync 테스트
- [ ] 문서 업데이트

## 결론

namespace를 ArgoCD Application 레벨에서 일원화하면 설정 관리가 단순화되고 Helm 표준 관행을 따르게 됩니다. 마이그레이션 작업이 필요하지만, 장기적으로 유지보수성이 향상됩니다.

## 참고 자료

- [Helm Best Practices - Namespaces](https://helm.sh/docs/chart_best_practices/conventions/#namespace)
- [ArgoCD Application Specification](https://argo-cd.readthedocs.io/en/stable/user-guide/application-specification/)
