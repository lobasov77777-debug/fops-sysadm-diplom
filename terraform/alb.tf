resource "yandex_vpc_address" "site" {
  name = "${var.prefix}-site"
  external_ipv4_address {
    zone_id = var.zones[0]
  }
}

locals {
  site_domain = "netology-anastasia.${replace(yandex_vpc_address.site.external_ipv4_address[0].address, ".", "-")}.sslip.io"
}

resource "yandex_cm_certificate" "site" {
  name    = "${var.prefix}-site"
  domains = [local.site_domain]
  managed {
    challenge_type  = "HTTP"
    challenge_count = 1
  }
}

resource "yandex_alb_backend_group" "web" {
  name = "${var.prefix}-web"
  http_backend {
    name             = "nginx"
    port             = 80
    weight           = 1
    target_group_ids = [yandex_compute_instance_group.web.application_load_balancer[0].target_group_id]
    healthcheck {
      interval            = "5s"
      timeout             = "2s"
      healthy_threshold   = 2
      unhealthy_threshold = 2
      http_healthcheck {
        path = "/"
      }
    }
  }
}

resource "yandex_alb_http_router" "site" {
  name = "${var.prefix}-router"
}

resource "yandex_alb_virtual_host" "site" {
  name           = "site"
  http_router_id = yandex_alb_http_router.site.id
  authority      = ["*"]
  dynamic "route" {
    for_each = { for challenge in yandex_cm_certificate.site.challenges :
      regex("https?://[^/]+(/.*)", challenge.http_url)[0] => challenge.http_content
      if challenge.http_url != ""
    }
    content {
      name = "acme-${substr(sha256(route.key), 0, 10)}"
      http_route {
        http_match {
          path {
            exact = route.key
          }
        }
        direct_response_action {
          status = 200
          body   = route.value
        }
      }
    }
  }
  route {
    name = "site"
    http_route {
      http_match {
        path {
          prefix = "/"
        }
      }
      http_route_action {
        backend_group_id = yandex_alb_backend_group.web.id
        timeout          = "15s"
      }
    }
  }
}

resource "yandex_alb_load_balancer" "site" {
  name               = "${var.prefix}-alb"
  network_id         = yandex_vpc_network.course.id
  security_group_ids = [yandex_vpc_security_group.service["alb"].id]
  allocation_policy {
    dynamic "location" {
      for_each = toset(["public-a", "public-d"])
      content {
        zone_id   = local.subnet_specs[location.value].zone
        subnet_id = yandex_vpc_subnet.course[location.value].id
      }
    }
  }
  listener {
    name = "http"
    endpoint {
      ports = [80]
      address {
        external_ipv4_address {
          address = yandex_vpc_address.site.external_ipv4_address[0].address
        }
      }
    }
    http {
      handler {
        http_router_id = yandex_alb_http_router.site.id
      }
    }
  }
  dynamic "listener" {
    for_each = var.enable_https ? [yandex_cm_certificate.site.id] : []
    content {
      name = "https"
      endpoint {
        ports = [443]
        address {
          external_ipv4_address {
            address = yandex_vpc_address.site.external_ipv4_address[0].address
          }
        }
      }
      tls {
        default_handler {
          certificate_ids = [listener.value]
          http_handler {
            http_router_id = yandex_alb_http_router.site.id
          }
        }
      }
    }
  }
  depends_on = [yandex_vpc_security_group_rule.alb_health, yandex_alb_virtual_host.site]
}
