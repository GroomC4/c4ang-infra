# EC2NodeClass for Core workloads
resource "kubernetes_manifest" "karpenter_ec2nodeclass_core" {
  manifest = {
    apiVersion = "karpenter.k8s.aws/v1beta1"
    kind       = "EC2NodeClass"
    metadata = {
      name = "core-on-demand"
    }
    spec = {
      amiFamily = "AL2023"
      role      = aws_iam_role.karpenter_node.name

      subnetSelectorTerms = [
        {
          tags = {
            "karpenter.sh/discovery" = var.cluster_name
          }
        }
      ]

      securityGroupSelectorTerms = [
        {
          tags = {
            "karpenter.sh/discovery" = var.cluster_name
          }
        }
      ]

      blockDeviceMappings = [
        {
          deviceName = "/dev/xvda"
          ebs = {
            volumeSize          = "30Gi"
            volumeType          = "gp3"
            deleteOnTermination = true
            encrypted           = true
            iops                = 3000
            throughput          = 125
          }
        }
      ]

      tags = {
        Name                     = "karpenter-core-node"
        NodeType                 = "core-workload"
        workload                 = "core"
        "karpenter.sh/discovery" = var.cluster_name
      }
    }
  }

  depends_on = [
    aws_iam_instance_profile.karpenter_node,
    helm_release.karpenter
  ]
}

# EC2NodeClass for High-Traffic workloads
resource "kubernetes_manifest" "karpenter_ec2nodeclass_high_traffic" {
  manifest = {
    apiVersion = "karpenter.k8s.aws/v1beta1"
    kind       = "EC2NodeClass"
    metadata = {
      name = "high-traffic-on-demand"
    }
    spec = {
      amiFamily = "AL2023"
      role      = aws_iam_role.karpenter_node.name

      subnetSelectorTerms = [
        {
          tags = {
            "karpenter.sh/discovery" = var.cluster_name
          }
        }
      ]

      securityGroupSelectorTerms = [
        {
          tags = {
            "karpenter.sh/discovery" = var.cluster_name
          }
        }
      ]

      blockDeviceMappings = [
        {
          deviceName = "/dev/xvda"
          ebs = {
            volumeSize          = "50Gi"  # 고트래픽용 더 큰 디스크
            volumeType          = "gp3"
            deleteOnTermination = true
            encrypted           = true
            iops                = 4000
            throughput          = 250
          }
        }
      ]

      tags = {
        Name                     = "karpenter-high-traffic-node"
        NodeType                 = "high-traffic-workload"
        workload                 = "high-traffic"
        "karpenter.sh/discovery" = var.cluster_name
      }
    }
  }

  depends_on = [
    aws_iam_instance_profile.karpenter_node,
    helm_release.karpenter
  ]
}

# EC2NodeClass for Low-Traffic workloads
resource "kubernetes_manifest" "karpenter_ec2nodeclass_low_traffic" {
  manifest = {
    apiVersion = "karpenter.k8s.aws/v1beta1"
    kind       = "EC2NodeClass"
    metadata = {
      name = "low-traffic-on-demand"
    }
    spec = {
      amiFamily = "AL2023"
      role      = aws_iam_role.karpenter_node.name

      subnetSelectorTerms = [
        {
          tags = {
            "karpenter.sh/discovery" = var.cluster_name
          }
        }
      ]

      securityGroupSelectorTerms = [
        {
          tags = {
            "karpenter.sh/discovery" = var.cluster_name
          }
        }
      ]

      blockDeviceMappings = [
        {
          deviceName = "/dev/xvda"
          ebs = {
            volumeSize          = "20Gi"  # 저트래픽용 작은 디스크
            volumeType          = "gp3"
            deleteOnTermination = true
            encrypted           = true
            iops                = 3000
            throughput          = 125
          }
        }
      ]

      tags = {
        Name                     = "karpenter-low-traffic-node"
        NodeType                 = "low-traffic-workload"
        workload                 = "low-traffic"
        "karpenter.sh/discovery" = var.cluster_name
      }
    }
  }

  depends_on = [
    aws_iam_instance_profile.karpenter_node,
    helm_release.karpenter
  ]
}

# EC2NodeClass for Monitoring workloads
resource "kubernetes_manifest" "karpenter_ec2nodeclass_monitoring" {
  manifest = {
    apiVersion = "karpenter.k8s.aws/v1beta1"
    kind       = "EC2NodeClass"
    metadata = {
      name = "monitoring-on-demand"
    }
    spec = {
      amiFamily = "AL2023"
      role      = aws_iam_role.karpenter_node.name

      subnetSelectorTerms = [
        {
          tags = {
            "karpenter.sh/discovery" = var.cluster_name
          }
        }
      ]

      securityGroupSelectorTerms = [
        {
          tags = {
            "karpenter.sh/discovery" = var.cluster_name
          }
        }
      ]

      blockDeviceMappings = [
        {
          deviceName = "/dev/xvda"
          ebs = {
            volumeSize          = "100Gi"  # 모니터링용 대용량 디스크
            volumeType          = "gp3"
            deleteOnTermination = true
            encrypted           = true
            iops                = 5000
            throughput          = 500
          }
        }
      ]

      tags = {
        Name                     = "karpenter-monitoring-node"
        NodeType                 = "monitoring-workload"
        workload                 = "monitoring"
        role                     = "monitoring"
        "karpenter.sh/discovery" = var.cluster_name
      }
    }
  }

  depends_on = [
    aws_iam_instance_profile.karpenter_node,
    helm_release.karpenter
  ]
}
