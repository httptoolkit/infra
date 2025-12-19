resource "kubernetes_namespace_v1" "certificates" {
  metadata {
    name = "certificates"
  }
}

# Set up Cert Manager & Let's Encrypt for TLS:
resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "oci://quay.io/jetstack/charts"
  chart            = "cert-manager"
  version          = "v1.19.2"
  namespace        = "certificates"
  create_namespace = true
  wait             = true

  values = [
    yamlencode({
      installCRDs = true

      extraArgs = [
        "--enable-gateway-api"
      ]
    })
  ]
}

resource "kubectl_manifest" "letsencrypt_prod" {
  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name      = "letsencrypt-prod"
      namespace = "certificates"
    }
    spec = {
      acme = {
        email  = "certificate-admin@httptoolkit.com"
        server = "https://acme-v02.api.letsencrypt.org/directory"
        privateKeySecretRef = {
          name = "letsencrypt-prod-account-key"
        }
        solvers = [
          {
            # All ACME is delegated via CNAMEs to acme-dns.httptoolkit.tech:
            dns01 = {
              cnameStrategy = "Follow"
              webhook = {
                groupName  = "acme.scaleway.com"
                solverName = "scaleway"
                config = {
                  zone      = "acme-dns.httptoolkit.tech"
                  projectId = var.project_id
                }
              }
            }
            selector = {
              dnsNames = [
                "httptoolkit.tech",
                "*.httptoolkit.tech"
              ]
            }
          }
        ]
      }
    }
  })

  depends_on = [
    helm_release.cert_manager,
    helm_release.cert_manager_scaleway_webhook
  ]
}

# Manually set up the TLS cert for *.e.httptoolk.it, for now:
resource "kubernetes_secret_v1" "cert_httptoolk_it" {
  metadata {
    name      = "cert-httptoolk-it"
    namespace = "certificates"
  }

  type = "kubernetes.io/tls"

  data = {
    "tls.crt" = var.httptoolk_it_tls_cert
    "tls.key" = var.httptoolk_it_tls_key
  }

  depends_on = [helm_release.envoy_gateway]
}

# We create a new app & API key for cert manager to automate our DNS:
resource "scaleway_iam_application" "acme_dns_bot" {
  name        = "acme-dns-bot"
  description = "Automated bot for Cert Manager DNS challenges"
}

resource "scaleway_iam_policy" "acme_dns_bot_policy" {
  name           = "acme-dns-bot-policy"
  application_id = scaleway_iam_application.acme_dns_bot.id

  rule {
    project_ids          = [var.project_id]
    permission_set_names = ["DomainsDNSFullAccess"]
  }
}

resource "scaleway_iam_api_key" "acme_dns_key" {
  application_id = scaleway_iam_application.acme_dns_bot.id
  description    = "Key for Cert Manager ACME DNS challenges"
}

resource "helm_release" "cert_manager_scaleway_webhook" {
  name       = "scaleway-webhook"
  repository = "https://helm.scw.cloud"
  chart      = "scaleway-certmanager-webhook"
  namespace  = "certificates"

  depends_on = [helm_release.cert_manager]

  values = [
    yamlencode({
      certManager = {
        namespace          = "certificates"
        serviceAccountName = "cert-manager"
      }

      secret = {
        accessKey = scaleway_iam_api_key.acme_dns_key.access_key
        secretKey = scaleway_iam_api_key.acme_dns_key.secret_key
      }
    })
  ]
}

resource "kubectl_manifest" "cert_wildcard_httptoolkit_tech" {
  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "cert-wildcard-httptoolkit-tech"
      namespace = "certificates"
    }
    spec = {
      secretName = "cert-wildcard-httptoolkit-tech"
      issuerRef = {
        name = "letsencrypt-prod"
        kind = "ClusterIssuer"
      }
      commonName = "httptoolkit.tech"
      dnsNames = [
        "httptoolkit.tech",
        "*.httptoolkit.tech"
      ]
    }
  })

  depends_on = [
    kubectl_manifest.letsencrypt_prod,
    kubectl_manifest.gateways
  ]
}