# NodePool for Core workloads (v1beta1 API) - EKS 노드 그룹과 일치
resource "kubernetes_manifest" "karpenter_nodepool_core" {
  manifest = {
    apiVersion = "karpenter.sh/v1beta1"
    kind       = "NodePool"
    metadata = {
      name = "core-on"
    }
    spec = {
      template = {
        metadata = {
          labels = {
            "workload"  = "core"
            "nodegroup" = "core-on"
            "node-type" = "core-on-demand"
          }
        }
        spec = {
          nodeClassRef = {
            apiVersion = "karpenter.k8s.aws/v1beta1"
            kind       = "EC2NodeClass"
            name       = "core-on-demand"
          }

          requirements = [
            {
              key      = "kubernetes.io/arch"
              operator = "In"
              values   = ["amd64"]  # EKS 노드 그룹과 일치
            },
            {
              key      = "karpenter.sh/capacity-type"
              operator = "In"
              values   = ["on-demand"]
            },
            {
              key      = "node.kubernetes.io/instance-type"
              operator = "In"
              values   = ["t3.medium", "t3.large", "t3.xlarge"]  # EKS 노드 그룹과 유사한 타입
            }
          ]

          taints = []
        }
      }

      limits = {
        cpu    = "16"   # 적절한 제한
        memory = "64Gi"
      }

      disruption = {
        consolidationPolicy = "WhenUnderutilized"
        expireAfter         = "30m"
      }

      weight = 100
    }
  }

  depends_on = [kubernetes_manifest.karpenter_ec2nodeclass_core]
}

# NodePool for High-Traffic workloads
resource "kubernetes_manifest" "karpenter_nodepool_high_traffic" {
  manifest = {
    apiVersion = "karpenter.sh/v1beta1"
    kind       = "NodePool"
    metadata = {
      name = "high-traffic"
    }
    spec = {
      template = {
        metadata = {
          labels = {
            "workload"  = "high-traffic"
            "nodegroup" = "high-traffic"
            "node-type" = "high-traffic-on-demand"
          }
        }
        spec = {
          nodeClassRef = {
            apiVersion = "karpenter.k8s.aws/v1beta1"
            kind       = "EC2NodeClass"
            name       = "high-traffic-on-demand"
          }

          requirements = [
            {
              key      = "kubernetes.io/arch"
              operator = "In"
              values   = ["amd64"]
            },
            {
              key      = "karpenter.sh/capacity-type"
              operator = "In"
              values   = ["on-demand"]
            },
            {
              key      = "node.kubernetes.io/instance-type"
              operator = "In"
              values   = ["t3.large", "t3.xlarge", "m5.large", "m5.xlarge"]
            }
          ]

          taints = []
        }
      }

      limits = {
        cpu    = "32"
        memory = "128Gi"
      }

      disruption = {
        consolidationPolicy = "WhenUnderutilized"
        expireAfter         = "15m"  # 트래픽 변동에 빠른 대응
      }

      weight = 90
    }
  }

  depends_on = [kubernetes_manifest.karpenter_ec2nodeclass_high_traffic]
}

# NodePool for Low-Traffic workloads
resource "kubernetes_manifest" "karpenter_nodepool_low_traffic" {
  manifest = {
    apiVersion = "karpenter.sh/v1beta1"
    kind       = "NodePool"
    metadata = {
      name = "low-traffic"
    }
    spec = {
      template = {
        metadata = {
          labels = {
            "workload"  = "low-traffic"
            "nodegroup" = "low-traffic"
            "node-type" = "low-traffic-on-demand"
          }
        }
        spec = {
          nodeClassRef = {
            apiVersion = "karpenter.k8s.aws/v1beta1"
            kind       = "EC2NodeClass"
            name       = "low-traffic-on-demand"
          }

          requirements = [
            {
              key      = "kubernetes.io/arch"
              operator = "In"
              values   = ["amd64"]
            },
            {
              key      = "karpenter.sh/capacity-type"
              operator = "In"
              values   = ["on-demand"]
            },
            {
              key      = "node.kubernetes.io/instance-type"
              operator = "In"
              values   = ["t3.small", "t3.medium", "t3.large"]
            }
          ]

          taints = []
        }
      }

      limits = {
        cpu    = "8"
        memory = "32Gi"
      }

      disruption = {
        consolidationPolicy = "WhenUnderutilized"
        expireAfter         = "60m"  # 저트래픽이므로 더 오래 유지
      }

      weight = 70
    }
  }

  depends_on = [kubernetes_manifest.karpenter_ec2nodeclass_low_traffic]
}

# NodePool for Monitoring workloads
resource "kubernetes_manifest" "karpenter_nodepool_monitoring" {
  manifest = {
    apiVersion = "karpenter.sh/v1beta1"
    kind       = "NodePool"
    metadata = {
      name = "monitoring"
    }
    spec = {
      template = {
        metadata = {
          labels = {
            "role"      = "monitoring"
            "workload"  = "monitoring"
            "nodegroup" = "monitoring"
            "node-type" = "monitoring-on-demand"
          }
        }
        spec = {
          nodeClassRef = {
            apiVersion = "karpenter.k8s.aws/v1beta1"
            kind       = "EC2NodeClass"
            name       = "monitoring-on-demand"
          }

          requirements = [
            {
              key      = "kubernetes.io/arch"
              operator = "In"
              values   = ["amd64"]
            },
            {
              key      = "karpenter.sh/capacity-type"
              operator = "In"
              values   = ["on-demand"]
            },
            {
              key      = "node.kubernetes.io/instance-type"
              operator = "In"
              values   = ["t3.large", "t3.xlarge", "m5.large", "m5.xlarge"]
            }
          ]

          taints = [
            {
              key    = "dedicated"
              value  = "monitoring"
              effect = "NoSchedule"
            }
          ]
        }
      }

      limits = {
        cpu    = "16"
        memory = "64Gi"
      }

      disruption = {
        consolidationPolicy = "WhenEmpty"  # 모니터링은 안정성 우선
        expireAfter         = "24h"        # 모니터링 노드는 오래 유지
      }

      weight = 80
    }
  }

  depends_on = [kubernetes_manifest.karpenter_ec2nodeclass_monitoring]
}
