# Test Environment Infrastructure

이 폴더는 테스트 환경을 위한 최소한의 Terraform 인프라 코드입니다.

## 🏗️ 주요 구성 요소

### 1. **VPC 구성**
- **VPC-APP**: 애플리케이션용 (Public/Private Subnets)
- **VPC-DB**: 데이터베이스용 (Private Subnets만)
- **VPC Peering**: App과 DB VPC 간 통신

### 2. **EKS 클러스터**
- **Kubernetes 버전**: 1.33
- **노드 그룹**: t3.medium 인스턴스 (테스트용)
- **노드 수**: 1-2개 (자동 스케일링)
- **디스크**: 20GB (테스트용 최소 사양)

### 3. **단방향 통신 설정**
- **PUBLIC → ONPREM**: 허용 (AWS에서 On-premises로 통신 가능)
- **ONPREM → PUBLIC**: 차단 (On-premises에서 AWS로 통신 불가)
- **VPN 서버**: 불필요 (AWS 기본 보안 정책으로 자동 적용)

## 🚀 배포 방법


### 자동 배포 (권장)
```bash
./deploy-eks.sh
```

### 수동 배포
1. `terraform.tfvars` 파일을 환경에 맞게 수정
2. `terraform init` 실행
3. `terraform plan` 실행하여 변경사항 확인
4. `terraform apply` 실행하여 인프라 배포

### 단계별 배포 (문제 발생 시)
```bash
# 1단계: 기본 인프라
terraform apply -target=module.vpc_app -auto-approve

# 2단계: IAM 역할
terraform apply -target=aws_iam_role.ebs_csi_driver -auto-approve

# 3단계: EKS 클러스터
terraform apply -target=module.eks -auto-approve

# 4단계: kubectl 설정
aws eks update-kubeconfig --region ap-northeast-2 --name c4-cluster

# 5단계: Helm 차트
terraform apply -target=helm_release.ebs_csi_driver -auto-approve

# 6단계: Kubernetes 리소스 (선택사항)
# terraform.tfvars에서 create_k8s_resources = true로 변경 후
terraform apply -target=kubernetes_namespace.airflow -auto-approve

# 7단계: 전체 배포
terraform apply -auto-approve
```

### 1. **사전 준비**
```bash
# AWS CLI 설정
aws configure

# Terraform 초기화
terraform init
```

### 2. **환경 변수 설정**
```bash
# 예시 파일을 복사
cp terraform.tfvars.example terraform.tfvars

# 실제 값으로 수정
```

### 3. **배포 실행**
```bash
# 계획 확인
terraform plan

# 배포 실행
terraform apply
```

### 4. **EKS 클러스터 접속**
```bash
# kubeconfig 업데이트
aws eks update-kubeconfig --name c4-cluster --region ap-northeast-2

# 클러스터 상태 확인
kubectl get nodes
kubectl get pods --all-namespaces
```

### 5. **VPN 접속 (VPN 연결 활성화 시)**
```bash
# VPN 설정 정보 확인
terraform output vpn_setup_info

# 터널 정보 확인
terraform output vpn_connection_tunnel1_address
terraform output vpn_connection_tunnel2_address

# Preshared Keys 확인 (민감 정보)
terraform output vpn_connection_tunnel1_preshared_key
terraform output vpn_connection_tunnel2_preshared_key
```

### 6. **배포 확인**
```bash
# 출력 정보 확인
terraform output

# 리소스 상태 확인
terraform show
```

## 🔒 보안 설정

### **단방향 통신**
- PUBLIC → ONPREM 통신 허용
- ONPREM → PUBLIC 통신 자동 차단
- 별도의 VPN 서버 불필요

### **네트워크 격리**
- VPC-DB는 완전 격리 (IGW, NAT Gateway 없음)
- VPC-APP에서만 VPC-DB 접근 가능

## 💰 비용 최적화

### **최소 구성**
- VPC: 2개 (APP, DB)
- NAT Gateway: 1개 (비용 절약)
- EKS Cluster: t3.medium 노드 (테스트용)
- VPN Server: 불필요 (비용 절약)
- DB Instance: 제거됨 (요청에 따라)

### **EKS 비용 절약**
- **인스턴스 타입**: t3.medium (private의 c5.2xlarge 대비 저렴)
- **노드 수**: 최대 2개 (private의 최대 3개 대비 절약)
- **디스크**: 20GB (private의 50GB 대비 절약)

### **통신 비용**
- VPN 서버 비용 절약 (인스턴스 불필요)
- AWS 기본 보안 정책 활용

## 🌐 네트워크 구성

### **CIDR 대역**
- **VPC-APP**: 172.20.128.0/17
- **VPC-DB**: 172.20.0.0/17
- **On-premises**: 10.128.0.0/19

### **Subnet 구성**
- **Public Subnets**: AZ-a, AZ-b, AZ-c
- **Private Subnets**: AZ-a, AZ-b, AZ-c
- **DB Subnets**: AZ-a, AZ-b, AZ-c (Private만)

## 🧹 정리 방법

### **전체 인프라 삭제**
```bash
terraform destroy
```

### **특정 리소스만 삭제**
```bash
# 특정 리소스만 삭제
terraform destroy -target=aws_vpc_peering_connection.app_to_db
```

## ⚠️ 주의사항

1. **테스트 환경**: 프로덕션 환경에는 적합하지 않음
2. **비용**: 테스트 완료 후 반드시 리소스 정리
3. **보안**: 기본 보안 설정만 적용됨
## 🔗 VPN 설정

### **Site-to-Site VPN 구성**
현재 설정된 On-premises 정보:
- **고객 게이트웨이 주소**: `112.221.225.163`
- **로컬 IPv4 네트워크 CIDR**: `10.128.0.0/19`

### **VPN 활성화 방법**
```bash
# terraform.tfvars 파일에서 VPN 활성화
create_vpn_connection = true
onprem_public_ip = "112.221.225.163"
onprem_bgp_asn = 65000
onprem_cidr = "10.128.0.0/19"

# VPN 리소스 생성
terraform apply
```

### **On-premises 라우터 설정**
VPN 연결 후 다음 정보로 라우터를 설정하세요:

```bash
# AWS 터널 정보 확인
terraform output vpn_setup_info
```

**라우터 설정 예시:**
- **Tunnel 1 Remote IP**: [AWS에서 제공하는 터널 1 IP]
- **Tunnel 2 Remote IP**: [AWS에서 제공하는 터널 2 IP]
- **Preshared Keys**: Terraform 출력에서 확인
- **암호화**: AES256, SHA256, DH Group 14
- **로컬 네트워크**: 10.128.0.0/19

### **통신 방향**
- **AWS → On-premises**: 허용 (VPN 터널을 통해)
- **On-premises → AWS**: 차단 (보안 정책 유지)

## 🔧 문제 해결

### **일반적인 문제들**
1. **VPC Peering 연결 실패**: 라우팅 테이블 확인
2. **VPN 연결 실패**: On-premises 라우터 설정 확인
3. **통신 문제**: VPC Flow Logs와 보안 그룹 설정 확인

### **로그 확인**
```bash
# VPC Flow Logs 확인
aws logs describe-log-groups --log-group-name-prefix "/aws/vpc/flowlogs"
```

## 🛠️ 도구 설정

### Infracost (비용 분석)

비용 분석 도구 설정 방법:

#### 방법 1: GitHub App (권장) ⭐

가장 간단한 방법입니다. CI/CD 설정 없이 자동으로 Pull Request에 비용 정보를 표시합니다.

1. https://www.infracost.io/cloud 접속
2. GitHub 계정으로 로그인
3. Settings > Integrations > GitHub에서 리포지토리 선택
4. 테스트 Pull Request 생성하여 확인

#### 방법 2: CLI (로컬)

로컬에서 비용을 분석하고 싶다면:

```bash
# 1. 설치
brew install infracost

# 2. API 키 설정
export INFRACOST_API_KEY=your_api_key

# 3. 비용 분석
infracost breakdown --path . --terraform-var-file=only-rds.tfvars
```

자세한 설정 방법: [TOOLS_SETUP.md](./TOOLS_SETUP.md) 또는 [docs/INFRACOST_SETUP.md](./docs/INFRACOST_SETUP.md)

### Brainboard (인프라 시각화)

인프라 시각화 도구 설정 방법:

1. https://www.brainboard.co/ 접속
2. 계정 생성 (GitHub 로그인 권장)
3. 새 프로젝트 생성
4. Terraform 파일 업로드 또는 Git 리포지토리 연동

자세한 설정 방법: [TOOLS_SETUP.md](./TOOLS_SETUP.md) 또는 [docs/BRAINBOARD_SETUP.md](./docs/BRAINBOARD_SETUP.md)

### 기타 도구

- **Terraform-docs**: 문서 자동 생성
- **TFLint**: 코드 품질 검사
- **Checkov**: 보안 검사

## 📞 지원

문제가 발생하면 다음을 확인하세요:
1. Terraform 상태 파일
2. AWS CloudTrail 로그
4. VPC Flow Logs
5. [도구 설정 가이드](./TOOLS_SETUP.md)
