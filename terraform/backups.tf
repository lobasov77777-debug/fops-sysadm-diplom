data "yandex_compute_instance" "web" {
  count       = var.enable_backups ? length(yandex_compute_instance_group.web.instances) : 0
  instance_id = yandex_compute_instance_group.web.instances[count.index].instance_id
}

resource "yandex_compute_snapshot_schedule" "daily" {
  count            = var.enable_backups ? 1 : 0
  name             = "${var.prefix}-daily"
  retention_period = "168h"
  schedule_policy {
    expression = "0 0 * * *"
  }
  snapshot_spec {
    description = "Daily course backup retained for seven days"
    labels      = { project = var.prefix }
  }
  disk_ids = concat(
    [for host in yandex_compute_instance.service : host.boot_disk[0].disk_id],
    [for host in data.yandex_compute_instance.web : host.boot_disk[0].disk_id]
  )
}
