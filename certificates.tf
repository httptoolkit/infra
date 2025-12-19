# Dummy cert (copying from fixed .it cert for now) to bootstrap
# httptoolkit.tech and get the gateway running.
resource "kubernetes_secret_v1" "cert_httptoolkit_tech_bootstrap" {
  metadata {
    name      = "cert-httptoolkit-tech"
    namespace = "gateway"
  }

  type = "kubernetes.io/tls"

  data = {
    "tls.crt" = var.httptoolk_it_tls_cert
    "tls.key" = var.httptoolk_it_tls_key
  }

  lifecycle {
    ignore_changes = [data, metadata]
  }
}

# Set up Cert Manager & Let's Encrypt for TLS:
resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "oci://quay.io/jetstack/charts"
  chart            = "cert-manager"
  version          = "v1.19.2"
  namespace        = "cert-manager"
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
      name = "letsencrypt-prod"
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
            http01 = {
              gatewayHTTPRoute = {
                parentRefs = [
                  {
                    name      = "primary-gateway"
                    namespace = "gateway"
                    kind      = "Gateway"
                  },
                  {
                    name      = "secondary-gateway"
                    namespace = "gateway"
                    kind      = "Gateway"
                  }
                ]
              }
            }
          }
        ]
      }
    }
  })

  depends_on = [helm_release.cert_manager]
}

# Set up our two certificates
resource "kubernetes_secret_v1" "cert_httptoolk_it" {
  metadata {
    name      = "cert-httptoolk-it"
    namespace = "gateway"
  }

  type = "kubernetes.io/tls"

  data = {
    "tls.crt" = var.httptoolk_it_tls_cert
    "tls.key" = var.httptoolk_it_tls_key
  }

  depends_on = [helm_release.envoy_gateway]
}

resource "kubectl_manifest" "cert_httptoolkit_tech" {
  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "cert-httptoolkit-tech"
      namespace = "gateway"
    }
    spec = {
      secretName = "cert-httptoolkit-tech"
      issuerRef = {
        name = "letsencrypt-prod"
        kind = "ClusterIssuer"
      }
      commonName = "httptoolkit.tech"
      dnsNames = [
        "httptoolkit.tech",
        "public-endpoint.httptoolkit.tech",
        "accounts-api.httptoolkit.tech"
      ]
    }
  })

  depends_on = [
    kubectl_manifest.letsencrypt_prod,
    kubectl_manifest.gateways
  ]
}