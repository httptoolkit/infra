# Fetch, split & install the Gateway API CRDs
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


resource "kubectl_manifest" "main_gateway" {
  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "Gateway"
    metadata = {
      name      = "main-gateway"
      namespace = "envoy-gateway-system"
      annotations = {
        "cert-manager.io/cluster-issuer" = "letsencrypt-prod"
      }
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
          name          = "https-httptoolkit-it"
          port          = 443
          protocol      = "HTTPS"
          hostname      = "*.httptoolk.it"
          allowedRoutes = { namespaces = { from = "All" } }
          tls = {
            mode            = "Terminate"
            certificateRefs = [{ kind = "Secret", name = "cert-httptoolkit-it" }]
          }
        },
        {
          name          = "app-port-4000"
          port          = 4000
          protocol      = "HTTP"
          allowedRoutes = { namespaces = { from = "All" } }
        },
        {
          name          = "app-port-4040"
          port          = 4040
          protocol      = "HTTP"
          allowedRoutes = { namespaces = { from = "All" } }
        }
      ]
      infrastructure = {
        annotations = {
          "service.beta.kubernetes.io/scw-loadbalancer-use-hostname" = "true"
        }
      }
    }
  })
  depends_on = [helm_release.envoy_gateway, kubectl_manifest.letsencrypt_prod]
}