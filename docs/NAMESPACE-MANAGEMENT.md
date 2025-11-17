# 네임스페이스 관리 가이드

## 🎯 목적

이 문서는 EKS 환경에서 Istio 사이드카 자동 주입을 위한 네임스페이스 라벨을 **영구적으로** 관리하는 방법을 설명합니다.

## ⚠️ 중요: 근본 원인

### 문제
- 수동으로 `kubectl label` 명령어로 라벨을 추가하면 **일시적**입니다
- 재배포, ArgoCD 동기화, Terraform apply 시 라벨이 사라질 수 있습니다
- 결과: 사이드카 자동 주입이 중단됩니다

### 해결
네임스페이스 정의를 **코드로 관리**하여 언제든 재생성 가능하게 만들어야 합니다.

## 🛠️ 해결 방법 (4가지)

### 방법 1: Helm 차트 사용 ⭐️ (권장)

**장점**:
- GitOps 친화적
- 버전 관리 가능
- 롤백 가능
- ArgoCD와 완벽 호환

**설정**:

`helm/management-base/istio/values.yaml`:
```yaml
namespace:
  name: ecommerce
  create: true
  istioInjection: enabled  # ← 여기가 핵심!
```

**배포**:
```bash
# Helm으로 직접 배포
helm install istio-config ./helm/management-base/istio \
  --namespace ecommerce \
  --create-namespace

# 또는 업데이트된 install-istio.sh 사용
cd k8s-eks/istio
./install-istio.sh  # Helm 템플릿 자동 사용
```

**검증**:
```bash
kubectl get namespace ecommerce -o yaml
```

### 방법 2: ArgoCD Application ⭐️ (프로덕션 권장)

**장점**:
- 자동 동기화 (selfHeal)
- Git을 Single Source of Truth로 사용
- 변경사항 자동 감지 및 복구
- 의존성 관리 (서비스보다 먼저 Istio 배포)

**설정**:

`k8s-eks/argocd/istio-application.yaml` (이미 생성됨):
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: istio-config
  namespace: argocd
spec:
  source:
    path: helm/management-base/istio
    helm:
      values: |
        namespace:
          name: ecommerce
          create: true
          istioInjection: enabled  # ← 자동으로 라벨 설정!
  
  syncPolicy:
    automated:
      selfHeal: true  # ← 라벨이 삭제되면 자동 복구!
```

**배포**:
```bash
# ArgoCD에 Application 등록
kubectl apply -f k8s-eks/argocd/istio-application.yaml

# 상태 확인
argocd app get istio-config
argocd app sync istio-config
```

**장점**:
- 누군가 실수로 `kubectl label namespace ecommerce istio-injection-` 명령어로 라벨을 제거해도
- ArgoCD가 자동으로 감지하고 복구합니다!

### 방법 3: Terraform (IaC) ⭐️

**장점**:
- 인프라를 코드로 관리
- 상태 추적 (terraform.tfstate)
- 다른 AWS 리소스와 함께 관리

**설정**:

`terraform/kubernetes/namespace-ecommerce.tf` (이미 생성됨):
```hcl
resource "kubernetes_namespace" "ecommerce" {
  metadata {
    name = "ecommerce"
    
    labels = {
      "istio-injection" = "enabled"  # ← Terraform이 관리
    }
  }
}
```

**배포**:
```bash
cd terraform/kubernetes

# 초기화
terraform init

# 계획 확인
terraform plan

# 배포
terraform apply
```

**유지**:
```bash
# Terraform이 관리하는 상태를 확인
terraform show

# 드리프트 감지 (실제 상태와 코드 비교)
terraform plan
```

### 방법 4: 독립 YAML 파일

**장점**:
- 간단하고 직접적
- kubectl만 있으면 됨
- GitOps 리포지토리에 포함 가능

**설정**:

`k8s-eks/istio/namespace.yaml` (이미 생성됨):
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: ecommerce
  labels:
    istio-injection: enabled  # ← 여기가 핵심!
```

**배포**:
```bash
# Git에 커밋
git add k8s-eks/istio/namespace.yaml
git commit -m "Add namespace definition with istio-injection label"
git push

# 배포
kubectl apply -f k8s-eks/istio/namespace.yaml
```

**ArgoCD와 함께 사용**:
```yaml
# argocd/namespace-app.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ecommerce-namespace
spec:
  source:
    path: k8s-eks/istio
    directory:
      include: namespace.yaml
  syncPolicy:
    automated:
      selfHeal: true
```

## 📊 방법 비교

| 방법 | 난이도 | GitOps | 자동복구 | 버전관리 | 권장 환경 |
|------|--------|--------|----------|----------|-----------|
| **Helm 차트** | 중간 | ✅ | ✅ | ✅ | 개발/스테이징/프로덕션 |
| **ArgoCD** | 중간 | ✅ | ✅ | ✅ | **프로덕션 (강력 권장)** |
| **Terraform** | 높음 | ✅ | ⚠️ | ✅ | 멀티 클라우드 환경 |
| **YAML 파일** | 낮음 | ✅ | ⚠️ | ✅ | 개발/테스트 |

## 🚀 권장 워크플로우

### 개발 환경
```bash
# Helm으로 빠르게 배포
cd k8s-eks/istio
./install-istio.sh
```

### 스테이징/프로덕션 환경
```bash
# ArgoCD로 GitOps 구성
kubectl apply -f k8s-eks/argocd/istio-application.yaml

# 변경사항은 Git에 커밋
git add helm/management-base/istio/values.yaml
git commit -m "Update Istio config"
git push

# ArgoCD가 자동으로 동기화
```

## ✅ 검증 방법

### 1. 네임스페이스 라벨 확인
```bash
kubectl get namespace ecommerce --show-labels

# 출력 예시:
# NAME        STATUS   AGE   LABELS
# ecommerce   Active   1d    istio-injection=enabled,...
```

### 2. 관리 방법 확인
```bash
# Helm으로 관리 중인지 확인
helm list -A | grep istio

# ArgoCD로 관리 중인지 확인
argocd app list | grep istio

# Terraform으로 관리 중인지 확인
terraform state list | grep namespace
```

### 3. 사이드카 주입 테스트
```bash
# 테스트 Pod 생성
kubectl run test-injection --image=nginx:1.25-alpine -n ecommerce

# 컨테이너 수 확인 (2개 예상: nginx + istio-proxy)
kubectl get pod test-injection -n ecommerce

# 정리
kubectl delete pod test-injection -n ecommerce
```

## 🔧 트러블슈팅

### 문제: Helm과 kubectl이 충돌

**증상**:
```
Error: INSTALLATION FAILED: rendered manifests contain a resource that already exists
```

**원인**: 네임스페이스가 kubectl로 이미 생성됨

**해결**:
```bash
# 기존 네임스페이스 삭제 (주의: 모든 리소스 삭제됨!)
kubectl delete namespace ecommerce

# 또는 Helm으로 import
helm import istio-config ./helm/management-base/istio -n ecommerce
```

### 문제: ArgoCD가 동기화 실패

**증상**:
```
ComparisonError: Namespace ecommerce already exists
```

**원인**: 네임스페이스가 ArgoCD 외부에서 생성됨

**해결**:
```bash
# 네임스페이스에 ArgoCD 레이블 추가
kubectl label namespace ecommerce \
  argocd.argoproj.io/instance=istio-config \
  --overwrite
```

### 문제: Terraform이 기존 리소스를 인식 못함

**증상**:
```
Error: Namespace already exists
```

**원인**: 네임스페이스가 Terraform 외부에서 생성됨

**해결**:
```bash
# 기존 리소스를 Terraform state로 import
terraform import kubernetes_namespace.ecommerce ecommerce

# 또는 새로 시작
kubectl delete namespace ecommerce
terraform apply
```

## 📚 관련 문서

- **Istio 설치 가이드**: [k8s-eks/istio/README.md](../k8s-eks/istio/README.md)
- **사이드카 문제 해결**: [ISTIO-SIDECAR-INJECTION-TROUBLESHOOTING.md](./ISTIO-SIDECAR-INJECTION-TROUBLESHOOTING.md)
- **ArgoCD 설정**: [k8s-eks/argocd/README.md](../k8s-eks/argocd/README.md)
- **Terraform 가이드**: [terraform/README.md](../terraform/README.md)

## 🎓 베스트 프랙티스

### 1. 단일 진실 공급원(Single Source of Truth)

하나의 방법으로 통일:
- ❌ 나쁨: kubectl + Helm + Terraform 혼용
- ✅ 좋음: ArgoCD만 사용 (Git이 SSoT)

### 2. 라벨 표준화

```yaml
labels:
  # Istio (필수)
  istio-injection: enabled
  
  # 관리 정보 (권장)
  environment: production
  managed-by: argocd
  team: platform
  
  # 비용 추적 (선택)
  cost-center: engineering
  project: ecommerce
```

### 3. 문서화

네임스페이스 정의에 주석 추가:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: ecommerce
  labels:
    istio-injection: enabled
  annotations:
    description: "E-commerce microservices with Istio"
    owner: "platform-team@company.com"
    docs: "https://wiki.company.com/ecommerce-infra"
```

### 4. 변경 관리

```bash
# 변경 전 백업
kubectl get namespace ecommerce -o yaml > namespace-backup.yaml

# 변경 사항을 Git에 먼저 커밋
git add <files>
git commit -m "Update namespace labels"
git push

# ArgoCD가 자동 배포하도록 대기
# 또는 수동 동기화
argocd app sync istio-config
```

## 🔒 보안 고려사항

### RBAC 설정

```yaml
# ArgoCD가 네임스페이스를 관리할 수 있도록 권한 부여
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: argocd-namespace-manager
rules:
  - apiGroups: [""]
    resources: ["namespaces"]
    verbs: ["get", "list", "watch", "create", "update", "patch"]
```

### Admission Controller

자동으로 라벨 추가:

```yaml
# ValidatingWebhook으로 라벨 검증
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingWebhookConfiguration
metadata:
  name: validate-istio-label
webhooks:
  - name: validate.istio.label
    rules:
      - operations: ["CREATE"]
        apiGroups: [""]
        apiVersions: ["v1"]
        resources: ["namespaces"]
```

---

**마지막 업데이트**: 2025-11-17  
**작성자**: Platform Team  
**검토자**: Istio 공식 문서 기반

