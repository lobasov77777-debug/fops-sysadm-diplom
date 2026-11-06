#!/usr/bin/env python3
"""Build the submitted Grafana dashboard with explicit USE queries and thresholds."""
import json
from pathlib import Path

panels = [
    ("CPU · Utilization", '100 * (1 - avg by(instance) (rate(node_cpu_seconds_total{job="node",mode="idle"}[2m])))', "percent", 80),
    ("CPU · Saturation", 'node_load1{job="node"} / on(instance) count by(instance) (node_cpu_seconds_total{job="node",mode="idle"})', "short", 1),
    ("CPU · Errors", 'course_cpu_error_events_total{job="node"}', "short", 1),
    ("RAM · Utilization", '100 * (1 - node_memory_MemAvailable_bytes{job="node"} / node_memory_MemTotal_bytes{job="node"})', "percent", 90),
    ("RAM · Saturation — major faults", 'rate(node_vmstat_pgmajfault{job="node"}[2m])', "ops", 10),
    ("RAM · Errors — OOM kills", 'node_vmstat_oom_kill{job="node"}', "short", 1),
    ("Disk · Utilization", '100 * rate(node_disk_io_time_seconds_total{job="node",device!~"loop.*|ram.*"}[2m])', "percent", 80),
    ("Disk · Saturation — queue depth", 'rate(node_disk_io_time_weighted_seconds_total{job="node",device!~"loop.*|ram.*"}[2m])', "short", 1),
    ("Disk · Errors", 'course_disk_error_events_total{job="node"}', "short", 1),
    ("Network · Utilization", 'rate(node_network_receive_bytes_total{job="node",device!="lo"}[2m]) + rate(node_network_transmit_bytes_total{job="node",device!="lo"}[2m])', "Bps", 10000000),
    ("Network · Saturation — dropped packets", 'rate(node_network_receive_drop_total{job="node",device!="lo"}[2m]) + rate(node_network_transmit_drop_total{job="node",device!="lo"}[2m])', "pps", 1),
    ("Network · Errors", 'rate(node_network_receive_errs_total{job="node",device!="lo"}[2m]) + rate(node_network_transmit_errs_total{job="node",device!="lo"}[2m])', "pps", 1),
    ("Nginx · http_response_count_total", 'nginx_http_response_count_total', "short", 100000),
    ("Nginx · http_response_size_bytes", 'nginx_http_response_size_bytes', "bytes", 100000000),
    ("Nginx · Requests / second", 'sum by(instance,status) (rate(nginx_http_response_count_total[2m]))', "reqps", 100),
    ("Availability · Exporters", 'up{job=~"node|nginx"}', "short", 2),
]

dashboard = {
    "uid": "course-use",
    "title": "Курсовая работа — USE и Nginx",
    "schemaVersion": 39,
    "version": 1,
    "refresh": "15s",
    "time": {"from": "now-30m", "to": "now"},
    "timezone": "browser",
    "tags": ["course", "USE", "nginx"],
    "panels": [],
}
for index, (title, expression, unit, threshold) in enumerate(panels):
    dashboard["panels"].append({
        "id": index + 1,
        "type": "timeseries",
        "title": title,
        "datasource": {"type": "prometheus", "uid": "prometheus"},
        "gridPos": {"x": (index % 3) * 8, "y": (index // 3) * 8, "w": 8, "h": 8},
        "targets": [{"refId": "A", "expr": expression, "legendFormat": "{{instance}} {{device}} {{status}}"}],
        "fieldConfig": {
            "defaults": {
                "unit": unit,
                "min": 0,
                "thresholds": {"mode": "absolute", "steps": [
                    {"color": "green", "value": None},
                    {"color": "red", "value": threshold},
                ]},
                "custom": {"drawStyle": "line", "fillOpacity": 8, "thresholdsStyle": {"mode": "line"}},
            },
            "overrides": [],
        },
        "options": {"legend": {"displayMode": "list", "placement": "bottom"}, "tooltip": {"mode": "multi"}},
    })

output = Path(__file__).resolve().parents[1] / "ansible/roles/grafana/files/course.json"
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(json.dumps(dashboard, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"Built {len(panels)} dashboard panels")
