# Repository Guidelines

이 레포는 쇼핑몰 웹서비스 인프라(k3d·EKS) 구성과 운영 자동화를 담당하며, 에이전트 프롬프트에 필요한 최소 정보를 제공합니다.

## 프로젝트 개요 & 기술 스택
- 구조: `scripts/bootstrap`(로컬 부트스트랩) · `scripts/platform`(플랫폼 운영) · `charts`(Helm) · `config/dev|prod`(값) · `argocd`(GitOps) · `environments/<env>`(클러스터 산출물) · `performance-tests`.
- 스택: k3d, AWS EKS, Docker, Helm, ArgoCD ApplicationSet, Istio, Strimzi Kafka, External Secrets+AWS Secrets Manager, Prometheus·Grafana·Loki·Tempo, Bash+Make, SOPS+Age, k6.

## 패키지 인덱스 요약
- `Makefile`: 모든 개발/운영 명령. `make help`로 최신 타겟 확인.
- `scripts/bootstrap/dev.sh`: Docker+k3d+ECR+ArgoCD 전체 초기화 및 `--up/--down/--destroy`. 하위 `create-cluster.sh`, `start/stop-environment.sh`는 클러스터 라이프사이클을 캡슐화.
- `scripts/platform/*.sh`: `argocd`·`istio`·`kafka`·`monitoring`·`secrets` 설치/상태/제거. 새 기능 시 동일 플래그 패턴 유지.
- `charts/monitoring|istio|argo-rollouts|services|statefulset-base`: 공용 차트 소스 및 Redis/Postgres 템플릿. 변경 시 `config/*` 값으로만 환경 분기.
- `config/dev|prod/*.yaml`: 리소스 크기·시크릿 매핑. enc 파일만 커밋.
- `argocd/projects`·`argocd/applicationsets`: 경계·매트릭스 정의 (`infrastructure.yaml`, `services.yaml`).
- `environments/dev/kubeconfig`, `environments/prod/secrets`, `docs/`, `performance-tests/*`: 각각 kubeconfig, ExternalSecret, 운영 문서, k6 스크립트/결과.

## 핵심 명령
- 환경 준비: `make dev-init && export KUBECONFIG=$(pwd)/environments/dev/kubeconfig/config`.
- 차트/모니터링 검증: `make helm-build`, `make deploy-monitoring`.
- 상태 확인: `make dev-status`, `make argocd-install --status`, `make istio-install --status`.
- 성능 테스트: `make perf-smoke`, `make perf-load SERVICE=<name|all>`, `make perf-stress` (결과 `performance-tests/results/` 공유).

## 스타일 · 테스트 · 협업
- YAML은 2스페이스·kebab-case, 셸은 `#!/usr/bin/env bash` + `set -euo pipefail` + 소문자 함수, k6 파일은 snake_case와 서비스명을 사용.
- Helm/K8s 변경 시 `make dev-up` 후 `kubectl --kubeconfig=environments/dev/kubeconfig/config get pods -n msa-quality`; 추가 수동 절차는 `docs/`에 기록.
- 커밋은 Conventional Commits(`feat:`, `fix:`, `chore(scope):`), 영역별로 분리. PR에는 의도·연동 이슈·검증 명령·주요 출력·시크릿 처리 계획을 포함.
- 시크릿은 `make sops-setup`, `sops-{encrypt,decrypt}`로만 다루고 `config/<env>/*.secrets.enc.yaml`만 커밋. `argocd/applicationsets` 수정 시 dev 검증 후 prod 승격·롤백 플랜을 명시.
