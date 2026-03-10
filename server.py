#!/usr/bin/env python3
import json
import os
import subprocess
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

    def do_POST(self):
        if self.path != "/api/refresh":
            return self._json(404, {"ok": False, "error": "not found"})
        try:
            proc = subprocess.run(["/usr/bin/env", "bash", COLLECTOR], capture_output=True, text=True, timeout=240)
            if proc.returncode != 0:
                return self._json(500, {
                    "ok": False,
                    "error": "collector failed",
                    "code": proc.returncode,
                    "stderr": (proc.stderr or "")[-1200:],
                })
            return self._json(200, {"ok": True})
        except subprocess.TimeoutExpired:
            return self._json(504, {"ok": False, "error": "collector timeout"})
        except Exception as e:
            return self._json(500, {"ok": False, "error": str(e)})

print(f"Dashboard listening on http://{BIND_HOST}:{PORT}")
os.chdir(PUBLIC_DIR)
ThreadingHTTPServer((BIND_HOST, PORT), Handler).serve_forever()
