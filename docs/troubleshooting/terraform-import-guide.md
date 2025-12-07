# Terraform Import 트러블슈팅 가이드

## 개요

기존 AWS 리소스를 Terraform state에 import하는 과정에서 발생한 문제와 해결 방법을 문서화합니다.

**상황:** terraform.tfstate가 비어있어 기존 AWS 리소스가 Terraform으로 관리되지 않음

**목표:** 기존 리소스를 Terraform state에 import하여 IaC 관리 가능하게 만들기

---

## 발생한 문제

### 1. Provider 의존성 문제

**에러 메시지:**
```
Error: Invalid provider configuration

on main.tf line 60:
  60: provider "kubernetes" {

The configuration for provider["registry.terraform.io/hashicorp/kubernetes"]
depends on values that cannot be determined until apply.
```

**원인:**
```hcl
# main.tf
provider "kubernetes" {
  host = var.create_eks_cluster ? module.eks[0].cluster_endpoint : null
  #                               ↑ EKS가 state에 없으면 값을 알 수 없음
}
```

Terraform은 import 실행 시 모든 provider를 초기화해야 합니다.
kubernetes/helm provider가 EKS 모듈 output에 의존하고 있어서,
EKS가 state에 없으면 provider 초기화가 불가능합니다.

**해결:**
```hcl
# terraform.tfvars
create_eks_cluster = false  # 임시 비활성화
```

### 2. Count 의존성 문제

**에러 메시지:**
```
Error: Invalid count argument

on main.tf line 167, in resource "aws_route" "app_to_db":
  167:   count = length(module.vpc_app.private_route_table_ids)

The "count" value depends on resource attributes that cannot be determined
until apply, so Terraform cannot predict how many instances will be created.
```

**원인:**
```hcl
resource "aws_route" "app_to_db" {
  count = length(module.vpc_app.private_route_table_ids)
  #      ↑ VPC가 import 되어야 알 수 있는 값
}
```

Terraform은 plan 단계에서 count 값을 미리 계산해야 합니다.
하지만 count가 다른 모듈의 output에 의존하면 순환 의존성이 발생합니다.

**해결:**
```hcl
# 변경 전
count = length(module.vpc_app.private_route_table_ids)

# 변경 후 (변수 기반으로 변경)
count = length(var.vpc_app_private_subnets)
```

### 3. EKS 노드 그룹 동적 이름 문제

**문제:**
```
Terraform이 생성하는 노드 그룹 이름:
  core-on-{random_suffix}

실제 AWS의 노드 그룹 이름:
  core-on-2025120406513330660000000f
```

노드 그룹 이름에 랜덤 suffix가 포함되어 있어 import 경로를 정확히 지정하기 어렵습니다.

**해결:**
AWS CLI로 실제 이름 확인 후 import:
```bash
aws eks list-nodegroups --cluster-name c4-cluster --region ap-northeast-2

terraform import 'module.eks[0].module.eks_managed_node_group["core-on"].aws_eks_node_group.this[0]' \
  'c4-cluster:core-on-2025120406513330660000000f'
```

---

## Import 절차

### Step 1: 사전 준비

```bash
# 1. 현재 AWS 리소스 ID 수집
aws ec2 describe-vpcs --region ap-northeast-2 --query 'Vpcs[*].[VpcId,CidrBlock,Tags[?Key==`Name`].Value|[0]]' --output table
aws eks describe-cluster --name c4-cluster --region ap-northeast-2
aws rds describe-db-instances --region ap-northeast-2 --query 'DBInstances[*].[DBInstanceIdentifier,DBInstanceStatus]' --output table

# 2. terraform.tfvars 백업
cp terraform.tfvars terraform.tfvars.backup
```

### Step 2: 의존성 비활성화

```hcl
# terraform.tfvars
create_eks_cluster = false  # EKS 임시 비활성화
create_rds = false          # 필요시
create_elasticache = false  # 필요시
```

### Step 3: Count 의존성 수정

```hcl
# main.tf - 변경 전
resource "aws_route" "app_to_db" {
  count = length(module.vpc_app.private_route_table_ids)
  ...
}

# main.tf - 변경 후
resource "aws_route" "app_to_db" {
  count = length(var.vpc_app_private_subnets)  # 변수 기반
  ...
}
```

### Step 4: 단계별 Import

**순서가 중요합니다:**

```bash
cd /Users/castle/Workspace/c4ang-infra/external-services/terraform/production

# 1. VPC Import (기반 인프라)
terraform import 'module.vpc_app.aws_vpc.this[0]' vpc-0f26099f532f44c82
terraform import 'module.vpc_db.aws_vpc.this[0]' vpc-005baa0446f0c787c

# 2. Subnet Import
terraform import 'module.vpc_app.aws_subnet.public[0]' subnet-08adb9b5e9e980127
terraform import 'module.vpc_app.aws_subnet.public[1]' subnet-0d007efd4de9b541e
terraform import 'module.vpc_app.aws_subnet.public[2]' subnet-01e4fe7ff4fdaca98
terraform import 'module.vpc_app.aws_subnet.private[0]' subnet-082db99d913229b07
terraform import 'module.vpc_app.aws_subnet.private[1]' subnet-0c7a1a932d2e523ea
terraform import 'module.vpc_app.aws_subnet.private[2]' subnet-0c8fbe044cbca4545

# 3. Internet Gateway, NAT Gateway
terraform import 'module.vpc_app.aws_internet_gateway.this[0]' igw-0dcaeabb387188ee9
terraform import 'module.vpc_app.aws_nat_gateway.this[0]' nat-033fe4d9a14a3edbe

# 4. VPC Peering
terraform import 'aws_vpc_peering_connection.app_to_db' pcx-095c16bb098761295

# 5. EKS 활성화 후 Import
# terraform.tfvars에서 create_eks_cluster = true로 변경
terraform import 'module.eks[0].aws_eks_cluster.this[0]' c4-cluster

# 6. RDS Import
terraform import 'aws_db_instance.domain_rds["customer"]' c4-customer-db
# ... 나머지 RDS

# 7. ElastiCache Import
terraform import 'aws_elasticache_cluster.cache_redis[0]' c4-cache-redis

# 8. MSK Import
terraform import 'aws_msk_cluster.this[0]' arn:aws:kafka:ap-northeast-2:963403601423:cluster/c4-kafka-m7g/...
```

### Step 5: 검증

```bash
# Import 후 반드시 plan 확인
terraform plan

# 변경사항이 없어야 정상
# "No changes" 또는 최소한의 태그 변경만 있어야 함
```

---

## 실패 가능성 및 대응

### 높은 실패 가능성

| 리소스 | 실패 가능성 | 이유 |
|--------|------------|------|
| VPC | 낮음 | 단순한 리소스 |
| Subnet | 중간 | 인덱스 순서가 다를 수 있음 |
| EKS Cluster | 중간 | 많은 속성 차이 가능 |
| EKS Node Group | **높음** | 동적 이름, launch template 의존성 |
| RDS | 중간 | 비밀번호, 파라미터 그룹 차이 |
| MSK | 중간 | Configuration 버전 차이 |

### EKS 노드 그룹 Import 실패 시

**증상:**
```
Error: Resource already exists
또는
Error: importing ... NodeGroupName mismatch
```

**대응:**
1. 노드 그룹을 Terraform 관리에서 제외
2. 또는 새 노드 그룹 생성 후 기존 것 삭제 (다운타임 발생)

```hcl
# eks.tf - 노드 그룹 제외 예시
lifecycle {
  ignore_changes = all
}
```

### Plan에서 많은 변경사항 발생 시

**증상:**
```
Plan: 0 to add, 47 to change, 3 to destroy.
```

**대응:**
1. 변경사항이 태그만이면 안전
2. `destroy`가 있으면 **절대 apply하지 말 것**
3. tfvars 또는 tf 파일을 AWS 실제 값에 맞게 조정

```bash
# 어떤 리소스가 destroy 예정인지 확인
terraform plan | grep "will be destroyed"
```

---

## 대안: Import 포기하고 새로 시작

Import가 너무 복잡하면:

### Option A: Terraform 관리 포기
```
- 기존 리소스는 AWS 콘솔로 관리
- 새 리소스만 Terraform으로 관리
- destroy/create 스크립트는 AWS CLI 기반으로 유지
```

### Option B: 전체 재생성
```
- 다운타임 허용 시
- 기존 리소스 모두 삭제
- Terraform으로 처음부터 생성
- 데이터 백업 필수 (RDS 스냅샷, MSK 토픽 등)
```

### Option C: Terraformer 사용
```bash
# 기존 AWS 리소스에서 Terraform 코드 자동 생성
brew install terraformer
terraformer import aws --resources=vpc,eks,rds --regions=ap-northeast-2
```

---

## 현재 상태 (2025-12-08)

### 완료된 Import
- [x] VPC-APP (vpc-0f26099f532f44c82)

### 대기 중
- [ ] VPC-DB
- [ ] Subnets
- [ ] Internet Gateway
- [ ] NAT Gateway
- [ ] VPC Peering
- [ ] EKS Cluster
- [ ] EKS Node Groups
- [ ] RDS Instances (7개)
- [ ] ElastiCache (2개)
- [ ] MSK Cluster

### 수정된 파일
- `terraform.tfvars`: create_eks_cluster = false
- `main.tf`: count 의존성 수정 (line 167-178)

---

## 참고 명령어

```bash
# State 확인
terraform state list
terraform state show 'module.vpc_app.aws_vpc.this[0]'

# Import 취소 (state에서 제거)
terraform state rm 'module.vpc_app.aws_vpc.this[0]'

# 특정 리소스만 plan
terraform plan -target='module.vpc_app'

# Import 시 상세 로그
TF_LOG=DEBUG terraform import ...
```

---

## 연락처

문제 발생 시:
- Terraform 공식 문서: https://developer.hashicorp.com/terraform/cli/import
- AWS Provider 문서: https://registry.terraform.io/providers/hashicorp/aws/latest/docs
