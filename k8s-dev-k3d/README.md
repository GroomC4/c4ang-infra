# k8s-dev-k3d 로컬 환경 구축 가이드

k3d를 사용한 로컬 Kubernetes 환경 구축 및 관리 스크립트입니다.

## 📁 디렉토리 구조

```
k8s-dev-k3d/
├── install-k3s.sh              # k3d 설치 및 클러스터 부트스트랩
├── scripts/
│   ├── start-environment.sh    # 로컬 환경 시작
│   ├── stop-environment.sh     # 로컬 환경 중지
│   └── cleanup.sh              # k3d 리소스 정리
├── values/
│   ├── airflow.yaml            # (선택) Airflow values
│   ├── postgresql.yaml         # PostgreSQL values (helm/statefulset-base/postgresql 사용)
│   └── redis.yaml              # Redis values (helm/statefulset-base/redis 사용)
├── kubeconfig/                 # kubeconfig 파일 저장 디렉토리
└── README.md
```

## 🚀 빠른 시작

### 1. k3d 클러스터 설치 및 생성

```bash
cd k8s-dev-k3d
./install-k3s.sh
```

이 스크립트는 다음을 수행합니다:
- k3d 자동 설치 (필요시)
- Helm 자동 설치 (필요시)
- k3d 클러스터 생성
- kubeconfig 설정
- Helm 저장소 추가

### 2. 로컬 환경 시작

```bash
cd k8s-dev-k3d/scripts
./start-environment.sh
```

이 스크립트는 다음을 수행합니다:
- k3d 클러스터 시작/생성
- 네임스페이스 생성
- Redis와 PostgreSQL 베이스 차트 배포 (필요한 Helm dependencies 자동 빌드 포함)
- 헬스체크 및 상태 출력

> ℹ️ **처음 실행 시 다운로드 지연 안내**
>
> Redis/PostgreSQL 차트는 Bitnami 원격 저장소의 의존성 패키지를 내려받습니다. 처음 한 번은 `helm dependency build` 시간이 다소 걸릴 수 있습니다. 미리 받아 두고 싶다면 아래를 실행하세요.
>
> ```bash
> cd helm
> ./build-dependencies.sh
> ```
>
> 이후에는 캐시된 `charts/*.tgz`를 재사용하므로 훨씬 빠르게 배포됩니다.

### 3. 로컬 환경 중지

```bash
cd k8s-dev-k3d/scripts
./stop-environment.sh
```

## 📝 사용 방법

### kubeconfig 설정

```bash
export KUBECONFIG=$(pwd)/k8s-dev-k3d/kubeconfig/config
kubectl get nodes
```

### 클러스터 관리

```bash
# 클러스터 목록
k3d cluster list

# 클러스터 시작
k3d cluster start msa-quality-cluster

# 클러스터 중지
k3d cluster stop msa-quality-cluster

# 클러스터 삭제
k3d cluster delete msa-quality-cluster
```

### Helm 차트 배포

```bash
export KUBECONFIG=$(pwd)/k8s-dev-k3d/kubeconfig/config

# Redis 배포 (자동)
cd k8s-dev-k3d/scripts
./start-environment.sh

# 또는 수동 배포 (Redis)
helm upgrade --install redis \
  helm/statefulset-base/redis \
  --namespace msa-quality \
  --create-namespace \
  --values k8s-dev-k3d/values/redis.yaml

# 수동 배포 (PostgreSQL)
helm upgrade --install postgresql \
  helm/statefulset-base/postgresql \
  --namespace msa-quality \
  --create-namespace \
  --values k8s-dev-k3d/values/postgresql.yaml
```

## 🔧 환경 변수

| 변수 | 기본값 | 설명 |
|------|--------|------|
| `CLUSTER_NAME` | `msa-quality-cluster` | k3d 클러스터 이름 |
| `NAMESPACE` | `msa-quality` | Kubernetes 네임스페이스 |
| `NODEPORT_START` | `30000` | NodePort 시작 포트 |
| `NODEPORT_END` | `30100` | NodePort 종료 포트 |
| `WAIT_TIMEOUT` | `600` | Helm 배포 대기 시간 (초) |

## 🏗️ 구조 설명

### Helm 베이스 차트 사용

k3d 환경은 저장소의 Helm 베이스 차트를 직접 사용합니다:

- `helm/statefulset-base/redis/` - Redis Statefulset 베이스 차트
- `helm/statefulset-base/postgresql/` - PostgreSQL Statefulset 베이스 차트
- `helm/management-base/airflow/` - (선택) Airflow 관리용 베이스 차트
- `k8s-dev-k3d/values/*.yaml` - 로컬 환경 최적화 values 파일

### k8s-deployments와의 차이

- **k8s-deployments**: 프로덕션/실단계 배포용 (별도 관리)
- **k8s-dev-k3d**: 로컬 개발/테스트 환경 전용
- **helm/**: 공통 Helm 차트 (양쪽에서 사용)

## 🐛 문제 해결

### 포트 충돌

```bash
# 포트 사용 확인
lsof -i :80
lsof -i :443
lsof -i :6443

# 포트 범위 변경
export NODEPORT_START=30100
export NODEPORT_END=30200
./install-k3s.sh
```

### 클러스터 재생성

```bash
# 방법 1: 정리 스크립트 사용 (권장)
cd k8s-dev-k3d/scripts
./cleanup.sh

# 방법 2: 수동 삭제
k3d cluster delete msa-quality-cluster
./install-k3s.sh

# 방법 3: 강제 정리 (확인 없이)
cd k8s-dev-k3d/scripts
./cleanup.sh --force
```

### Helm 차트 수동 배포

```bash
export KUBECONFIG=$(pwd)/k8s-dev-k3d/kubeconfig/config

# Redis 수동 배포
helm upgrade --install redis \
  helm/statefulset-base/redis \
  --namespace msa-quality \
  --create-namespace \
  --values k8s-dev-k3d/values/redis.yaml

# PostgreSQL 수동 배포
helm upgrade --install postgresql \
  helm/statefulset-base/postgresql \
  --namespace msa-quality \
  --create-namespace \
  --values k8s-dev-k3d/values/postgresql.yaml
```

## 📚 참고 자료

- [k3d 공식 문서](https://k3d.io/)
- [k3s 공식 문서](https://k3s.io/)
- [Helm 공식 문서](https://helm.sh/docs/)

