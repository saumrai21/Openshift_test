# terraform/environments/prod/variables.tf

variable "project_id"   { type = string }
variable "region"       { type = string; default = "us-central1" }
variable "zone"         { type = string; default = "us-central1-a" }
variable "environment"  { type = string; default = "prod" }

variable "ocp_cluster_name" { type = string; default = "tfe-ocp" }
variable "ocp_version"      { type = string; default = "1.28" }
variable "node_machine_type" { type = string; default = "n2-standard-8" }
variable "node_count"        { type = number; default = 3 }

variable "tfe_hostname"   { type = string }
variable "tfe_version"    { type = string; default = "latest" }
variable "tfe_replicas"   { type = number; default = 2 }
variable "tfe_license_secret"            { type = string }
variable "tfe_encryption_password_secret" { type = string }

variable "db_tier"       { type = string; default = "db-custom-4-15360" }
variable "db_version"    { type = string; default = "POSTGRES_15" }

variable "redis_tier"      { type = string; default = "STANDARD_HA" }
variable "redis_memory_gb" { type = number; default = 4 }
