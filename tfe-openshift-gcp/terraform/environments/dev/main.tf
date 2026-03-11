# terraform/environments/prod/main.tf
terraform {
  required_version = ">= 1.7.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.25"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Recommended: use GCS backend for state
  backend "gcs" {
    bucket = "YOUR_TF_STATE_BUCKET"   # replace or pass via -backend-config
    prefix = "tfe-openshift/prod"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

# ── GCP Infrastructure ────────────────────────────────────────────────────────
module "gcp_infra" {
  source = "../../modules/gcp-infra"

  project_id       = var.project_id
  region           = var.region
  zone             = var.zone
  environment      = var.environment
  cluster_name     = var.ocp_cluster_name

  db_tier              = var.db_tier
  db_version           = var.db_version
  redis_tier           = var.redis_tier
  redis_memory_gb      = var.redis_memory_gb
  tfe_license_secret   = var.tfe_license_secret
  tfe_enc_secret       = var.tfe_encryption_password_secret
}

# ── OpenShift Cluster ─────────────────────────────────────────────────────────
module "openshift" {
  source = "../../modules/openshift"

  project_id         = var.project_id
  region             = var.region
  zone               = var.zone
  cluster_name       = var.ocp_cluster_name
  ocp_version        = var.ocp_version
  node_machine_type  = var.node_machine_type
  node_count         = var.node_count
  network            = module.gcp_infra.network_name
  subnetwork         = module.gcp_infra.subnetwork_name
  pods_range_name    = module.gcp_infra.pods_range_name
  services_range_name = module.gcp_infra.services_range_name
  tfe_sa_email       = module.gcp_infra.tfe_sa_email

  depends_on = [module.gcp_infra]
}

# ── Outputs ───────────────────────────────────────────────────────────────────
output "db_host"      { value = module.gcp_infra.db_host;      sensitive = false }
output "db_name"      { value = module.gcp_infra.db_name;      sensitive = false }
output "db_user"      { value = module.gcp_infra.db_user;      sensitive = false }
output "db_password"  { value = module.gcp_infra.db_password;  sensitive = true  }
output "redis_host"   { value = module.gcp_infra.redis_host;   sensitive = false }
output "redis_port"   { value = module.gcp_infra.redis_port;   sensitive = false }
output "gcs_bucket"   { value = module.gcp_infra.gcs_bucket;   sensitive = false }
output "tfe_sa_email" { value = module.gcp_infra.tfe_sa_email; sensitive = false }
output "cluster_endpoint" { value = module.openshift.endpoint; sensitive = false }
