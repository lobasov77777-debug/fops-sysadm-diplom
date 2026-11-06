#!/usr/bin/env python3
import json
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, HTTPServer


class Receiver(BaseHTTPRequestHandler):
    def do_POST(self):
        size = int(self.headers.get("Content-Length", "0"))
        event = json.loads(self.rfile.read(size))
        event["received_at"] = datetime.now(timezone.utc).isoformat()
        with open("/var/log/course/alerts-received.jsonl", "a", encoding="utf-8") as output:
            output.write(json.dumps(event) + "\n")
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"ok")


HTTPServer(("127.0.0.1", 5001), Receiver).serve_forever()
