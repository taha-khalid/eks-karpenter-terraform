resource "helm_release" "karpenter" {
  namespace        = "kube-system"
  name             = "karpenter"
  repository       = "oci://public.ecr.aws/karpenter"
  chart            = "karpenter"
  version          = var.karpenter_version
  create_namespace = false

  values = [
    <<YAML
settings:
    clusterName: ${var.cluster_name}
    clusterEndpoint: ${var.cluster_endpoint}
    interruptionQueue: ${var.interruption_queue_name}
tolerations:
    - key: "CriticalAddonsOnly"
      operator: "Exists"
      effect: "NoSchedule"
nodeSelector:
    workload.type: "system"
YAML
  ]
}

resource "kubectl_manifest" "ec2_node_class" {
  yaml_body = templatefile("${path.module}/manifests/ec2nodeclass.yaml", {
    cluster_name   = var.cluster_name
    node_role_name = var.node_role_name
  })

  depends_on = [helm_release.karpenter]

}

resource "kubectl_manifest" "node_pool" {
  yaml_body = templatefile("${path.module}/manifests/nodepool_stateless.yaml", {
    cpu_limit    = var.cpu_limit
    memory_limit = var.memory_limit
  })

  depends_on = [kubectl_manifest.ec2_node_class]
}
