# Cluster configuration
variable "cluster_name" {
  description = "Name of the existing EKS cluster"
  type        = string
  default     = "hihypipe-eks-cluster" # 실제 클러스터명
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-2"
}

# Local state configuration (no backend variables needed)

# Karpenter configuration
variable "karpenter_version" {
  description = "Karpenter Helm chart version"
  type        = string
  default     = "0.16.3"
}

variable "karpenter_namespace" {
  description = "Kubernetes namespace for Karpenter"
  type        = string
  default     = "karpenter"
}

# LLM workload configuration
variable "llm_instance_type" {
  description = "Instance type for LLM workloads"
  type        = string
  default     = "t4g.medium"
}

variable "llm_root_volume_size" {
  description = "Root volume size for LLM nodes (GiB)"
  type        = number
  default     = 100
}

variable "llm_root_volume_iops" {
  description = "Root volume IOPS for LLM nodes"
  type        = number
  default     = 3000
}

variable "llm_root_volume_throughput" {
  description = "Root volume throughput for LLM nodes (MiB/s)"
  type        = number
  default     = 125
}

# Node configuration
variable "core_node_selector" {
  description = "Node selector for core workloads (Karpenter controller)"
  type        = map(string)
  default = {
    "node-role" = "core"
  }
}

# Tags
variable "additional_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default = {
    "Project"     = "karpenter-llm"
    "Environment" = "production"
    "Workload"    = "llm"
  }
}
