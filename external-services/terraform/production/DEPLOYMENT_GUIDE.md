# Production 배포 요약

## 구성 요소
- 이중 VPC (APP, DB) + VPC 피어링
- Amazon EKS `c4-cluster` (관리형 노드 그룹 5종)
- PostgreSQL RDS (`aws_db_instance.airflow_db`)
- Airflow 로그용 S3 버킷
- NAT 게이트웨이 1개
- VPN 구성은 옵션 (기본 비활성화)

## 배포 순서
```bash
cd production
cp terraform.tfvars.example terraform.tfvars   # 필요 시 값 조정

terraform init
terraform plan
terraform apply
```

## 배포 확인
```bash
terraform output
aws eks update-kubeconfig --name c4-cluster --region ap-northeast-2
kubectl get nodes
kubectl get pods -A
```

## 부분 배포 예시
```bash
terraform apply -target=module.vpc_app -target=module.vpc_db -auto-approve    # 네트워크만
terraform apply -target=module.eks -auto-approve                               # EKS만
terraform apply -target=aws_db_instance.airflow_db -auto-approve              # RDS만
```

## 정리
```bash
terraform destroy
```

> Jenkins 및 Spark 관련 리소스는 제거되었습니다.


