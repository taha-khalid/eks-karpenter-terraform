variable "cluster_name" { type = string }
variable "vpc_id" { type = string }
variable "subnet_ids" { type = list(string) }
variable "system_node_min" { type = number }
variable "system_node_max" { type = number }
variable "system_node_desired" { type = number }
