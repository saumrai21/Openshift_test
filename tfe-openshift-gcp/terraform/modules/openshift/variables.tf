# terraform/modules/openshift/variables.tf
variable "project_id"          { type = string }
variable "region"              { type = string }
variable "zone"                { type = string }
variable "cluster_name"        { type = string }
variable "ocp_version"         { type = string }
variable "node_machine_type"   { type = string }
variable "node_count"          { type = number }
variable "network"             { type = string }
variable "subnetwork"          { type = string }
variable "pods_range_name"     { type = string }
variable "services_range_name" { type = string }
variable "tfe_sa_email"        { type = string }
