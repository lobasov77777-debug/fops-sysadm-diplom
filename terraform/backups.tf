resource "yandex_compute_snapshot_schedule" "daily" {
  name             = "${var.prefix}-daily"
  retention_period = "168h"
  schedule_policy {
    expression = var.backup_cron
  }
  snapshot_spec {
    description = "Daily course backup retained for seven days"
    labels      = { project = var.prefix }
  }
  disk_ids = [for host in yandex_compute_instance.service : host.boot_disk[0].disk_id]
  # The reconciler includes and removes instance-group boot disks as the group changes.
  lifecycle {
    ignore_changes = [disk_ids]
  }
}
