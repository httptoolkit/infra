terraform {
  required_version = ">= 1.10.7"
  required_providers {
    scaleway = {
      source  = "scaleway/scaleway"
      version = "~> 2.64"
    }
  }
}

provider "scaleway" {
  access_key = var.scw_access_key
  secret_key = var.scw_secret_key
  project_id = var.project_id

  profile = "disabled"
}

resource "scaleway_vpc_private_network" "main" {
  name = "htk-production-vpc"
  tags = ["htk", "production"]

  project_id = var.project_id
  region     = var.region
}

resource "scaleway_k8s_cluster" "main" {
  name                        = "htk-production-cluster"
  version                     = "1.34"
  cni                         = "cilium"
  delete_additional_resources = true
  private_network_id          = scaleway_vpc_private_network.main.id
  tags                        = ["htk", "production"]

  project_id = var.project_id
  region     = var.region

  auto_upgrade {
    enable                        = true
    maintenance_window_start_hour = 10
    maintenance_window_day        = "tuesday"
  }
}

resource "scaleway_k8s_pool" "main" {
  cluster_id  = scaleway_k8s_cluster.main.id
  name        = "htk-production-pool"
  node_type   = "PLAY2-NANO"
  region      = var.region
  zone        = var.zone
  size        = 1
  min_size    = 1
  max_size    = 3
  autoscaling = true
  tags        = ["htk", "production"]
}

resource "scaleway_registry_namespace" "main" {
  name        = "htk-registry"
  description = "Main registry for HTK production images"
  is_public   = true
  region      = var.region
  project_id  = var.project_id
}

output "kubeconfig" {
  value     = scaleway_k8s_cluster.main.kubeconfig[0].config_file
  sensitive = true
}

output "registry_endpoint" {
  value = scaleway_registry_namespace.main.endpoint
}