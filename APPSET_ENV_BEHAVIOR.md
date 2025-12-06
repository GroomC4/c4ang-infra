# ApplicationSet 환경 동작 정리

이 문서는 App of Apps 패턴 아래에서 ApplicationSet이 환경별로 어떻게 동작하는지, 그리고 환경/클러스터 분리 설정이 실제 운영(로컬 k3d 1개 + EKS 1개)과 어떻게 조화를 이루는지 요약합니다.

## 핵심 구성 요약
- **Root Application**: `bootstrap/root-application.yaml` 단 하나가 `argocd/hooks`, `argocd/projects`, `argocd/applicationsets`를 재귀적으로 동기화합니다. 특정 환경만 실행하는 스위치는 없으며, Root가 항상 모든 ApplicationSet 리소스를 생성합니다.
- **ApplicationSet 내부 분기**: 환경별 분리는 각 ApplicationSet의 Matrix Generator에 있는 `env` 요소로 처리됩니다. 예) `argocd/applicationsets/infrastructure.yaml`에서는 `env: dev`가 `https://kubernetes.default.svc`(k3d), `env: prod`가 EKS API URL을 가리킵니다.
- **Destination 설정**: 템플릿의 `spec.destination.server: '{{.cluster}}'`가 generator의 `cluster` 필드를 사용하므로, ApplicationSet이 자동으로 dev Application을 k3d로, prod Application을 EKS로 전송합니다.
- **Single Cluster 환경**: 하나의 클러스터에서 dev/prod를 namespace로만 구분하고 싶다면 generator 리스트를 수정하여 동일한 `cluster` 값을 넣거나, 특정 환경 항목을 제거해 한 환경만 남길 수 있습니다.

## App of Apps + ApplicationSet 동작 흐름
1. `bootstrap/install-argocd.sh` 실행 후 Root Application을 적용 → Hook이 ApplicationSet Controller 준비 여부를 확인.
2. Root Application이 `argocd/projects`를 배포하여 `infrastructure`, `applications` 등 Role 경계를 정의.
3. Root Application이 `argocd/applicationsets/*.yaml`을 모두 생성.
4. 각 ApplicationSet이 Matrix Generator를 이용해 `(env, component)` 조합만큼 Application을 생성하고 Sync Wave에 따라 네임스페이스 → 인프라 → 서비스 순으로 배포.
5. ArgoCD는 `automated.prune` + `selfHeal` 설정으로 dev·prod 두 환경을 동시에 감시/복구.

## 환경/클러스터 분리에 대한 FAQ
- **Q. ApplicationSet이 환경별로 클러스터를 분리 지정해두면 k3d 1개 + EKS 1개로 개발/운영을 못 하는가?**  
  **A.** 아니요. 현재 설정은 "env마다 어느 클러스터로 배포할지 지정"한 것뿐입니다. dev 항목은 k3d API 하나만, prod 항목은 EKS API 하나만 가리키므로 한 환경당 단일 클러스터 운용과 충돌하지 않습니다.

- **Q. Root Application이 특정 환경만 실행하도록 제어하나?**  
  **A.** 아닙니다. Root는 항상 모든 ApplicationSet을 동기화합니다. 환경별 감지는 ApplicationSet 내부에서 수행되며, 필요 시 generator의 `env` 리스트를 수정하여 배포 대상을 제한합니다.

- **Q. 한 클러스터에서 dev/prod를 네임스페이스로만 나누고 싶을 때는?**  
  **A.** ApplicationSet generator의 `cluster` 값을 동일하게 맞춰 같은 API 서버를 가리키게 하거나, 특정 환경 항목을 삭제하여 단일 환경만 남기면 됩니다. Sync Wave와 값 파일을 통해 namespace/리소스 차이를 유지할 수 있습니다.

- **Q. 이 구조의 장단점은?**  
  - **장점**: App of Apps 하나로 전체 구성을 배포, 환경 추가 시 Matrix 리스트만 확장, Sync Wave로 의존성 보장, dev/prod 상태를 하나의 ArgoCD UI에서 확인.  
  - **단점**: YAML 구조가 복잡하고 ApplicationSet Controller 의존도가 높음, 잘못된 커밋이 두 환경에 동시에 영향을 줄 수 있으므로 리뷰와 테스트가 필수, Sync Wave 관리가 필요.

## 참고 파일
- `bootstrap/root-application.yaml`: Root Application 정의 (디렉터리 동기화 범위 포함)
- `argocd/hooks/wait-for-applicationset-controller.yaml`: ApplicationSet Controller 준비를 대기하는 PreSync Hook
- `argocd/applicationsets/*.yaml`: 환경/클러스터 매핑 및 Sync Wave 지정
- `APP_OF_APPS.md`, `PROJECT_DESIGN.md`: 전체 아키텍처 설명 및 부트스트랩 흐름
