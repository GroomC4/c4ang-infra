# ArgoCD Manifest Directory

이 디렉토리는 ArgoCD가 직접 적용하는 Kubernetes 매니페스트를 포함합니다.

## 파일 목록

### namespaces.yaml
네임스페이스 정의 파일입니다. Istio injection 라벨을 포함합니다.

- `ecommerce`: 마이크로서비스 네임스페이스 (istio-injection: enabled)
- `monitoring`: 모니터링 스택 네임스페이스

**적용 방법:**
- ArgoCD Application: `argocd/applicationsets/00-namespaces.yaml`
- Sync Wave: `-1` (가장 먼저 실행)

### root-apps.yaml.deprecated (레거시)
**[DEPRECATED]** 이 파일은 더 이상 사용되지 않습니다.

새로운 ApplicationSet 기반 방식을 사용하세요:
- 인프라: `argocd/applicationsets/infrastructure.yaml`
- 서비스: `argocd/applicationsets/services.yaml`

## 주의사항

이 디렉토리에 새로운 Application 정의를 추가하지 마세요.
대신 `argocd/applicationsets/` 디렉토리에 ApplicationSet을 생성하세요.

### 왜 ApplicationSet을 사용해야 하나요?

1. **환경별 자동 생성**: dev/prod 환경을 자동으로 생성
2. **중복 제거**: 하나의 템플릿으로 여러 Application 생성
3. **유지보수 용이**: 설정 변경 시 한 곳만 수정
4. **확장성**: 새로운 서비스 추가가 간단함

## 마이그레이션 가이드

레거시 Application을 ApplicationSet으로 마이그레이션하려면:

1. `argocd/applicationsets/` 디렉토리에 새 ApplicationSet 생성
2. 환경별 설정을 `config/dev/`, `config/prod/`로 분리
3. 레거시 Application 삭제
4. ApplicationSet 적용 확인

자세한 내용은 `argocd/DEPLOYMENT-ORDER.md`를 참고하세요.
