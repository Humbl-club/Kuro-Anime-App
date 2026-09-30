#!/usr/bin/env python3
"""Serve the local screen canvas and its isolated capture output."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import argparse

PAGE = Path(__file__).resolve().parents[1] / 'tools/live-preview/index.html'

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        route = self.path.split('?')[0]
        mime = 'text/html; charset=utf-8'
        if route in ('/', '/index.html'):
            target = PAGE
        elif route == '/manifest.json':
            target = Path('/tmp/kuro-screen-canvas/manifest.json')
            mime = 'application/json'
        elif route.startswith('/captures/'):
            root = Path('/tmp/kuro-screen-canvas').resolve()
            target = (root / route.removeprefix('/captures/')).resolve()
            if not target.is_relative_to(root) or target.suffix != '.png':
                self.send_error(404)
                return
            mime = 'image/png'
        else:
            self.send_error(404)
            return
        if not target.is_file():
            self.send_error(404)
            return
        body = target.read_bytes()
        self.send_response(200)
        self.send_header('Content-Type', mime)
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Cache-Control', 'no-store')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.end_headers()
        self.wfile.write(body)

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', type=int, default=8799)
    args = parser.parse_args()
    server = ThreadingHTTPServer(('127.0.0.1', args.port), Handler)
    print(f'Kuro live preview: http://127.0.0.1:{args.port}', flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
