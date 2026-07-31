output "web_container_id" {
  description = "ID of the Terraform-managed Nginx container"
  value       = docker_container.web_server.id
}

output "application_container_id" {
  description = "ID of the internal application container"
  value       = docker_container.application_server.id
}

output "network_name" {
  description = "Name of the Terraform-managed Docker network"
  value       = docker_network.application.name
}

output "volume_name" {
  description = "Name of the Terraform-managed persistent volume"
  value       = docker_volume.nginx_cache.name
}

output "web_url" {
  description = "URL used to access the Nginx web server locally"
  value       = "http://localhost:${var.web_port}"
}

output "managed_containers" {
  description = "Names of all Terraform-managed containers"
  value = [
    docker_container.web_server.name,
    docker_container.application_server.name
  ]
}
