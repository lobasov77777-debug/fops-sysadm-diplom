output "hosts" {
  value = { for name, host in yandex_compute_instance.service : name => {
    id         = host.id
    private_ip = host.network_interface[0].ip_address
    public_ip  = host.network_interface[0].nat_ip_address
    disk_id    = host.boot_disk[0].disk_id
    zone       = host.zone
  } }
}

output "web_instances" {
  value = yandex_compute_instance_group.web.instances
}

output "instance_group_id" {
  value = yandex_compute_instance_group.web.id
}

output "alb_id" {
  value = yandex_alb_load_balancer.site.id
}

output "site_ip" {
  value = yandex_vpc_address.site.external_ipv4_address[0].address
}

output "site_domain" {
  value = local.site_domain
}

output "certificate_id" {
  value = yandex_cm_certificate.site.id
}

output "certificate_status" {
  value = yandex_cm_certificate.site.status
}

output "postgres_cluster_id" {
  value = yandex_mdb_postgresql_cluster.metrics.id
}

output "postgres_master_fqdn" {
  value = "c-${yandex_mdb_postgresql_cluster.metrics.id}.rw.mdb.yandexcloud.net"
}

output "postgres_hosts" {
  value = yandex_mdb_postgresql_cluster.metrics.host
}

output "snapshot_schedule_id" {
  value = yandex_compute_snapshot_schedule.daily.id
}
