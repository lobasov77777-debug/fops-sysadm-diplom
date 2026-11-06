#!/usr/bin/env python3
"""Verify real metrics, indexed logs and configured Grafana panels from the bastion."""
import argparse
import base64
import json
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--settings", required=True)
parser.add_argument("--outputs", required=True)
args = parser.parse_args()
settings = json.loads(Path(args.settings).read_text(encoding="utf-8-sig"))
outputs = json.loads(Path(args.outputs).read_text(encoding="utf-8-sig"))
hosts = outputs["hosts"]["value"]
prometheus = f"http://{hosts['prometheus']['private_ip']}:9090"
elasticsearch = f"http://{hosts['elasticsearch']['private_ip']}:9200"
grafana = f"http://{hosts['grafana']['private_ip']}:3000"
kibana = f"http://{hosts['kibana']['private_ip']}:5601"


def request(url, username=None, password=None, body=None):
    headers = {"Content-Type": "application/json"}
    if username:
        credentials = base64.b64encode(f"{username}:{password}".encode()).decode()
        headers["Authorization"] = f"Basic {credentials}"
    payload = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(url, headers=headers, data=payload)
    with urllib.request.urlopen(req, timeout=30) as response:
        return json.load(response)


targets = request(prometheus + "/api/v1/targets")["data"]["activeTargets"]
web_targets = [item for item in targets if item["labels"]["job"] in ("node", "nginx")]
assert len(web_targets) >= 4, f"Expected at least four web exporter targets, got {len(web_targets)}"
assert all(item["health"] == "up" for item in web_targets), "A web exporter is down"
zones = {item["labels"]["zone"] for item in web_targets}
assert len(zones) == 2, f"Web exporters must cover two availability zones, got {zones}"

dashboard = request(grafana + "/api/dashboards/uid/course-use", "course_admin", settings["grafana_admin_password"])
panel_results = []
for panel in dashboard["dashboard"]["panels"]:
    expression = panel["targets"][0]["expr"]
    query = urllib.parse.urlencode({"query": expression})
    result = request(prometheus + "/api/v1/query?" + query)
    assert result["status"] == "success", panel["title"]
    assert result["data"]["result"], f"No data for panel {panel['title']}"
    if panel["id"] <= 12:
        assert len(panel["fieldConfig"]["defaults"]["thresholds"]["steps"]) >= 2
    panel_results.append({"title": panel["title"], "series": len(result["data"]["result"])})

aggregation = {
    "size": 0,
    "aggs": {
        "datasets": {"terms": {"field": "event.dataset", "size": 20}},
        "services": {"terms": {"field": "service.name", "size": 20}},
        "hosts": {"terms": {"field": "host.name", "size": 20}},
    },
}
logs = request(elasticsearch + "/course-logs-*/_search", "elastic", settings["elastic_password"], aggregation)
datasets = {item["key"]: item["doc_count"] for item in logs["aggregations"]["datasets"]["buckets"]}
services = {item["key"]: item["doc_count"] for item in logs["aggregations"]["services"]["buckets"]}
assert datasets.get("nginx.access", 0) > 0, "Nginx access logs are absent"
assert datasets.get("nginx.error", 0) > 0, "Nginx error logs are absent"
for name in ("elasticsearch", "kibana", "prometheus", "grafana"):
    assert services.get(name, 0) > 0, f"Internal logs for {name} are absent"

status = request(kibana + "/api/status", "course_viewer", settings["reviewer_password"])
assert status["status"]["overall"]["level"] == "available", "Kibana is not available"
reviewer_dashboard = request(grafana + "/api/dashboards/uid/course-use", "course_viewer", settings["reviewer_password"])
assert reviewer_dashboard["dashboard"]["uid"] == "course-use"

print(json.dumps({
    "verified_at": datetime.now(timezone.utc).isoformat(),
    "exporters": [{"job": item["labels"]["job"], "instance": item["labels"]["instance"], "zone": item["labels"]["zone"], "health": item["health"]} for item in web_targets],
    "grafana_panels": panel_results,
    "indexed_datasets": datasets,
    "indexed_services": services,
    "kibana": "available",
    "reviewer_access": "verified",
}, indent=2, ensure_ascii=False))
