# terraform/modules/gcp-infra/outputs.tf
output "network_name"      { value = google_compute_network.tfe.name }
output "subnetwork_name"   { value = google_compute_subnetwork.tfe.name }
output "pods_range_name"   { value = "pods" }
output "services_range_name" { value = "services" }

output "db_host"     { value = google_sql_database_instance.tfe.private_ip_address }
output "db_name"     { value = google_sql_database.tfe.name }
output "db_user"     { value = google_sql_user.tfe.name }
output "db_password" { value = random_password.db_password.result; sensitive = true }

output "redis_host" { value = google_redis_instance.tfe.host }
output "redis_port" { value = google_redis_instance.tfe.port }

output "gcs_bucket"   { value = google_storage_bucket.tfe.name }
output "tfe_sa_email" { value = google_service_account.tfe.email }
