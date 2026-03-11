# terraform/modules/gcp-infra/main.tf
# Provisions: VPC, Cloud SQL, Memorystore, GCS bucket, IAM, Secret Manager

locals {
  prefix = "${var.cluster_name}-${var.environment}"
}

# ── VPC ───────────────────────────────────────────────────────────────────────
resource "google_compute_network" "tfe" {
  name                    = "${local.prefix}-vpc"
  auto_create_subnetworks = false
  project                 = var.project_id
}

resource "google_compute_subnetwork" "tfe" {
  name          = "${local.prefix}-subnet"
  ip_cidr_range = "10.10.0.0/20"
  region        = var.region
  network       = google_compute_network.tfe.id
  project       = var.project_id

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.20.0.0/16"
  }
  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.30.0.0/20"
  }

  private_ip_google_access = true
}

resource "google_compute_router" "tfe" {
  name    = "${local.prefix}-router"
  region  = var.region
  network = google_compute_network.tfe.id
  project = var.project_id
}

resource "google_compute_router_nat" "tfe" {
  name                               = "${local.prefix}-nat"
  router                             = google_compute_router.tfe.name
  region                             = var.region
  project                            = var.project_id
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

# Private services peering for Cloud SQL / Redis
resource "google_compute_global_address" "private_services" {
  name          = "${local.prefix}-psa"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 20
  network       = google_compute_network.tfe.id
  project       = var.project_id
}

resource "google_service_networking_connection" "private_services" {
  network                 = google_compute_network.tfe.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_services.name]
}

# ── Cloud SQL (PostgreSQL) ────────────────────────────────────────────────────
resource "random_password" "db_password" {
  length  = 32
  special = false
}

resource "google_sql_database_instance" "tfe" {
  name             = "${local.prefix}-pg"
  database_version = var.db_version
  region           = var.region
  project          = var.project_id

  deletion_protection = true

  settings {
    tier              = var.db_tier
    availability_type = "REGIONAL"  # HA

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
      start_time                     = "03:00"
      transaction_log_retention_days = 7
      backup_retention_settings {
        retained_backups = 14
      }
    }

    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.tfe.id
    }

    database_flags {
      name  = "max_connections"
      value = "500"
    }
    database_flags {
      name  = "log_min_duration_statement"
      value = "1000"
    }

    maintenance_window {
      day  = 7
      hour = 4
    }
  }

  depends_on = [google_service_networking_connection.private_services]
}

resource "google_sql_database" "tfe" {
  name     = "tfe"
  instance = google_sql_database_instance.tfe.name
  project  = var.project_id
}

resource "google_sql_user" "tfe" {
  name     = "tfe"
  instance = google_sql_database_instance.tfe.name
  password = random_password.db_password.result
  project  = var.project_id
}

# ── Memorystore Redis ─────────────────────────────────────────────────────────
resource "google_redis_instance" "tfe" {
  name           = "${local.prefix}-redis"
  tier           = var.redis_tier
  memory_size_gb = var.redis_memory_gb
  region         = var.region
  project        = var.project_id

  authorized_network = google_compute_network.tfe.id
  redis_version      = "REDIS_7_0"
  display_name       = "TFE Redis Cache"

  redis_configs = {
    maxmemory-policy = "allkeys-lru"
  }

  maintenance_policy {
    weekly_maintenance_window {
      day = "SUNDAY"
      start_time { hours = 4; minutes = 0 }
    }
  }
}

# ── GCS Bucket (TFE blob storage) ─────────────────────────────────────────────
resource "google_storage_bucket" "tfe" {
  name                        = "${local.prefix}-tfe-data-${random_id.suffix.hex}"
  location                    = var.region
  project                     = var.project_id
  uniform_bucket_level_access = true
  force_destroy               = false

  versioning { enabled = true }

  lifecycle_rule {
    condition { num_newer_versions = 5 }
    action    { type = "Delete" }
  }

  encryption {
    default_kms_key_name = google_kms_crypto_key.tfe.id
  }
}

resource "random_id" "suffix" {
  byte_length = 4
}

# ── KMS for bucket encryption ─────────────────────────────────────────────────
resource "google_kms_key_ring" "tfe" {
  name     = "${local.prefix}-keyring"
  location = var.region
  project  = var.project_id
}

resource "google_kms_crypto_key" "tfe" {
  name     = "${local.prefix}-key"
  key_ring = google_kms_key_ring.tfe.id

  rotation_period = "7776000s" # 90 days

  lifecycle {
    prevent_destroy = true
  }
}

# ── IAM — TFE Workload Identity Service Account ────────────────────────────────
resource "google_service_account" "tfe" {
  account_id   = "${local.prefix}-tfe-sa"
  display_name = "TFE Workload Identity SA"
  project      = var.project_id
}

resource "google_storage_bucket_iam_member" "tfe_sa_storage" {
  bucket = google_storage_bucket.tfe.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.tfe.email}"
}

resource "google_secret_manager_secret_iam_member" "tfe_license" {
  project   = var.project_id
  secret_id = var.tfe_license_secret
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.tfe.email}"
}

resource "google_project_iam_member" "tfe_sa_sql" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.tfe.email}"
}

# Workload Identity binding — allows Kubernetes SA to impersonate GCP SA
resource "google_service_account_iam_member" "workload_identity" {
  service_account_id = google_service_account.tfe.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[openshift-tfe/tfe]"
}
