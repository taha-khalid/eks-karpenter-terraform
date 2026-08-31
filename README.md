Zero-Trust Amazon EKS with Karpenter

A production-oriented Terraform project for deploying a private Amazon EKS cluster with secure administrative access through AWS Systems Manager (SSM) and just-in-time worker-node provisioning through Karpenter.

The project uses reusable Terraform modules and separate environment roots for dev, staging, and prod.

Architecture

flowchart TD
    Developer["Developer workstation<br/>kubectl · Helm · Terraform"]
    Tunnel["SSM port-forwarding tunnel<br/>localhost:8443 → EKS:443"]

    subgraph VPC["AWS VPC"]
        Bastion["SSM bastion<br/>No inbound SSH"]
        API["Private EKS API endpoint"]
        System["Managed system node group<br/>Amazon Linux 2023"]
        Karpenter["Karpenter controller"]
        Dynamic["Dynamic workload nodes<br/>Bottlerocket · Spot / On-Demand"]
    end

    Developer --> Tunnel --> Bastion --> API
    API --> System
    System --> Karpenter
    Karpenter --> Dynamic

Key design choices

Private EKS API: Public Kubernetes API access is disabled.

SSM-only administration: The bastion exposes no inbound SSH port and requires no SSH keys.

Dedicated system capacity: Core add-ons and the Karpenter controller run on a fixed EKS managed node group.

Dynamic workload capacity: Karpenter launches appropriately sized Spot or On-Demand instances based on pending pod requirements.

Hardened nodes: Dynamically provisioned nodes use Bottlerocket, encrypted EBS volumes, and IMDSv2.

Pod-level AWS identity: Karpenter uses EKS Pod Identity instead of credentials stored in the cluster.

Interruption handling: EventBridge and SQS notify Karpenter about Spot interruption and instance lifecycle events.

Multi-environment layout: Development, staging, and production use the same modules with separate state and configuration.

Repository structure

.
├── environments/
│   ├── dev/
│   │   ├── main.tf
│   │   ├── outputs.tf
│   │   ├── providers.tf
│   │   ├── terraform.tfvars
│   │   └── variables.tf
│   ├── staging/
│   │   └── ...
│   └── prod/
│       └── ...
├── modules/
│   ├── bastion/
│   ├── eks_control_plane/
│   ├── karpenter_iam/
│   ├── karpenter_resources/
│   │   └── manifests/
│   │       ├── ec2nodeclass.yaml
│   │       └── nodepool-stateless.yaml
│   └── vpc/
├── README.md
└── track.log

Components

Component

Purpose

VPC

Multi-AZ networking, private worker subnets, public bastion subnet, routing, and NAT connectivity

EKS control plane

Private Kubernetes API, cluster encryption, add-ons, and managed system nodes

SSM bastion

Administrative path to the private EKS endpoint without inbound access

Karpenter IAM

Controller identity, node role, interruption queue, and event rules

Karpenter resources

Helm deployment, EC2NodeClass, and workload-specific NodePool resources

Prerequisites

An AWS account and credentials with permission to create VPC, EKS, EC2, IAM, KMS, EventBridge, and SQS resources

Terraform >= 1.5

AWS CLI v2

kubectl

AWS Session Manager plugin

Confirm the local tooling before deployment:

terraform version
aws --version
kubectl version --client
session-manager-plugin --version
aws sts get-caller-identity

Configuration

Select an environment and review its terraform.tfvars before applying:

aws_region   = "us-east-1"
environment  = "prod"
cluster_name = "prod-eks-karpenter"
vpc_cidr     = "10.100.0.0/16"

Do not commit secrets, credentials, account-specific identifiers, or sensitive backend configuration to the repository.

Deployment

Because the EKS API is private, deployment is completed in two phases. The first phase creates AWS infrastructure. The second runs Kubernetes and Helm operations through the SSM tunnel.

The examples below use production. Replace prod with dev or staging as required.

1. Initialize and review

cd environments/prod
terraform init
terraform fmt -check -recursive ../..
terraform validate
terraform plan -out=tfplan

2. Deploy the AWS-side foundation

terraform apply \
  -target=module.vpc \
  -target=module.eks \
  -target=module.karpenter_iam \
  -target=module.bastion

Targeted applies are used here only to bootstrap access to the private cluster. Always follow this step with a normal terraform plan and terraform apply so the final state converges completely.

3. Establish the SSM tunnel

Get the bastion instance ID and EKS endpoint from the environment outputs:

terraform output

Map the EKS endpoint hostname to the local loopback interface. This keeps TLS hostname validation intact while traffic is forwarded through SSM:

echo "127.0.0.1 <EKS_ENDPOINT_HOST>" | sudo tee -a /etc/hosts

Start the tunnel in a separate terminal and leave it running:

aws ssm start-session \
  --region <AWS_REGION> \
  --target <BASTION_INSTANCE_ID> \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters '{"host":["<EKS_ENDPOINT_HOST>"],"portNumber":["443"],"localPortNumber":["8443"]}'

4. Configure Kubernetes access

In another terminal, create the kubeconfig entry:

aws eks update-kubeconfig \
  --region <AWS_REGION> \
  --name <CLUSTER_NAME> \
  --alias <CLUSTER_NAME>

Point that kubeconfig cluster entry to the local tunnel:

kubectl config set-cluster <CLUSTER_NAME> \
  --server=https://<EKS_ENDPOINT_HOST>:8443

Verify access:

kubectl cluster-info
kubectl get nodes

Running aws eks update-kubeconfig again resets the server URL to port 443. Reapply the kubectl config set-cluster command while using the tunnel.

5. Complete the deployment

With the SSM tunnel still active:

terraform plan -out=tfplan
terraform apply tfplan

This installs Karpenter and applies the EC2NodeClass and NodePool resources.

Verification

Check the fixed system capacity:

kubectl get nodes -l workload.type=system -o wide

Check the Karpenter controller and custom resources:

kubectl get pods -n karpenter
kubectl get nodepools
kubectl get ec2nodeclasses
kubectl get nodeclaims

Follow controller activity while deploying a workload:

kubectl logs -n karpenter \
  -l app.kubernetes.io/name=karpenter \
  -c controller \
  --follow

Confirm that dynamically provisioned nodes satisfy the configured security requirements:

kubectl get nodes \
  -L karpenter.sh/capacity-type,kubernetes.io/arch,node.kubernetes.io/instance-type

Security controls

Private-only EKS control-plane endpoint

No inbound rules or SSH keys on the SSM bastion

Encrypted Kubernetes secrets using AWS KMS

EBS encryption for dynamically created nodes

IMDSv2 required with a hop limit of 1

Bottlerocket for a minimal, purpose-built worker-node operating system

IAM separation between the Karpenter controller and EC2 worker nodes

Discovery restricted through cluster-specific subnet and security-group tags

Dedicated, tainted system nodes for critical cluster services

Operations and cost considerations

Production uses multi-AZ networking and may create one NAT gateway per Availability Zone.

Spot capacity lowers workload cost but can be interrupted; disruption budgets and interruption handling reduce application impact.

Workloads should define realistic CPU and memory requests so Karpenter can make sound scheduling decisions.

Use PodDisruptionBudgets and topology spread constraints for highly available services.

Pin tested Terraform module, provider, EKS, and Karpenter versions before production deployment.

Review terraform plan carefully when promoting changes between environments.

Troubleshooting

Symptom

Likely cause

Resolution

EKS API request times out

The API is private and the tunnel is not active

Start the SSM port-forwarding session and retry

TargetNotConnected

The bastion cannot reach Systems Manager or its agent is not online

Check SSM agent status, instance profile, DNS, and outbound HTTPS access

SessionManagerPlugin is not found

The local plugin is missing

Install the Session Manager plugin and restart the shell

TLS certificate is valid for the EKS hostname, not localhost

Kubeconfig uses localhost directly

Map the EKS hostname to 127.0.0.1 and retain the original hostname in the URL

Connection refused on 127.0.0.1:443

update-kubeconfig restored the default port

Change the kubeconfig server URL back to https://<EKS_ENDPOINT_HOST>:8443

Pod Identity association reports cluster not found

Terraform dependency ordering is incomplete

Make the Karpenter IAM module depend on the EKS module

Managed node-group AMI is rejected

The configured AMI type is incompatible with the EKS version

Use a supported AMI such as AL2023_x86_64_STANDARD

The complete development and troubleshooting history is recorded in track.log.

Destroying an environment

Keep the SSM tunnel active while Terraform removes Kubernetes-managed resources, then destroy the remaining AWS infrastructure:

cd environments/<environment>
terraform plan -destroy -out=destroy.tfplan
terraform apply destroy.tfplan

Review the plan before approval. Destruction permanently removes the selected environment and may leave externally managed resources or retained storage that require separate cleanup.

Roadmap

Velero backup and disaster recovery

Runtime threat detection with Falco

Centralized metrics, logs, and alerts

Policy enforcement with Kyverno or OPA Gatekeeper

Automated validation and deployment through CI/CD

Additional NodePools for stateful, compute-intensive, and ARM64 workloads

Disclaimer

This project is intended as a production-oriented reference implementation. Review IAM permissions, network design, Kubernetes versions, Karpenter compatibility, quotas, and organizational security requirements before using it in a production account.