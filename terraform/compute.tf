data "yandex_compute_image" "ubuntu" {
  family = "ubuntu-2204-lts"
}

locals {
  hosts = {
    bastion       = { subnet = "public-a", ip = "10.70.1.10", memory = 1, disk = 10, public = true }
    prometheus    = { subnet = "private-a", ip = "10.70.10.20", memory = 2, disk = 10, public = false }
    elasticsearch = { subnet = "private-a", ip = "10.70.10.30", memory = 4, disk = 20, public = false }
    grafana       = { subnet = "public-a", ip = "10.70.1.20", memory = 1, disk = 10, public = true }
    kibana        = { subnet = "public-d", ip = "10.70.2.20", memory = 2, disk = 10, public = true }
  }
  base_cloud_config = {
    users = [{
      name                = "ubuntu"
      groups              = ["sudo"]
      sudo                = ["ALL=(ALL) NOPASSWD:ALL"]
      shell               = "/bin/bash"
      lock_passwd         = true
      ssh_authorized_keys = [var.ssh_public_key]
    }]
    ssh_pwauth = false
  }
}

resource "yandex_compute_instance" "service" {
  for_each    = local.hosts
  name        = "${var.prefix}-${each.key}"
  hostname    = "${var.prefix}-${each.key}"
  zone        = local.subnet_specs[each.value.subnet].zone
  platform_id = "standard-v3"
  labels      = { project = var.prefix, role = each.key }
  resources {
    cores         = 2
    memory        = each.value.memory
    core_fraction = 20
  }
  scheduling_policy {
    preemptible = true
  }
  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
      type     = "network-hdd"
      size     = each.value.disk
    }
  }
  network_interface {
    subnet_id          = yandex_vpc_subnet.course[each.value.subnet].id
    ip_address         = each.value.ip
    nat                = each.value.public
    security_group_ids = [yandex_vpc_security_group.service[each.key].id]
  }
  metadata = {
    user-data = "#cloud-config\n${yamlencode(local.base_cloud_config)}"
  }
  depends_on = [yandex_vpc_security_group_rule.ssh, yandex_vpc_security_group_rule.private]
}

resource "yandex_compute_instance_group" "web" {
  name               = "${var.prefix}-web"
  service_account_id = var.service_account_id
  labels             = { project = var.prefix }
  instance_template {
    name        = "${var.prefix}-web-{instance.index}"
    hostname    = "${var.prefix}-web-{instance.index}"
    platform_id = "standard-v3"
    labels      = { project = var.prefix, role = "web" }
    resources {
      cores         = 2
      memory        = 1
      core_fraction = 20
    }
    scheduling_policy {
      preemptible = true
    }
    boot_disk {
      mode = "READ_WRITE"
      initialize_params {
        image_id = data.yandex_compute_image.ubuntu.id
        type     = "network-hdd"
        size     = 10
      }
    }
    network_interface {
      network_id         = yandex_vpc_network.course.id
      subnet_ids         = [yandex_vpc_subnet.course["private-a"].id, yandex_vpc_subnet.course["private-d"].id]
      nat                = false
      security_group_ids = [yandex_vpc_security_group.service["web"].id]
    }
    metadata = {
      user-data = "#cloud-config\n${yamlencode(merge(local.base_cloud_config, {
        package_update = true
        packages       = ["ansible", "git"]
        write_files = [{
          path        = "/root/course-web-vars.yml"
          permissions = "0600"
          content = yamlencode({
            elasticsearch_ip  = local.hosts.elasticsearch.ip
            filebeat_password = var.filebeat_password
          })
        }]
        runcmd = [["ansible-pull", "-U", var.source_url, "-C", var.source_ref, "-d", "/opt/course-source", "-i", "localhost,", "-c", "local", "-e", "@/root/course-web-vars.yml", "ansible/web-bootstrap.yml"]]
      }))}"
    }
  }
  allocation_policy {
    zones = var.zones
  }
  deploy_policy {
    max_unavailable = 1
    max_expansion   = 1
  }
  scale_policy {
    auto_scale {
      initial_size           = 2
      min_zone_size          = 1
      max_size               = 3
      cpu_utilization_target = 50
      measurement_duration   = 60
      warmup_duration        = 600
      stabilization_duration = 180
    }
  }
  health_check {
    interval            = 10
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
    http_options {
      port = 80
      path = "/"
    }
  }
  application_load_balancer {
    target_group_name            = "${var.prefix}-web"
    ignore_health_checks         = true
    max_opening_traffic_duration = 1200
  }
  max_checking_health_duration = 1200
  depends_on                   = [yandex_vpc_security_group_rule.private]
}
