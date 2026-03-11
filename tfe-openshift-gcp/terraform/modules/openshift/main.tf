# terraform/modules/openshift/main.tf
# Provisions a GKE cluster configured to run OpenShift workloads
# For fully managed OCP (Red Hat OpenShift Dedicated on GCP), replace
# google_container_cluster with the OSD Terraform provider / ROSA equivalent.

resource "google_container_cluster" "ocp" {
  provider = google-beta

  name     = var.cluster_name
  location = var.region
  project  = var.project_id

  # Remove default node pool — managed separately
  remove_default_node_pool = true
  initial_node_count       = 1

  network    = var.network
  subnetwork = var.subnetwork

  networking_mode = "VPC_NATIVE"
  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_range_name
    services_secondary_range_name = var.services_range_name
  }

  # Workload Identity
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Private cluster
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = "0.0.0.0/0"
      display_name = "all"  # Restrict in production
    }
  }

  release_channel {
    channel = "STABLE"
  }

  min_master_version = var.ocp_version

  addons_config {
    http_load_balancing        { disabled = false }
    horizontal_pod_autoscaling { disabled = false }
    gce_persistent_disk_csi_driver_config { enabled = true }
    gcs_fuse_csi_driver_config { enabled = true }
  }

  maintenance_policy {
    recurring_window {
      start_time = "2024-01-07T04:00:00Z"
      end_time   = "2024-01-07T08:00:00Z"
      recurrence = "FREQ=WEEKLY;BYDAY=SU"
    }
  }

  logging_service    = "logging.googleapis.com/kubernetes"
  monitoring_service = "monitoring.googleapis.com/kubernetes"

  lifecycle {
    ignore_changes = [initial_node_count]
  }
}

# ── Node Pool ─────────────────────────────────────────────────────────────────
resource "google_container_node_pool" "tfe_nodes" {
  name     = "${var.cluster_name}-nodes"
  cluster  = google_container_cluster.ocp.id
  location = var.region
  project  = var.project_id

  node_count = var.node_count

  autoscaling {
    min_node_count = var.node_count
    max_node_count = var.node_count * 2
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type = var.node_machine_type
    disk_type    = "pd-ssd"
    disk_size_gb = 100
    image_type   = "COS_CONTAINERD"

    service_account = var.tfe_sa_email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    labels = {
      environment = "production"
      workload    = "tfe"
    }

    taint {
      key    = "workload"
      value  = "tfe"
      effect = "NO_SCHEDULE"
    }
  }

  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
    strategy        = "SURGE"
  }
}
