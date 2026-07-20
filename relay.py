from http.server import HTTPServer, BaseHTTPRequestHandler
import os, json, urllib.parse, urllib.request, subprocess, re, threading

RELAY_DIR = "/tmp/relay"
CHUNK = 65536

class RelayHandler(BaseHTTPRequestHandler):
    def _json(self, code, data):
        body = json.dumps(data).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        pass

    def do_POST(self):
        name = self.path.strip("/")
        if not name:
            self.send_response(400); self.end_headers(); return

        # /pull endpoint: VPS fetches file from agent through SSH tunnel
        if name == "pull":
            length = int(self.headers.get('Content-Length', 0))
            body = json.loads(self.rfile.read(length))
            port = body.get("port")
            path = body.get("path")
            filename = body.get("filename", os.path.basename(path))
            pre_cmd = body.get("pre_cmd")
            if not port or not path:
                self._json(400, {"error": "port and path required"})
                return
            os.makedirs(RELAY_DIR, exist_ok=True)
            # Run optional pre-command to prepare file (e.g. copy to SYSTEM-accessible location)
            if pre_cmd:
                try:
                    data = json.dumps({"command": pre_cmd, "timeout": 30}).encode()
                    req = urllib.request.Request(f"http://127.0.0.1:{port}/api/ps", data, {"Content-Type": "application/json"})
                    urllib.request.urlopen(req, timeout=35)
                except Exception as e:
                    self._json(500, {"error": f"pre_cmd failed: {e}"})
                    return
            enc = urllib.parse.quote(path)
            url = f"http://127.0.0.1:{port}/api/download?path={enc}"
            try:
                dest = os.path.join(RELAY_DIR, filename)
                # Use curl (not aria2) since v1 /api/download doesn't support Range headers
                r = subprocess.run(["curl", "-s", "-o", dest, url],
                    capture_output=True, text=True, timeout=600)
                if os.path.exists(dest) and os.path.getsize(dest) > 0:
                    self._json(200, {"status": "ok", "size": os.path.getsize(dest), "filename": filename})
                else:
                    self._json(500, {"error": "download failed"})
            except subprocess.TimeoutExpired:
                self._json(504, {"error": "timeout"})
            return

        # Regular file upload
        os.makedirs(RELAY_DIR, exist_ok=True)
        length = int(self.headers.get('Content-Length', 0))
        wrote = 0
        with open(f"{RELAY_DIR}/{name}", "wb") as f:
            while wrote < length:
                data = self.rfile.read(min(CHUNK, length - wrote))
                if not data: break
                f.write(data)
                wrote += len(data)
        self.send_response(200)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_GET(self):
        name = self.path.strip("/")

        # /register: scan all active agents and return port mapping
        if name == "register":
            agents = []
            lock = threading.Lock()

            def scan_v1(p):
                try:
                    data = json.dumps({"command": "hostname", "timeout": 5}).encode()
                    r = urllib.request.urlopen(urllib.request.Request(
                        f"http://127.0.0.1:{p}/api/ps", data, {"Content-Type": "application/json"}), timeout=4)
                    body = json.loads(r.read())
                    hn = body.get('stdout', '').strip()
                    if hn:
                        with lock: agents.append({"port": p, "hostname": hn, "version": "v1"})
                except: pass

            def scan_v2(p):
                try:
                    import uuid
                    sid = str(uuid.uuid4())
                    data = json.dumps({"jsonrpc": "2.0", "id": 1, "method": "initialize",
                        "params": {"protocolVersion": "2025-03-26", "capabilities": {}, "clientInfo": {"name": "r"}}}).encode()
                    req = urllib.request.Request(f"http://127.0.0.1:{p}/mcp", data, {
                        "Content-Type": "application/json", "Authorization": "Bearer 234d130007706cd69359c94b89d3dd70"})
                    r = urllib.request.urlopen(req, timeout=4)
                    body = json.loads(r.read())
                    if 'result' in body:
                        hdr = {k.lower(): v for k, v in r.headers.items()}
                        sid = hdr.get('mcp-session-id', str(uuid.uuid4()))
                        data2 = json.dumps({"jsonrpc": "2.0", "id": 2, "method": "tools/call",
                            "params": {"name": "shell", "arguments": {"command": "hostname", "timeout": 5}}}).encode()
                        req2 = urllib.request.Request(f"http://127.0.0.1:{p}/mcp", data2, {
                            "Content-Type": "application/json", "Authorization": "Bearer 234d130007706cd69359c94b89d3dd70",
                            "Mcp-Session-Id": sid})
                        r2 = urllib.request.urlopen(req2, timeout=5)
                        body2 = json.loads(r2.read())
                        text = body2.get('result', {}).get('content', [{}])[0].get('text', '')
                        hn = [l.strip() for l in text.split('\n') if l.strip()][-1] if text.strip() else ''
                        with lock: agents.append({"port": p, "hostname": hn, "version": "v2"})
                except: pass

            threads = []
            for p in range(7081, 7091): 
                t = threading.Thread(target=scan_v1, args=(p,)); t.start(); threads.append(t)
            for p in range(7181, 7201): 
                t = threading.Thread(target=scan_v2, args=(p,)); t.start(); threads.append(t)
            for t in threads: t.join()

            agents.sort(key=lambda a: a["port"])
            self._json(200, agents)
            return

        if not name:
            self.send_response(400); self.end_headers(); return
        path = f"{RELAY_DIR}/{name}"
        if not os.path.exists(path):
            self.send_response(404); self.end_headers(); return
        size = os.path.getsize(path)
        start, end = 0, size - 1
        range_header = self.headers.get("Range")
        if range_header:
            m = re.search(r"bytes=(\d*)-(\d*)", range_header)
            if m:
                start = int(m.group(1)) if m.group(1) else 0
                end = int(m.group(2)) if m.group(2) else size - 1
                if start >= size:
                    self.send_response(416); self.end_headers(); return
                end = min(end, size - 1)
                self.send_response(206)
                self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
                self.send_header("Content-Length", str(end - start + 1))
                self.end_headers()
                with open(path, "rb") as f:
                    f.seek(start)
                    remaining = end - start + 1
                    while remaining > 0:
                        chunk = f.read(min(CHUNK, remaining))
                        if not chunk: break
                        self.wfile.write(chunk)
                        remaining -= len(chunk)
                return
        self.send_response(200)
        self.send_header("Content-Length", str(size))
        self.end_headers()
        with open(path, "rb") as f:
            while True:
                data = f.read(CHUNK)
                if not data: break
                self.wfile.write(data)

    def do_DELETE(self):
        name = self.path.strip("/")
        try: os.remove(f"{RELAY_DIR}/{name}")
        except: pass
        self.send_response(200); self.end_headers()

HTTPServer(("0.0.0.0", 9999), RelayHandler).serve_forever()
