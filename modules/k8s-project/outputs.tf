output "deployer_token" {
  value = kubernetes_secret_v1.deployer_token.data.token
}