# Production 배포 가이드 (간략 버전)

## 1. 구성 요소
- `module.vpc_app` / `module.vpc_db`: 애플리케이션 VPC와 DB VPC
- `module.eks`: Amazon EKS 클러스터 (Kubernetes 1.32)
- 관리형 노드 그룹: `core-on`, `high-traffic`, `low-traffic`, `stateful-storage`, `kafka-storage`
- `aws_db_instance.airflow_db`: PostgreSQL RDS (프라이빗 서브넷)
- `aws_s3_bucket.airflow_logs`: 애플리케이션/모니터링 로그 저장소
- NAT 게이트웨이 1개 (APP VPC)
- Site-to-Site VPN (옵션, 기본 비활성화)

## 2. 준비 사항
```bash
aws configure                # 새 자격 증명 적용
terraform -version           # 1.0 이상
kubectl version --client
helm version
```

## 3. 배포 절차
```bash
cd production
cp terraform.tfvars.example terraform.tfvars   # 필요 시 값 수정

terraform init
terraform plan
terraform apply
```

## 4. 배포 후 점검
- `terraform output` 으로 EKS endpoint, RDS endpoint 등 확인
- `aws eks update-kubeconfig --name c4-cluster --region ap-northeast-2`
- `kubectl get nodes` / `kubectl get pods -A`

## 5. 부분 배포 (문제 발생 시)
```bash
# VPC 및 네트워크만
terraform apply -target=module.vpc_app -target=module.vpc_db -auto-approve

# RDS만
terraform apply -target=aws_db_instance.airflow_db -auto-approve

# EKS만
terraform apply -target=module.eks -auto-approve
```

## 6. 정리
```bash
terraform destroy
```

> Jenkins, Spark 관련 리소스는 제거되었습니다. 필요 시 별도 모듈로 추가하세요.


