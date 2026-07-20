from http.server import HTTPServer, BaseHTTPRequestHandler
import os

RELAY_DIR = "/tmp/relay"
CHUNK = 65536

class RelayHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass

    def do_POST(self):
        name = self.path.strip("/")
        if not name:
            self.send_response(400); self.end_headers(); return
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
        if not name:
            self.send_response(400); self.end_headers(); return
        path = f"{RELAY_DIR}/{name}"
        if not os.path.exists(path):
            self.send_response(404); self.end_headers(); return
        size = os.path.getsize(path)
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
