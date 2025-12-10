terraform {
  required_version = ">= 1.10.7"
  required_providers {
    scaleway = {
      source  = "scaleway/scaleway"
      version = "~> 2.64"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.1"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.5"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.19.0"
    }
  }
}

provider "scaleway" {
  access_key = var.scw_access_key
  secret_key = var.scw_secret_key
  project_id = var.project_id

  profile = "disabled"
}

provider "helm" {
  kubernetes = {
    host                   = scaleway_k8s_cluster.main.kubeconfig[0].host
    token                  = scaleway_k8s_cluster.main.kubeconfig[0].token
    cluster_ca_certificate = base64decode(scaleway_k8s_cluster.main.kubeconfig[0].cluster_ca_certificate)
  }
}

provider "kubernetes" {
  host                   = scaleway_k8s_cluster.main.kubeconfig[0].host
  token                  = scaleway_k8s_cluster.main.kubeconfig[0].token
  cluster_ca_certificate = base64decode(scaleway_k8s_cluster.main.kubeconfig[0].cluster_ca_certificate)
}