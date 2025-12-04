terraform {
  required_providers {
    scaleway = {
      source = "scaleway/scaleway"
    }
  }
}

provider "scaleway" {
  project_id = var.project_id
}

# 1. Private Network (VPC)
resource "scaleway_vpc_private_network" "main" {
  name = "k8s-db-private-network"
  tags = ["tofu-playground"]
}

# 2. Managed Database (PostgreSQL)
resource "scaleway_rdb_instance" "main" {
  name           = "playground-db"
  node_type      = "db-dev-s"
  engine         = "PostgreSQL-15"
  is_ha_cluster  = false
  disable_backup = true
  user_name      = "tofu_user"
  password       = var.db_password
  tags           = ["tofu-playground"]

  private_network {
    pn_id       = scaleway_vpc_private_network.main.id
    enable_ipam = true
  }
}

# 3. Kapsule Cluster (Control Plane)
resource "scaleway_k8s_cluster" "main" {
  name                        = "playground-cluster"
  version                     = "1.34"
  cni                         = "cilium"
  delete_additional_resources = true
  private_network_id          = scaleway_vpc_private_network.main.id
  tags                        = ["tofu-playground"]

  auto_upgrade {
    enable                        = true
    maintenance_window_start_hour = 10
    maintenance_window_day        = "tuesday"
  }
}

# 4. Kapsule Node Pool
resource "scaleway_k8s_pool" "main" {
  cluster_id  = scaleway_k8s_cluster.main.id
  name        = "default-pool"
  node_type   = "PLAY2-NANO"
  size        = 1
  min_size    = 1
  max_size    = 1
  autoscaling = true
  tags        = ["tofu-playground"]
}

output "db_endpoint" {
  value = scaleway_rdb_instance.main.private_network[0].ip
}