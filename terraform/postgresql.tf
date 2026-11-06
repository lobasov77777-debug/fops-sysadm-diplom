resource "yandex_mdb_postgresql_cluster" "metrics" {
  name               = "${var.prefix}-metrics"
  environment        = "PRODUCTION"
  network_id         = yandex_vpc_network.course.id
  security_group_ids = [yandex_vpc_security_group.service["postgres"].id]
  labels             = { project = var.prefix }
  config {
    version                   = var.postgres_version
    autofailover              = true
    backup_retain_period_days = 7
    resources {
      resource_preset_id = "s2.micro"
      disk_type_id       = "network-ssd"
      disk_size          = 10
    }
  }
  host {
    name             = "metrics-a"
    zone             = var.zones[0]
    subnet_id        = yandex_vpc_subnet.course["private-a"].id
    assign_public_ip = false
  }
  host {
    name             = "metrics-d"
    zone             = var.zones[1]
    subnet_id        = yandex_vpc_subnet.course["private-d"].id
    assign_public_ip = false
  }
}

resource "yandex_mdb_postgresql_user" "prometheus" {
  cluster_id = yandex_mdb_postgresql_cluster.metrics.id
  name       = "prometheus"
  password   = var.postgres_password
}

resource "yandex_mdb_postgresql_database" "metrics" {
  cluster_id = yandex_mdb_postgresql_cluster.metrics.id
  name       = "metrics"
  owner      = yandex_mdb_postgresql_user.prometheus.name
}
