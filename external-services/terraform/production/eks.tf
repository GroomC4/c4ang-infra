# =============================================================================
# EKS Cluster and Managed Node Groups
# =============================================================================

# EKS Cluster
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  count = var.create_eks_cluster ? 1 : 0

  name               = local.eks_cluster_name
  kubernetes_version = "1.32"

  # EKS 애드온 설정
  addons = {
    coredns = {
      most_recent       = true
      resolve_conflicts = "OVERWRITE"
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent              = true
      before_compute           = true
      resolve_conflicts        = "OVERWRITE"
      service_account_role_arn = aws_iam_role.cni_role[0].arn
    }
    eks-pod-identity-agent = {
      most_recent = true
    }
  }

  # VPC 설정
  vpc_id                  = module.vpc_app.vpc_id
  subnet_ids              = module.vpc_app.private_subnets # Private Subnet 사용
  endpoint_public_access  = true
  endpoint_private_access = true


  # EKS Managed Node Groups (최소 사양 구성이며, Karpenter와 병행 사용 가능)
  eks_managed_node_groups = {
    core-on = {
      ami_type       = "AL2023_x86_64_STANDARD"
      capacity_type  = "ON_DEMAND"
      instance_types = var.core_node_group.instance_types
      min_size       = var.core_node_group.min_size
      desired_size   = var.core_node_group.desired_size
      max_size       = var.core_node_group.max_size
      disk_size      = var.core_node_group.disk_size

      labels = {
        workload  = "core"
        nodegroup = "core-on"
      }
    }

    high-traffic = {
      ami_type       = "AL2023_x86_64_STANDARD"
      capacity_type  = "ON_DEMAND"
      instance_types = var.high_traffic_node_group.instance_types
      min_size       = var.high_traffic_node_group.min_size
      desired_size   = var.high_traffic_node_group.desired_size
      max_size       = var.high_traffic_node_group.max_size
      disk_size      = var.high_traffic_node_group.disk_size

      labels = {
        workload  = "high-traffic"
        nodegroup = "high-traffic"
      }
    }

    low-traffic = {
      ami_type       = "AL2023_x86_64_STANDARD"
      capacity_type  = "ON_DEMAND"
      instance_types = var.low_traffic_node_group.instance_types
      min_size       = var.low_traffic_node_group.min_size
      desired_size   = var.low_traffic_node_group.desired_size
      max_size       = var.low_traffic_node_group.max_size
      disk_size      = var.low_traffic_node_group.disk_size

      labels = {
        workload  = "low-traffic"
        nodegroup = "low-traffic"
      }
    }

    stateful-storage = {
      ami_type       = "AL2023_x86_64_STANDARD"
      capacity_type  = "ON_DEMAND"
      instance_types = var.stateful_storage_node_group.instance_types
      min_size       = var.stateful_storage_node_group.min_size
      desired_size   = var.stateful_storage_node_group.desired_size
      max_size       = var.stateful_storage_node_group.max_size
      disk_size      = var.stateful_storage_node_group.disk_size

      labels = {
        workload  = "stateful"
        nodegroup = "stateful-storage"
      }

      taints = {
        stateful = {
          key    = "workload"
          value  = "stateful"
          effect = "NO_SCHEDULE"
        }
      }
    }

    kafka-storage = {
      ami_type       = "AL2023_x86_64_STANDARD"
      capacity_type  = "ON_DEMAND"
      instance_types = var.kafka_storage_node_group.instance_types
      min_size       = var.kafka_storage_node_group.min_size
      desired_size   = var.kafka_storage_node_group.desired_size
      max_size       = var.kafka_storage_node_group.max_size
      disk_size      = var.kafka_storage_node_group.disk_size

      labels = {
        workload  = "kafka"
        nodegroup = "kafka-storage"
      }

      taints = {
        kafka = {
          key    = "workload"
          value  = "kafka"
          effect = "NO_SCHEDULE"
        }
      }
    }
  }

  # EKS Access Entries (IAM 접근 제어)
  access_entries = {
    user_sunho_kim = {
      principal_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/sunho-kim"
      policy_associations = {
        admin = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }

    user_eunju_lee = {
      principal_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/eunju-lee"
      policy_associations = {
        admin = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }

    user_sanga_kim = {
      principal_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/sanga-kim"
      policy_associations = {
        admin = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }

    user_ingyu_han = {
      principal_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/ingyu-han"
      policy_associations = {
        admin = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }

    user_yujin_jung = {
      principal_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/yujin-jung"
      policy_associations = {
        admin = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
  }

  # 공통 태그
  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# 현재 AWS 계정 정보 조회
data "aws_caller_identity" "current" {}


# =============================================================================
# EBS CSI Driver Helm 차트 설치 (Kubernetes 1.33 호환성)
# =============================================================================

# EBS CSI Driver Helm 차트 설치
resource "helm_release" "ebs_csi_driver" {
  count = var.create_eks_cluster && var.create_k8s_resources ? 1 : 0

  name       = "aws-ebs-csi-driver"
  repository = "https://kubernetes-sigs.github.io/aws-ebs-csi-driver"
  chart      = "aws-ebs-csi-driver"
  namespace  = "kube-system"
  version    = "2.20.0" # 안정적인 버전 사용

  set {
    name  = "controller.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.ebs_csi_driver[0].arn
  }

  set {
    name  = "controller.serviceAccount.name"
    value = "ebs-csi-controller-sa"
  }

  depends_on = [
    module.eks,
    aws_iam_role.ebs_csi_driver
  ]
}

# =============================================================================
# EKS 클러스터 퍼블릭 액세스 CIDR 제한 (현재 IP만 허용)
# =============================================================================

# EKS 클러스터 설정을 업데이트하여 현재 IP만 허용
resource "null_resource" "restrict_eks_public_access" {
  count = var.create_eks_cluster && var.eks_public_access_enabled ? 1 : 0

  triggers = {
    cluster_name = module.eks[0].cluster_name
    current_ip   = chomp(data.http.current_ip.response_body)
  }

  provisioner "local-exec" {
    command = <<-EOT
      aws eks update-cluster-config \
        --region ${var.aws_region} \
        --name ${module.eks[0].cluster_name} \
        --resources-vpc-config endpointPublicAccess=true,endpointPrivateAccess=true,publicAccessCidrs=${chomp(data.http.current_ip.response_body)}/32
    EOT
  }

  depends_on = [module.eks]
}

