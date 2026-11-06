param(
    [Parameter(Mandatory)][string]$TerraformOutputs,
    [Parameter(Mandatory)][string]$ServiceSecrets,
    [Parameter(Mandatory)][string]$Destination,
    [Parameter(Mandatory)][string]$FolderId
)
$ErrorActionPreference = 'Stop'
$outputs = Get-Content -LiteralPath $TerraformOutputs -Raw | ConvertFrom-Json -AsHashtable
$secrets = Get-Content -LiteralPath $ServiceSecrets -Raw | ConvertFrom-Json -AsHashtable
$hosts = $outputs.hosts.value
$children = @{}
$containers = @{
    elasticsearch = @('course-elasticsearch')
    prometheus    = @('course-prometheus', 'course-alertmanager')
    grafana       = @('course-grafana')
    kibana        = @('course-kibana')
}
foreach ($name in $containers.Keys) {
    $children[$name] = @{
        hosts = @{
            $name = @{
                ansible_host       = $hosts[$name].private_ip
                service_containers = $containers[$name]
            }
        }
    }
}
$webHosts = @{}
foreach ($instance in $outputs.web_instances.value) {
    $webHosts[$instance.name] = @{ansible_host = $instance.network_interface[0].ip_address}
}
$inventory = @{
    all = @{
        vars = @{
            ansible_user                 = 'ubuntu'
            ansible_ssh_private_key_file = '/home/ubuntu/.ssh/course_ed25519'
        }
        children = @{
            services = @{children = $children}
            web      = @{hosts = $webHosts}
        }
    }
}
$secrets.folder_id = $FolderId
$secrets.snapshot_schedule_id = $outputs.snapshot_schedule_id.value
$secrets.postgres_master_fqdn = $outputs.postgres_master_fqdn.value
New-Item -ItemType Directory -Path $Destination -Force | Out-Null
$inventory | ConvertTo-Json -Depth 14 | Set-Content -LiteralPath (Join-Path $Destination 'inventory.json') -Encoding utf8
$secrets | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $Destination 'ansible-secrets.json') -Encoding utf8
'Prepared Ansible inventory and protected variables.'
