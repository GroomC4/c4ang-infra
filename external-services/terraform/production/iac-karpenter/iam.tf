# Karpenter Controller IRSA Role
data "aws_iam_policy_document" "karpenter_controller_assume_role_policy" {
  statement {
    effect = "Allow"
    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.cluster.arn]
    }
    actions = ["sts:AssumeRoleWithWebIdentity"]
    condition {
      test     = "StringEquals"
      variable = "${replace(data.aws_iam_openid_connect_provider.cluster.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:${var.karpenter_namespace}:karpenter"]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(data.aws_iam_openid_connect_provider.cluster.url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "karpenter_controller" {
  name               = "KarpenterController-${var.cluster_name}"
  assume_role_policy = data.aws_iam_policy_document.karpenter_controller_assume_role_policy.json

  tags = merge(var.additional_tags, {
    Name                     = "KarpenterController-${var.cluster_name}"
    "karpenter.sh/discovery" = var.cluster_name
  })
}

# Attach required AWS managed policies to Karpenter Controller role
resource "aws_iam_role_policy_attachment" "karpenter_controller_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.karpenter_controller.name
}

resource "aws_iam_role_policy_attachment" "karpenter_controller_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.karpenter_controller.name
}

resource "aws_iam_role_policy_attachment" "karpenter_controller_ecr_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.karpenter_controller.name
}

resource "aws_iam_role_policy_attachment" "karpenter_controller_ssm_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.karpenter_controller.name
}

# Karpenter Controller custom policy for node management
resource "aws_iam_policy" "karpenter_controller" {
  name        = "KarpenterController-${var.cluster_name}"
  description = "Karpenter Controller policy for managing EC2 instances"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          # 기존 EC2 및 EKS 권한
          "ec2:DescribeImages",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeLaunchTemplates",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeInstanceTypeOfferings",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeSpotPriceHistory",
          "ec2:CreateLaunchTemplate",
          "ec2:CreateFleet",
          "ec2:CreateTags",
          "ec2:DeleteLaunchTemplate",
          "ec2:RunInstances",

          # SSM 및 Pricing 권한
          "ssm:GetParameter",
          "pricing:GetProducts",

          # EKS 권한
          "eks:DescribeCluster",

          # 누락된 핵심 IAM 권한들 (이 부분이 중요)
          "iam:GetInstanceProfile",
          "iam:CreateInstanceProfile",
          "iam:DeleteInstanceProfile",
          "iam:AddRoleToInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile",
          "iam:TagInstanceProfile",
          "iam:ListInstanceProfiles",
          "iam:ListInstanceProfilesForRole"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = [
          "arn:aws:iam::*:role/KarpenterNodeInstanceProfile-*",
          "arn:aws:iam::*:role/KarpenterNode*"
        ]
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "ec2.amazonaws.com"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:TerminateInstances",
          "ec2:DeleteTags"
        ]
        Resource = "*"
        Condition = {
          StringLike = {
            "ec2:ResourceTag/karpenter.sh/nodepool" = "*"
          }
        }
      }
    ]
  })

  tags = merge(var.additional_tags, {
    Name                     = "KarpenterController-${var.cluster_name}"
    "karpenter.sh/discovery" = var.cluster_name
  })
}

resource "aws_iam_role_policy_attachment" "karpenter_controller_policy" {
  policy_arn = aws_iam_policy.karpenter_controller.arn
  role       = aws_iam_role.karpenter_controller.name
}

# Additional Karpenter Controller permissions for AMI/SSM/EC2 operations
resource "aws_iam_policy" "karpenter_controller_extra" {
  name        = "${var.cluster_name}-KarpenterControllerExtra"
  description = "Additional permissions for Karpenter Controller"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:RunInstances",
          "ec2:CreateFleet",
          "ec2:CreateTags",
          "ec2:TerminateInstances",
          "ec2:Describe*",
          "ssm:GetParameter",
          "pricing:GetProducts"
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = aws_iam_role.karpenter_node.arn
      }
    ]
  })

  tags = merge(var.additional_tags, {
    Name                     = "${var.cluster_name}-KarpenterControllerExtra"
    "karpenter.sh/discovery" = var.cluster_name
  })
}

resource "aws_iam_role_policy_attachment" "karpenter_controller_extra" {
  policy_arn = aws_iam_policy.karpenter_controller_extra.arn
  role       = aws_iam_role.karpenter_controller.name
}

# IAM Role for Karpenter-managed nodes
resource "aws_iam_role" "karpenter_node" {
  name = "KarpenterNode-${var.cluster_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(var.additional_tags, {
    Name                     = "KarpenterNode-${var.cluster_name}"
    "karpenter.sh/discovery" = var.cluster_name
  })
}

# Attach required AWS managed policies to Karpenter Node role
resource "aws_iam_role_policy_attachment" "karpenter_node_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.karpenter_node.name
}

resource "aws_iam_role_policy_attachment" "karpenter_node_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.karpenter_node.name
}

resource "aws_iam_role_policy_attachment" "karpenter_node_ecr_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.karpenter_node.name
}

resource "aws_iam_role_policy_attachment" "karpenter_node_ssm_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.karpenter_node.name
}

# Instance Profile for Karpenter-managed nodes
resource "aws_iam_instance_profile" "karpenter_node" {
  name = "KarpenterNodeInstanceProfile-${var.cluster_name}"
  role = aws_iam_role.karpenter_node.name

  tags = merge(var.additional_tags, {
    Name                     = "KarpenterNodeInstanceProfile-${var.cluster_name}"
    "karpenter.sh/discovery" = var.cluster_name
  })
}
