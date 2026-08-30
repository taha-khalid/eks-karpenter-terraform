module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name                    = var.cluster_name
  cluster_version                 = "1.30"
  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = false # Zero Trust Policy

  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

  create_kms_key = true
  cluster_encryption_config = {
    resources = ["secrets"]
  }

  enable_cluster_creator_admin_permissions = true

  eks_managed_node_groups = {
    system_nodes = {
      name          = "system-addons"
      instance_type = ["t3.medium"]
      min_size      = var.system_node_min
      max_size      = var.system_node_max
      desired_size  = var.system_node_desired

      subnet_ids = var.subnet_ids

      labels = { "workload.type" = "system" }
      taints = [{
        key    = "CriticalAddonsOnly"
        value  = "true"
        effect = "NO_SCHEDULE"
      }]

      metadata_options = {
        http_endpoint               = "enabled"
        http_tokens                 = "required"
        http_put_response_hop_limit = 1
      }
    }
  }
  node_security_group_tags = {
    "karpenter.sh/discovery" = var.cluster_name
  }
}
