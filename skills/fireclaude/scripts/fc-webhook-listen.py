#!/usr/bin/env python3
"""fc-webhook-listen.py — ephemeral webhook receiver for fc webhook-listen"""
import argparse
import json
import signal
import sys
import time
from http.server import BaseHTTPRequestHandler, HTTPServer


class ReusableHTTPServer(HTTPServer):
    """HTTPServer with SO_REUSEADDR so rapid restarts don't hit EADDRINUSE."""
    allow_reuse_address = True


class WebhookHandler(BaseHTTPRequestHandler):
    emit_json = False

    def log_message(self, fmt, *args):
        # Suppress default access log; we emit structured JSON instead
        pass

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body_bytes = self.rfile.read(length) if length else b""
        try:
            body = json.loads(body_bytes)
        except Exception:
            body = body_bytes.decode(errors="replace")

        event = {
            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "method": self.command,
            "path": self.path,
            "headers": dict(self.headers),
            "body": body,
        }
        print(json.dumps(event), flush=True)

        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"OK")

    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"fc-webhook-listener running")


def main():
    parser = argparse.ArgumentParser(description="Ephemeral webhook receiver")
    parser.add_argument("--port", type=int, default=4321)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()

    WebhookHandler.emit_json = args.json

    server = ReusableHTTPServer(("", args.port), WebhookHandler)

    def _shutdown(sig, frame):
        sys.stderr.write("\nfc-webhook-listen: shutting down\n")
        server.server_close()
        sys.exit(0)

    signal.signal(signal.SIGINT, _shutdown)
    signal.signal(signal.SIGTERM, _shutdown)

    sys.stderr.write(f"fc-webhook-listen: listening on port {args.port} (Ctrl+C to stop)\n")
    server.serve_forever()


if __name__ == "__main__":
    main()
