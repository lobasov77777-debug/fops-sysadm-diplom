#!/usr/bin/env python3
"""Expose counts of CPU and block-device error events retained since boot."""
import os
import re
import subprocess

result = subprocess.run(
    ["journalctl", "-k", "-b", "--no-pager", "-o", "cat"],
    check=True, capture_output=True, text=True,
)
patterns = {
    "cpu": r"machine check|hardware error|mce:.*error|cpu.*hardware.*error",
    "disk": r"I/O error, dev|Buffer I/O error|blk_update_request:.*error|blk_print_req_error",
}
target = "/var/lib/prometheus/node-exporter/course-errors.prom"
with open(target + ".tmp", "w", encoding="utf-8") as output:
    for device, pattern in patterns.items():
        count = sum(bool(re.search(pattern, line, re.I)) for line in result.stdout.splitlines())
        metric = f"course_{device}_error_events_total"
        output.write(f"# HELP {metric} Kernel error events retained in this boot's journal.\n")
        output.write(f"# TYPE {metric} counter\n{metric} {count}\n")
os.chmod(target + ".tmp", 0o644)
os.replace(target + ".tmp", target)
