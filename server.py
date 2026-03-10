#!/usr/bin/env python3
import json
import os
import subprocess
import time
from urllib.parse import urlparse
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler

APP_DIR = os.path.dirname(os.path.abspath(__file__))
PUBLIC_DIR = os.path.join(APP_DIR, "public")
COLLECTOR = os.path.join(APP_DIR, "scripts", "codex-quota-collector.sh")
PORT = int(os.environ.get("PORT", "8787"))
BIND_HOST = os.environ.get("BIND_HOST", "auto")

if BIND_HOST == "auto":
    try:
      BIND_HOST = subprocess.check_output(["tailscale", "ip", "-4"], text=True).splitlines()[0].strip()
    except Exception:
      BIND_HOST = "127.0.0.1"
if not BIND_HOST:
    BIND_HOST = "127.0.0.1"

REFRESH_STATE = {
    "proc": None,
    "startedAt": None,
    "lastExitCode": None,
    "lastError": None,
    "lastFinishedAt": None,
}


def _refresh_status_payload():
    proc = REFRESH_STATE["proc"]
    if proc is not None:
        rc = proc.poll()
        if rc is not None:
            try:
                _stdout, stderr = proc.communicate(timeout=0.1)
            except Exception:
                stderr = ""
            REFRESH_STATE["proc"] = None
            REFRESH_STATE["lastExitCode"] = rc
            REFRESH_STATE["lastError"] = (stderr or "")[-1200:] if rc != 0 else None
            REFRESH_STATE["lastFinishedAt"] = time.strftime("%Y-%m-%dT%H:%M:%S%z")

    running = REFRESH_STATE["proc"] is not None
    return {
        "ok": True,
        "running": running,
        "startedAt": REFRESH_STATE["startedAt"],
        "lastExitCode": REFRESH_STATE["lastExitCode"],
        "lastError": REFRESH_STATE["lastError"],
        "lastFinishedAt": REFRESH_STATE["lastFinishedAt"],
    }


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=PUBLIC_DIR, **kwargs)

    def _json(self, code, payload):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = urlparse(self.path).path
        if path == "/api/refresh-status":
            return self._json(200, _refresh_status_payload())
        return super().do_GET()

    def do_POST(self):
        path = urlparse(self.path).path
        if path != "/api/refresh":
            return self._json(404, {"ok": False, "error": "not found"})

        status = _refresh_status_payload()
        if status.get("running"):
            return self._json(202, {"ok": True, "running": True, "message": "collector already running"})

        try:
            proc = subprocess.Popen(
                ["/usr/bin/env", "bash", COLLECTOR],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.PIPE,
                text=True,
            )
            REFRESH_STATE["proc"] = proc
            REFRESH_STATE["startedAt"] = time.strftime("%Y-%m-%dT%H:%M:%S%z")
            REFRESH_STATE["lastExitCode"] = None
            REFRESH_STATE["lastError"] = None
            return self._json(202, {"ok": True, "running": True, "started": True})
        except Exception as e:
            return self._json(500, {"ok": False, "error": str(e)})

print(f"Dashboard listening on http://{BIND_HOST}:{PORT}")
os.chdir(PUBLIC_DIR)
ThreadingHTTPServer((BIND_HOST, PORT), Handler).serve_forever()
