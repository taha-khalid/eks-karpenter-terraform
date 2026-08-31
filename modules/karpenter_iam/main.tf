module "karpenter_iam" {
  source  = "terraform-aws-modules/eks/aws/modules/karpenter"
  version = "~> 20.0"

  cluster_name                    = var.cluster_name
  enable_pod_identity             = true
  create_pod_identity_association = true

  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  enable_spot_termination = true
}
