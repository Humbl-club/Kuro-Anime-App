#!/usr/bin/env python3
"""Temporary, allowlisted Kuro design preview. No repo browsing or backend access.

Run with --cloudflared /path/to/cloudflared. The public URL and server expire
when this process stops, or after --hours (default 12). Refresh to see local edits.
"""
import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import re
import mimetypes
from pathlib import Path
import signal
import subprocess
import threading
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[1] / 'tools' / 'design-directions'
# Explicit UI entry points only; never serve repository/configuration files.
FILES = {
    'instrument.html', 'instrument.css', 'instrument.js', 'journal-data.js',
    'instrument-detail-data.js', 'instrument-art-materials.js',
    'manga-directions.js', 'manga-directions.css',
    'manga-philosophies.js', 'manga-philosophies.css',
}
# Add only literal artwork/font dependencies of those public sample UI files.
for name in tuple(FILES):
    source = (ROOT / name).read_text()
    FILES.update(re.findall(r"assets/[A-Za-z0-9_./-]+\.(?:jpg|jpeg|png|webp|ttf|woff2?)", source))
# Character filenames are interpolated by Instrument; these are existing sample portraits.
FILES.update(f'assets/detail-character-{key}.png' for key in (21, 22, 23, 24, 180, 181, 182))
FILES = {name for name in FILES if (ROOT / name).is_file()}

class Preview(BaseHTTPRequestHandler):
    def do_GET(self):
        self.serve(False)
    def do_HEAD(self):
        self.serve(True)
    def serve(self, head):
        name = unquote(urlsplit(self.path).path).lstrip('/') or 'instrument.html'
        if name not in FILES:
            self.send_error(404)
            return
        path = (ROOT / name).resolve()
        if not path.is_relative_to(ROOT.resolve()) or not path.is_file():
            self.send_error(404)
            return
        data = path.read_bytes()
        self.send_response(200)
        self.send_header('Content-Type', mimetypes.guess_type(name)[0] or 'application/octet-stream')
        self.send_header('Content-Length', str(len(data)))
        self.send_header('Cache-Control', 'no-store')
        self.send_header('X-Robots-Tag', 'noindex, nofollow, noarchive')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.send_header('Referrer-Policy', 'same-origin')
        self.end_headers()
        if not head:
            self.wfile.write(data)
    def log_message(self, fmt, *args):
        pass

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', type=int, default=8814)
    parser.add_argument('--hours', type=float, default=12)
    parser.add_argument('--cloudflared', type=Path)
    args = parser.parse_args()
    if not 0 < args.hours <= 24:
        parser.error('--hours must be greater than 0 and no more than 24')
    server = ThreadingHTTPServer(('127.0.0.1', args.port), Preview)
    server.daemon_threads = True
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    stop = threading.Event()
    signal.signal(signal.SIGTERM, lambda *_: stop.set())
    signal.signal(signal.SIGINT, lambda *_: stop.set())
    expiry = threading.Timer(args.hours * 3600, stop.set)
    expiry.daemon = True
    expiry.start()
    tunnel = None
    try:
        print(f'Preview serves {len(FILES)} allowlisted files at 127.0.0.1:{args.port}; expires in {args.hours:g} hours.', flush=True)
        if args.cloudflared:
            tunnel = subprocess.Popen([str(args.cloudflared.resolve()), 'tunnel', '--no-autoupdate', '--protocol', 'http2', '--url', f'http://127.0.0.1:{args.port}'])
        while not stop.wait(1):
            if tunnel and tunnel.poll() is not None:
                raise RuntimeError('Temporary tunnel exited; preview stopped.')
    finally:
        expiry.cancel()
        if tunnel and tunnel.poll() is None:
            tunnel.terminate()
            try:
                tunnel.wait(timeout=10)
            except subprocess.TimeoutExpired:
                tunnel.kill()
                tunnel.wait()
        server.shutdown()
        server.server_close()
        print('Temporary preview stopped.', flush=True)

if __name__ == '__main__':
    main()
