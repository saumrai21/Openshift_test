# terraform/modules/openshift/outputs.tf
output "endpoint" {
  value = google_container_cluster.ocp.endpoint
}
output "cluster_ca" {
  value     = google_container_cluster.ocp.master_auth[0].cluster_ca_certificate
  sensitive = true
}
output "cluster_name" {
  value = google_container_cluster.ocp.name
}
