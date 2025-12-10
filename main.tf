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

module "public_url_server" {
  source = "./modules/k8s-project"
  name   = "public-url-server"
}

output "public_url_server_token" {
  value     = module.public_url_server.deployer_token
  sensitive = true
}

output "kubeconfig" {
  value     = scaleway_k8s_cluster.main.kubeconfig[0].config_file
  sensitive = true
}

output "ci_k8s_ca_cert" {
  value     = scaleway_k8s_cluster.main.kubeconfig[0].cluster_ca_certificate
  sensitive = true
}

output "ci_k8s_server" {
  value     = scaleway_k8s_cluster.main.kubeconfig[0].host
  sensitive = true
}