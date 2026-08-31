output "ec2_node_class_name" {
  description = "The metadata name of the applied Karpenter EC2NodeClass CRD"
  value       = kubectl_manifest.ec2_node_class.name
}

output "node_pool_name" {
  description = "The metadata name of the applied Karpenter NodePool CRD"
  value       = kubectl_manifest.node_pool.name
}

output "karpenter_helm_release_status" {
  description = "Status of the deployed Karpenter Helm release"
  value       = helm_release.karpenter.status
}
