terraform {
  required_providers {
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
  }
}

# We create a separate namespace for each k8s project
resource "kubernetes_namespace_v1" "this" {
  metadata {
    name = var.name
  }
}

# Each namespaces gets a deployer service account
resource "kubernetes_service_account_v1" "deployer" {
  metadata {
    name      = "gh-actions-deployer"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }
}

resource "kubernetes_role_v1" "deployer" {
  metadata {
    name      = "gh-actions-deployer-role"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }

  # All permissions, but only in this namespace
  rule {
    api_groups = ["*"]
    resources  = ["*"]
    verbs      = ["*"]
  }
}

resource "kubernetes_role_binding_v1" "deployer" {
  metadata {
    name      = "gh-actions-deployer-binding"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.deployer.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.deployer.metadata[0].name
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }
}

resource "kubernetes_secret_v1" "deployer_token" {
  metadata {
    name      = "gh-actions-deployer-token"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
    annotations = {
      "kubernetes.io/service-account.name" = kubernetes_service_account_v1.deployer.metadata[0].name
    }
  }
  type = "kubernetes.io/service-account-token"
}
