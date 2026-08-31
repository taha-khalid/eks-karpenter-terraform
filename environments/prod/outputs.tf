output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "karpenter_node_role_arn" {
  value = module.karpenter_iam.node_iam_role_arn
}

output "karpenter_node_pool_name" {
  description = "Name of the Karpenter NodePool handling dynamic scaling"
  value       = module.karpenter_resources.node_pool_name
}

output "karpenter_helm_status" {
  description = "Helm deployment status for Karpenter"
  value       = module.karpenter_resources.karpenter_helm_release_status
}

locals {
  eks_endpoint_host = replace(module.eks.cluster_endpoint, "https://", "")
}

output "connect_step_1_start_ssm_tunnel" {
  description = "Run this command in Terminal 1 to start port-forwarding traffic to the private EKS API"
  value       = "aws ssm start-session --target ${module.bastion.instance_id} --document-name AWS-StartPortForwardingSessionToRemoteHost --parameters '${jsonencode({ "host" : ["${local.eks_endpoint_host}"], "portNumber" : ["443"], "localPortNumber" : ["8443"] })}'"
}

output "connect_step_2_setup_kubeconfig" {
  description = "Run this in Terminal 2 to point your local kubectl to the forwarded tunnel"
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} && kubectl config set-cluster arn:aws:eks:${var.aws_region}:$(aws sts get-caller-identity --query Account --output text):cluster/${module.eks.cluster_name} --server=https://localhost:8443"
}
