# Karpenter Helm Chart Installation
resource "helm_release" "karpenter" {
  name       = "karpenter"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = "0.37.0"
  namespace  = var.karpenter_namespace

  create_namespace = true

  values = [
    yamlencode({
      settings = {
        clusterName       = var.cluster_name
        clusterEndpoint   = data.aws_eks_cluster.cluster.endpoint
        interruptionQueue = ""
        aws = {
          defaultInstanceProfile = aws_iam_instance_profile.karpenter_node.name
        }
      }
      # Controller environment variables
      controller = {
        env = [
          {
            name  = "CLUSTER_NAME"
            value = var.cluster_name
          },
          {
            name  = "CLUSTER_ENDPOINT"
            value = data.aws_eks_cluster.cluster.endpoint
          }
        ]
      }
      serviceAccount = {
        annotations = {
          "eks.amazonaws.com/role-arn" = aws_iam_role.karpenter_controller.arn
        }
      }
      # Pin Karpenter controller to core nodes
      nodeSelector = var.core_node_selector
      tolerations = [
        {
          key      = "node-role"
          operator = "Equal"
          value    = "core"
          effect   = "NoSchedule"
        }
      ]
      affinity = {
        nodeAffinity = {
          requiredDuringSchedulingIgnoredDuringExecution = {
            nodeSelectorTerms = [
              {
                matchExpressions = [
                  {
                    key      = "node-role"
                    operator = "In"
                    values   = ["core"]
                  }
                ]
              }
            ]
          }
        }
      }
      # Resource limits for controller
      resources = {
        limits = {
          cpu    = "1"
          memory = "1Gi"
        }
        requests = {
          cpu    = "100m"
          memory = "100Mi"
        }
      }
      # Logging configuration
      logLevel = "info"
      # Metrics configuration
      metrics = {
        bindAddress = "0.0.0.0:8080"
      }
    })
  ]

  depends_on = [
    aws_iam_role.karpenter_controller,
    aws_iam_instance_profile.karpenter_node
  ]

  # Wait for deployment to be ready
  wait          = true
  wait_for_jobs = true
  timeout       = 300
}
