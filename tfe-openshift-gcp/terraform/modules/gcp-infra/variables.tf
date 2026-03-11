# terraform/modules/gcp-infra/variables.tf
variable "project_id"    { type = string }
variable "region"        { type = string }
variable "zone"          { type = string }
variable "environment"   { type = string }
variable "cluster_name"  { type = string }
variable "db_tier"       { type = string }
variable "db_version"    { type = string }
variable "redis_tier"    { type = string }
variable "redis_memory_gb" { type = number }
variable "tfe_license_secret" { type = string }
variable "tfe_enc_secret" { type = string }
