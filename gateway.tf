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

# Dummy cert (copying from fixed .it cert for now) to bootstrap
# httptoolkit.tech and get the gateway running.
resource "kubernetes_secret_v1" "cert_httptoolkit_tech_bootstrap" {
  metadata {
    name      = "cert-httptoolkit-tech"
    namespace = "envoy-gateway-system"
  }

  type = "kubernetes.io/tls"

  data = {
    "tls.crt" = var.httptoolk_it_tls_cert
    "tls.key" = var.httptoolk_it_tls_key
  }

  lifecycle {
    ignore_changes = [data, metadata]
  }

  depends_on = [helm_release.envoy_gateway]
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
        // TLS termination without proxying for *.e.httptoolk.it:
        {
          name     = "tls-httptoolk-it"
          port     = 443
          protocol = "TLS"
          hostname = "*.e.httptoolk.it"
          allowedRoutes = {
            namespaces = { from = "All" }
            kinds      = [{ kind = "TCPRoute" }]
          }
          tls = {
            mode            = "Terminate"
            certificateRefs = [{ kind = "Secret", name = "cert-httptoolk-it" }]
          }
        },
        // TLS termination but then raw TCP passthrough for the endpoint admin:
        {
          name          = "tls-endpoint-admin-httptoolkit-tech"
          port          = 443
          protocol      = "TLS"
          hostname      = "public-endpoint.httptoolkit.tech"
          allowedRoutes = { namespaces = { from = "All" } }
          tls = {
            mode            = "Terminate"
            certificateRefs = [{ kind = "Secret", name = "cert-httptoolkit-tech" }]
          }
        },
        // Normal HTTPS for all other httptoolkit.tech sites:
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
        }
      }
    }
  })
  depends_on = [
    helm_release.envoy_gateway,
    kubectl_manifest.letsencrypt_prod
  ]
}

# Force HTTP/2 for all endpoint admin TLS connections:
resource "kubectl_manifest" "force_h2_endpoint_admin_policy" {
  yaml_body = yamlencode({
    apiVersion = "gateway.envoyproxy.io/v1alpha1"
    kind       = "ClientTrafficPolicy"
    metadata = {
      name      = "force-h2-endpoint-admin"
      namespace = "envoy-gateway-system"
    }
    spec = {
      targetRef = {
        group       = "gateway.networking.k8s.io"
        kind        = "Gateway"
        name        = "main-gateway"
        sectionName = "tls-endpoint-admin-httptoolkit-tech"
      }
      tls = {
        alpnProtocols = ["h2"]
      }
    }
  })
}

# Force HTTP/2 for all endpoint admin TLS connections:
resource "kubectl_manifest" "allow_h2_public_endpoint_policy" {
  yaml_body = yamlencode({
    apiVersion = "gateway.envoyproxy.io/v1alpha1"
    kind       = "ClientTrafficPolicy"
    metadata = {
      name      = "allow-h2-public-endpoint"
      namespace = "envoy-gateway-system"
    }
    spec = {
      targetRef = {
        group       = "gateway.networking.k8s.io"
        kind        = "Gateway"
        name        = "main-gateway"
        sectionName = "tls-httptoolk-it"
      }
      tls = {
        alpnProtocols = ["http/1.1", "h2"]
      }
    }
  })
}