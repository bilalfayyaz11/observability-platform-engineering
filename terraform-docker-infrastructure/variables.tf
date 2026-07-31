variable "environment" {
  description = "Environment label applied to managed Docker resources"
  type        = string
  default     = "development"

  validation {
    condition = contains(
      ["development", "testing", "staging", "production"],
      var.environment
    )
    error_message = "Environment must be development, testing, staging, or production."
  }
}

variable "network_name" {
  description = "Name assigned to the Docker bridge network"
  type        = string
  default     = "terraform-network"

  validation {
    condition     = length(trimspace(var.network_name)) > 0
    error_message = "The Docker network name cannot be empty."
  }
}

variable "volume_name" {
  description = "Name assigned to the persistent Nginx cache volume"
  type        = string
  default     = "app-data-volume"

  validation {
    condition     = length(trimspace(var.volume_name)) > 0
    error_message = "The Docker volume name cannot be empty."
  }
}

variable "web_port" {
  description = "Local host port mapped to the Nginx HTTP port"
  type        = number
  default     = 8080

  validation {
    condition     = var.web_port >= 1024 && var.web_port <= 65535
    error_message = "The web port must be between 1024 and 65535."
  }
}

variable "restart_policy" {
  description = "Restart policy used by the managed containers"
  type        = string
  default     = "unless-stopped"

  validation {
    condition = contains(
      ["no", "always", "on-failure", "unless-stopped"],
      var.restart_policy
    )
    error_message = "Restart policy must be no, always, on-failure, or unless-stopped."
  }
}

variable "nginx_image" {
  description = "Nginx image used by the public web container"
  type        = string
  default     = "nginx:alpine"
}

variable "application_image" {
  description = "Apache HTTP image used by the internal application container"
  type        = string
  default     = "httpd:alpine"
}

variable "web_container_name" {
  description = "Name assigned to the Nginx container"
  type        = string
  default     = "terraform-nginx"
}

variable "application_container_name" {
  description = "Name assigned to the internal application container"
  type        = string
  default     = "terraform-application"
}
