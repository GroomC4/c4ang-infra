# Terraform 에러 해결 가이드

## 현재 발생한 에러 및 해결 방법

### 1. MSK Configuration 에러 ✅ 해결됨
**에러:**
```
Key 'log.retention.check.interval.ms' is not supported
```

**원인:** Kafka 3.7.x.kraft 버전에서 해당 설정 미지원

**해결:** `msk.tf`에서 `log.retention.check.interval.ms=300000` 라인 제거 완료

---

### 2. 기존 리소스 중복 에러 (Import 필요)

#### 2.1 IAM Roles
```bash
cd external-services/terraform/production

# EBS CSI Driver Role
terraform import 'aws_iam_role.ebs_csi_driver[0]' c4-AmazonEKS_EBS_CSI_DriverRole

# CNI Role
terraform import 'aws_iam_role.cni_role[0]' c4-AmazonEKS_CNI_Role

# Airflow IRSA Role
terraform import 'aws_iam_role.airflow_irsa[0]' c4-airflow-irsa
```

#### 2.2 S3 Buckets
```bash
# Airflow Logs Bucket
terraform import 'aws_s3_bucket.airflow_logs[0]' c4-airflow-logs-production-601423

# Tracking Log Bucket
terraform import 'aws_s3_bucket.tracking_log[0]' c4-tracking-log
```

#### 2.3 KMS Alias
```bash
terraform import 'module.eks[0].module.kms.aws_kms_alias.this["cluster"]' alias/eks/c4-eks-cluster
```

#### 전체 Import 스크립트
```bash
#!/usr/bin/env bash
set -euo pipefail

cd external-services/terraform/production

echo "=== IAM Roles Import ==="
terraform import 'aws_iam_role.ebs_csi_driver[0]' c4-AmazonEKS_EBS_CSI_DriverRole || true
terraform import 'aws_iam_role.cni_role[0]' c4-AmazonEKS_CNI_Role || true
terraform import 'aws_iam_role.airflow_irsa[0]' c4-airflow-irsa || true

echo "=== S3 Buckets Import ==="
terraform import 'aws_s3_bucket.airflow_logs[0]' c4-airflow-logs-production-601423 || true
terraform import 'aws_s3_bucket.tracking_log[0]' c4-tracking-log || true

echo "=== KMS Alias Import ==="
terraform import 'module.eks[0].module.kms.aws_kms_alias.this["cluster"]' alias/eks/c4-eks-cluster || true

echo "=== Import 완료 ==="
terraform plan
```

---

### 3. EKS Node Group 실패 (Unhealthy nodes)

**에러:**
```
NodeCreationFailure: Unhealthy nodes in the kubernetes cluster
```

**원인 분석:**
1. 노드가 클러스터에 조인하지 못함
2. IAM 역할 또는 보안 그룹 문제
3. 서브넷 또는 네트워크 설정 문제

**진단 명령:**
```bash
# 1. EKS 클러스터 상태 확인
aws eks describe-cluster --name c4-eks-cluster --region ap-northeast-2

# 2. Node Group 상태 확인
aws eks describe-nodegroup \
  --cluster-name c4-eks-cluster \
  --nodegroup-name core-on \
  --region ap-northeast-2

# 3. EC2 인스턴스 로그 확인
aws ec2 get-console-output \
  --instance-id i-02a1b4c066758bea4 \
  --region ap-northeast-2

# 4. CloudWatch Logs 확인
aws logs tail /aws/eks/c4-eks-cluster/cluster --follow
```

**해결 방법:**

#### Option 1: Node Group 재생성
```bash
# 실패한 Node Group 삭제
aws eks delete-nodegroup \
  --cluster-name c4-eks-cluster \
  --nodegroup-name core-on \
  --region ap-northeast-2

# Terraform으로 재생성
terraform apply -target='module.eks[0].module.eks_managed_node_group["core-on"]'
```

#### Option 2: Terraform State에서 제거 후 재생성
```bash
# State에서 제거
terraform state rm 'module.eks[0].module.eks_managed_node_group["core-on"].aws_eks_node_group.this[0]'
terraform state rm 'module.eks[0].module.eks_managed_node_group["monitoring"].aws_eks_node_group.this[0]'
terraform state rm 'module.eks[0].module.eks_managed_node_group["low-traffic"].aws_eks_node_group.this[0]'
terraform state rm 'module.eks[0].module.eks_managed_node_group["high-traffic"].aws_eks_node_group.this[0]'

# 재생성
terraform apply
```

#### Option 3: 수동 확인 및 수정
1. **IAM Role 확인:**
   ```bash
   aws iam get-role --role-name c4-eks-node-group-role
   ```

2. **Security Group 확인:**
   ```bash
   aws ec2 describe-security-groups \
     --filters "Name=tag:Name,Values=c4-eks-cluster-node*" \
     --region ap-northeast-2
   ```

3. **Subnet 확인:**
   ```bash
   aws ec2 describe-subnets \
     --filters "Name=tag:Name,Values=*private*" \
     --region ap-northeast-2
   ```

---

## 권장 실행 순서

### Step 1: MSK Configuration 수정 확인
```bash
cd external-services/terraform/production
git diff msk.tf
# log.retention.check.interval.ms 라인이 제거되었는지 확인
```

### Step 2: 기존 리소스 Import
```bash
# Import 스크립트 실행
bash /tmp/terraform_import_commands.sh
```

### Step 3: Terraform Plan 확인
```bash
terraform plan
# 변경사항이 예상대로인지 확인
```

### Step 4: EKS Node Group 문제 해결
```bash
# 실패한 Node Group 삭제
aws eks delete-nodegroup --cluster-name c4-eks-cluster --nodegroup-name core-on --region ap-northeast-2
aws eks delete-nodegroup --cluster-name c4-eks-cluster --nodegroup-name monitoring --region ap-northeast-2
aws eks delete-nodegroup --cluster-name c4-eks-cluster --nodegroup-name low-traffic --region ap-northeast-2
aws eks delete-nodegroup --cluster-name c4-eks-cluster --nodegroup-name high-traffic --region ap-northeast-2

# State에서 제거
terraform state rm 'module.eks[0].module.eks_managed_node_group["core-on"].aws_eks_node_group.this[0]'
terraform state rm 'module.eks[0].module.eks_managed_node_group["monitoring"].aws_eks_node_group.this[0]'
terraform state rm 'module.eks[0].module.eks_managed_node_group["low-traffic"].aws_eks_node_group.this[0]'
terraform state rm 'module.eks[0].module.eks_managed_node_group["high-traffic"].aws_eks_node_group.this[0]'

# 재생성
terraform apply
```

### Step 5: 검증
```bash
# EKS 노드 확인
kubectl get nodes

# MSK 확인
aws kafka list-clusters --region ap-northeast-2

# S3 버킷 확인
aws s3 ls | grep -E "airflow|tracking"
```

---

## 예방 조치

### 1. Terraform State 백업
```bash
cd external-services/terraform/production
terraform state pull > terraform.tfstate.backup.$(date +%Y%m%d_%H%M%S)
```

### 2. Import 전 리소스 확인
```bash
# IAM Roles
aws iam list-roles | grep -E "EBS_CSI|CNI|airflow"

# S3 Buckets
aws s3 ls | grep -E "airflow|tracking"

# KMS Aliases
aws kms list-aliases | grep eks
```

### 3. 점진적 적용
```bash
# 특정 리소스만 적용
terraform apply -target=aws_msk_configuration.msk_config
terraform apply -target=aws_s3_bucket.tracking_log
```

---

## 참고 문서
- [Terraform Import](https://developer.hashicorp.com/terraform/cli/import)
- [EKS Troubleshooting](https://docs.aws.amazon.com/eks/latest/userguide/troubleshooting.html)
- [MSK Configuration](https://docs.aws.amazon.com/msk/latest/developerguide/msk-configuration-properties.html)
