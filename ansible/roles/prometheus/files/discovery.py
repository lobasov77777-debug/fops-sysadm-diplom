#!/usr/bin/env python3
"""Refresh Prometheus targets and snapshot coverage after instance-group changes."""
import json
import os
import time
import urllib.parse
import urllib.request
from pathlib import Path

API = "https://compute.api.cloud.yandex.net/compute/v1/"
config = json.loads(Path("/opt/course/discovery.json").read_text())
metadata_request = urllib.request.Request(
    "http://169.254.169.254/computeMetadata/v1/instance/service-accounts/default/token",
    headers={"Metadata-Flavor": "Google"},
)
with urllib.request.urlopen(metadata_request, timeout=10) as response:
    token = json.load(response)["access_token"]


def request(path, method="GET", body=None, base=API):
    payload = None if body is None else json.dumps(body).encode()
    headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}
    req = urllib.request.Request(base + path, data=payload, headers=headers, method=method)
    with urllib.request.urlopen(req, timeout=30) as response:
        return json.load(response)


def list_items(path, key, parameters=None):
    parameters = dict(parameters or {})
    parameters["pageSize"] = "100"
    items = []
    while True:
        result = request(path + "?" + urllib.parse.urlencode(parameters))
        items.extend(result.get(key, []))
        token = result.get("nextPageToken")
        if not token:
            return items
        parameters["pageToken"] = token


instances = list_items("instances", "instances", {"folderId": config["folder_id"]})
course_instances = [item for item in instances if item.get("labels", {}).get("project") == config["prefix"]]
web = [item for item in course_instances if item.get("labels", {}).get("role") == "web" and item["status"] == "RUNNING"]
targets = [{
    "targets": [item["networkInterfaces"][0]["primaryV4Address"]["address"]],
    "labels": {"host": item["name"], "zone": item["zoneId"], "role": "web"},
} for item in web]
destination = Path("/opt/course/web-targets.json")
temporary = destination.with_suffix(".tmp")
temporary.write_text(json.dumps(targets, indent=2) + "\n")
os.chmod(temporary, 0o644)
temporary.replace(destination)

schedule_id = config["snapshot_schedule_id"]
attached = list_items(f"snapshotSchedules/{schedule_id}/disks", "disks")
current_disks = {item["id"] for item in attached}
desired_disks = {item["bootDisk"]["diskId"] for item in course_instances}
add = sorted(desired_disks - current_disks)
remove = sorted(current_disks - desired_disks)
if add or remove:
    operation = request(f"snapshotSchedules/{schedule_id}:updateDisks", "PATCH", {"add": add, "remove": remove})
    for attempt in range(30):
        if operation.get("done"):
            break
        time.sleep(2)
        operation = request(operation["id"], base="https://operation.api.cloud.yandex.net/operations/")
    if not operation.get("done") or operation.get("error"):
        raise RuntimeError(f"Snapshot schedule update failed: {operation}")
print(json.dumps({"web_targets": len(web), "protected_disks": len(desired_disks), "added": add, "removed": remove}))
