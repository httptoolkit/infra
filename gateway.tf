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

# Set up the gateways themselves:
resource "kubernetes_namespace_v1" "gateway" {
  metadata {
    name = "gateway"
  }
}

resource "helm_release" "envoy_gateway" {
  name             = "envoy-gateway"
  repository       = "oci://docker.io/envoyproxy"
  chart            = "gateway-helm"
  version          = "v1.6.1"
  namespace        = "gateway"
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

locals {
  gateway_topology = {
    "primary-gateway"   = var.primary_zone
    "secondary-gateway" = var.secondary_zone
  }

  gateway_listeners = [
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
        certificateRefs = [{ kind = "Secret", namespace = "certificates", name = "cert-wildcard-httptoolk-it" }]
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
        certificateRefs = [{ kind = "Secret", namespace = "certificates", name = "cert-wildcard-httptoolkit-tech" }]
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
        certificateRefs = [{ kind = "Secret", namespace = "certificates", name = "cert-wildcard-httptoolkit-tech" }]
      }
    },
    // Normal HTTPS for httptoolkit.com
    {
      name          = "https-httptoolkit-com"
      port          = 443
      protocol      = "HTTPS"
      hostname      = "httptoolkit.com"
      allowedRoutes = { namespaces = { from = "All" } }
      tls = {
        mode            = "Terminate"
        certificateRefs = [{ kind = "Secret", namespace = "certificates", name = "cert-httptoolkit-com" }]
      }
    }
  ]
}

resource "kubectl_manifest" "gateways" {
  for_each = local.gateway_topology

  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "Gateway"
    metadata = {
      name      = each.key
      namespace = "gateway"
    }
    spec = {
      gatewayClassName = "envoy-gateway"
      listeners        = local.gateway_listeners
      infrastructure = {
        annotations = {
          "service.beta.kubernetes.io/scw-loadbalancer-zone"              = each.value
          "service.beta.kubernetes.io/scw-loadbalancer-type"              = "LB-S"
          "service.beta.kubernetes.io/scw-loadbalancer-use-hostname"      = "true"
          "service.beta.kubernetes.io/scw-loadbalancer-proxy-protocol-v2" = "true"
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
  for_each = local.gateway_topology

  yaml_body = yamlencode({
    apiVersion = "gateway.envoyproxy.io/v1alpha1"
    kind       = "ClientTrafficPolicy"
    metadata = {
      name      = "force-h2-endpoint-admin-${each.key}"
      namespace = "gateway"
    }
    spec = {
      targetRef = {
        group       = "gateway.networking.k8s.io"
        kind        = "Gateway"
        name        = each.key
        sectionName = "tls-endpoint-admin-httptoolkit-tech"
      }
      tls = {
        alpnProtocols = ["h2"]
      }
    }
  })
  depends_on = [kubectl_manifest.gateways]
}

# Force HTTP/2 for all endpoint admin TLS connections:
resource "kubectl_manifest" "allow_h2_public_endpoint_policy" {
  for_each = local.gateway_topology

  yaml_body = yamlencode({
    apiVersion = "gateway.envoyproxy.io/v1alpha1"
    kind       = "ClientTrafficPolicy"
    metadata = {
      name      = "allow-h2-public-endpoint-${each.key}"
      namespace = "gateway"
    }
    spec = {
      targetRef = {
        group       = "gateway.networking.k8s.io"
        kind        = "Gateway"
        name        = each.key
        sectionName = "tls-httptoolk-it"
      }
      tls = {
        alpnProtocols = ["http/1.1", "h2"]
      }
    }
  })
  depends_on = [kubectl_manifest.gateways]
}

# Enable proxy protocol parsing, to handle proxy info from Scaleway LB:
resource "kubectl_manifest" "proxy_protocol_policy" {
  for_each = local.gateway_topology

  yaml_body = yamlencode({
    apiVersion = "gateway.envoyproxy.io/v1alpha1"
    kind       = "ClientTrafficPolicy"
    metadata = {
      name      = "enable-proxy-protocol-${each.key}"
      namespace = "gateway"
    }
    spec = {
      targetRef = {
        group = "gateway.networking.k8s.io"
        kind  = "Gateway"
        name  = each.key
      }
      enableProxyProtocol = true
    }
  })

  depends_on = [kubectl_manifest.gateways]
}