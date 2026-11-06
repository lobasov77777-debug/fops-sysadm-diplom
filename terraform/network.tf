locals {
  subnet_specs = {
    public-a  = { zone = var.zones[0], cidr = "10.70.1.0/24", private = false }
    public-d  = { zone = var.zones[1], cidr = "10.70.2.0/24", private = false }
    private-a = { zone = var.zones[0], cidr = "10.70.10.0/24", private = true }
    private-d = { zone = var.zones[1], cidr = "10.70.20.0/24", private = true }
  }
}

resource "yandex_vpc_network" "course" {
  name = var.prefix
}

resource "yandex_vpc_gateway" "egress" {
  name = "${var.prefix}-egress"
  shared_egress_gateway {}
}

resource "yandex_vpc_route_table" "private" {
  name       = "${var.prefix}-private-egress"
  network_id = yandex_vpc_network.course.id
  static_route {
    destination_prefix = "0.0.0.0/0"
    gateway_id         = yandex_vpc_gateway.egress.id
  }
}

resource "yandex_vpc_subnet" "course" {
  for_each       = local.subnet_specs
  name           = "${var.prefix}-${each.key}"
  zone           = each.value.zone
  network_id     = yandex_vpc_network.course.id
  v4_cidr_blocks = [each.value.cidr]
  route_table_id = each.value.private ? yandex_vpc_route_table.private.id : null
}

resource "yandex_vpc_security_group" "service" {
  for_each   = toset(["bastion", "web", "prometheus", "grafana", "elasticsearch", "kibana", "postgres", "alb"])
  name       = "${var.prefix}-${each.key}"
  network_id = yandex_vpc_network.course.id
  egress {
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "yandex_vpc_security_group_rule" "bastion_public" {
  security_group_binding = yandex_vpc_security_group.service["bastion"].id
  direction              = "ingress"
  protocol               = "TCP"
  port                   = 22
  v4_cidr_blocks         = var.admin_cidrs
}

resource "yandex_vpc_security_group_rule" "ssh" {
  for_each               = toset(["web", "prometheus", "grafana", "elasticsearch", "kibana"])
  security_group_binding = yandex_vpc_security_group.service[each.key].id
  direction              = "ingress"
  protocol               = "TCP"
  port                   = 22
  security_group_id      = yandex_vpc_security_group.service["bastion"].id
}

locals {
  private_rules = {
    web-http         = { destination = "web", source = "alb", port = 80 }
    web-node         = { destination = "web", source = "prometheus", port = 9100 }
    web-nginx        = { destination = "web", source = "prometheus", port = 4040 }
    prom-grafana     = { destination = "prometheus", source = "grafana", port = 9090 }
    prom-bastion     = { destination = "prometheus", source = "bastion", port = 9090 }
    alert-bastion    = { destination = "prometheus", source = "bastion", port = 9093 }
    es-web           = { destination = "elasticsearch", source = "web", port = 9200 }
    es-prom          = { destination = "elasticsearch", source = "prometheus", port = 9200 }
    es-grafana       = { destination = "elasticsearch", source = "grafana", port = 9200 }
    es-kibana        = { destination = "elasticsearch", source = "kibana", port = 9200 }
    es-bastion       = { destination = "elasticsearch", source = "bastion", port = 9200 }
    postgres-prom    = { destination = "postgres", source = "prometheus", port = 6432 }
    postgres-bastion = { destination = "postgres", source = "bastion", port = 6432 }
  }
}

resource "yandex_vpc_security_group_rule" "private" {
  for_each               = local.private_rules
  security_group_binding = yandex_vpc_security_group.service[each.value.destination].id
  direction              = "ingress"
  protocol               = "TCP"
  port                   = each.value.port
  security_group_id      = yandex_vpc_security_group.service[each.value.source].id
}

locals {
  public_rules = {
    http    = { service = "alb", port = 80 }
    https   = { service = "alb", port = 443 }
    grafana = { service = "grafana", port = 3000 }
    kibana  = { service = "kibana", port = 5601 }
  }
}

resource "yandex_vpc_security_group_rule" "public" {
  for_each               = local.public_rules
  security_group_binding = yandex_vpc_security_group.service[each.value.service].id
  direction              = "ingress"
  protocol               = "TCP"
  port                   = each.value.port
  v4_cidr_blocks         = ["0.0.0.0/0"]
}

resource "yandex_vpc_security_group_rule" "alb_health" {
  security_group_binding = yandex_vpc_security_group.service["alb"].id
  direction              = "ingress"
  protocol               = "TCP"
  port                   = 30080
  predefined_target      = "loadbalancer_healthchecks"
}

resource "yandex_vpc_security_group_rule" "web_health" {
  security_group_binding = yandex_vpc_security_group.service["web"].id
  direction              = "ingress"
  protocol               = "TCP"
  port                   = 80
  predefined_target      = "loadbalancer_healthchecks"
}

resource "yandex_vpc_security_group_rule" "alb_internal" {
  security_group_binding = yandex_vpc_security_group.service["alb"].id
  direction              = "ingress"
  protocol               = "ANY"
  predefined_target      = "self_security_group"
}
