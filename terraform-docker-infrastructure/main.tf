terraform {
  required_version = ">= 1.6.0, < 2.0.0"

  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 4.5"
    }
  }
}

provider "docker" {
  host = "unix:///var/run/docker.sock"
}

resource "docker_network" "application" {
  name   = var.network_name
  driver = "bridge"

  labels {
    label = "managed-by"
    value = "terraform"
  }

  labels {
    label = "environment"
    value = var.environment
  }
}

resource "docker_volume" "nginx_cache" {
  name = var.volume_name

  labels {
    label = "managed-by"
    value = "terraform"
  }

  labels {
    label = "environment"
    value = var.environment
  }
}

resource "docker_image" "nginx" {
  name         = var.nginx_image
  keep_locally = false
}

resource "docker_image" "application" {
  name         = var.application_image
  keep_locally = false
}

resource "docker_container" "web_server" {
  name  = var.web_container_name
  image = docker_image.nginx.image_id

  restart = var.restart_policy

  ports {
    internal = 80
    external = var.web_port
    ip       = "127.0.0.1"
  }

  networks_advanced {
    name    = docker_network.application.name
    aliases = ["web"]
  }

  volumes {
    volume_name    = docker_volume.nginx_cache.name
    container_path = "/var/cache/nginx"
  }

  labels {
    label = "managed-by"
    value = "terraform"
  }

  labels {
    label = "service"
    value = "web"
  }

  depends_on = [
    docker_network.application,
    docker_volume.nginx_cache
  ]
}

resource "docker_container" "application_server" {
  name  = var.application_container_name
  image = docker_image.application.image_id

  restart = var.restart_policy

  networks_advanced {
    name    = docker_network.application.name
    aliases = ["application"]
  }

  labels {
    label = "managed-by"
    value = "terraform"
  }

  labels {
    label = "service"
    value = "application"
  }

  depends_on = [
    docker_network.application
  ]
}
