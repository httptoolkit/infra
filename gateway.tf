# Install the Gateway API CRDs (n.b. standard, not experimental)
data "http" "gateway_api_crds" {
  url = "https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.1/standard-install.yaml"
}

data "kubectl_file_documents" "gateway_api_crds" {
  content = data.http.gateway_api_crds.response_body
}

resource "kubectl_manifest" "gateway_api_crds" {
  for_each  = data.kubectl_file_documents.gateway_api_crds.manifests
  yaml_body = each.value

  server_side_apply = true
  wait              = true
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

  set = [{
    name  = "installCRDs"
    value = "true"
  }]
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
        email  = "admin@httptoolkit.com"
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
                    name      = "main-gateway"
                    namespace = "envoy-gateway-system"
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
    namespace = "envoy-gateway-system"
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
      namespace = "envoy-gateway-system"
    }
    spec = {
      secretName = "cert-httptoolkit-tech"
      issuerRef = {
        name = "letsencrypt-prod"
        kind = "ClusterIssuer"
      }
      dnsNames = [
        "public-endpoint.httptoolkit.tech",
      ]
    }
  })

  depends_on = [
    kubectl_manifest.letsencrypt_prod,
    kubectl_manifest.main_gateway
  ]
}

# Set up the Gateway itself:
resource "helm_release" "envoy_gateway" {
  name             = "envoy-gateway"
  repository       = "oci://docker.io/envoyproxy"
  chart            = "gateway-helm"
  version          = "v1.6.1"
  namespace        = "envoy-gateway-system"
  create_namespace = true
  wait             = true

  depends_on = [kubectl_manifest.gateway_api_crds]
}

resource "kubectl_manifest" "gateway_class" {
  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "GatewayClass"
    metadata = {
      name = "envoy-gateway"
    }
    spec = {
      controllerName = "gateway.envoyproxy.io/gatewayclass-controller"
    }
  })

  depends_on = [helm_release.envoy_gateway]
}

resource "scaleway_lb_ip" "gateway_ip" {
  zone = var.zone
}

resource "kubectl_manifest" "main_gateway" {
  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "Gateway"
    metadata = {
      name      = "main-gateway"
      namespace = "envoy-gateway-system"
    }
    spec = {
      gatewayClassName = "envoy-gateway"
      listeners = [
        {
          name          = "http"
          port          = 80
          protocol      = "HTTP"
          allowedRoutes = { namespaces = { from = "All" } }
        },
        {
          name          = "https-httptoolk-it"
          port          = 443
          protocol      = "HTTPS"
          hostname      = "*.e.httptoolk.it"
          allowedRoutes = { namespaces = { from = "All" } }
          tls = {
            mode            = "Terminate"
            certificateRefs = [{ kind = "Secret", name = "cert-httptoolk-it" }]
          }
        },
        {
          name          = "https-httptoolkit-tech"
          port          = 443
          protocol      = "HTTPS"
          hostname      = "*.httptoolkit.tech"
          allowedRoutes = { namespaces = { from = "All" } }
          tls = {
            mode            = "Terminate"
            certificateRefs = [{ kind = "Secret", name = "cert-httptoolkit-tech" }]
          }
        }
      ]
      infrastructure = {
        annotations = {
          "service.beta.kubernetes.io/scw-loadbalancer-type"         = "LB-S"
          "service.beta.kubernetes.io/scw-loadbalancer-zone"         = var.zone
          "service.beta.kubernetes.io/scw-loadbalancer-use-hostname" = "true"
          "service.beta.kubernetes.io/scw-loadbalancer-ip-id"        = scaleway_lb_ip.gateway_ip.id
        }
      }
    }
  })
  depends_on = [
    helm_release.envoy_gateway,
    kubectl_manifest.letsencrypt_prod,
    scaleway_lb_ip.gateway_ip
  ]
}