module "vpc" {
  source = "../../modules/vpc"

  cluster_name = var.cluster_name
  vpc_cidr     = var.vpc_cidr
  environment  = var.environment
}

module "eks" {
  source = "../../modules/eks_control_plane"

  cluster_name        = var.cluster_name
  vpc_id              = module.vpc.vpc_id
  subnet_ids          = module.vpc.private_subnets
  system_node_min     = var.system_node_min
  system_node_max     = var.system_node_max
  system_node_desired = var.system_node_desired
}

module "karpenter_iam" {
  source = "../../modules/karpenter_iam"

  cluster_name = var.cluster_name
  depends_on   = [module.eks]
}

module "karpenter_resources" {
  source = "../../modules/karpenter_resources"

  cluster_name            = module.eks.cluster_name
  cluster_endpoint        = module.eks.cluster_endpoint
  node_role_name          = module.karpenter_iam.node_iam_role_name
  interruption_queue_name = module.karpenter_iam.queue_name
  karpenter_version       = var.karpenter_version
  cpu_limit               = var.karpenter_cpu_limit
  memory_limit            = var.karpenter_memory_limit

  depends_on = [module.eks, module.karpenter_iam]
}

module "bastion" {
  source = "../../modules/bastion"

  cluster_name                  = module.eks.cluster_name
  vpc_id                        = module.vpc.vpc_id
  public_subnet_id              = module.vpc.public_subnets[0]
  eks_cluster_security_group_id = module.eks.cluster_primary_security_group_id
}
