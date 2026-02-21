"""
Thin streaming proxy between Claude Code and LiteLLM.

LiteLLM can drop the opening '{' from input_json_delta events when
converting OpenAI tool_calls to Anthropic streaming format.  This proxy
forwards the SSE stream in real time and patches only the affected
chunks, preserving true streaming (token-by-token) for Claude Code.
"""

import json
import os
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from socketserver import ThreadingMixIn
from urllib.error import HTTPError
from urllib.request import Request, urlopen

UPSTREAM = os.environ.get("UPSTREAM", "http://litellm:4000")


class ProxyHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        self._forward("GET")

    def do_POST(self):
        self._forward("POST")

    def _forward(self, method):
        body = None
        if method == "POST":
            length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(length) if length else None

        is_messages = self.path.startswith("/v1/messages")
        wants_stream = False

        if is_messages and body:
            data = json.loads(body)
            wants_stream = data.get("stream", False)
            body = json.dumps(data).encode()

        headers = {}
        for key in ("content-type", "x-api-key", "anthropic-version",
                     "authorization", "accept"):
            val = self.headers.get(key)
            if val:
                headers[key] = val
        headers["Content-Type"] = "application/json"

        url = UPSTREAM + self.path
        req = Request(url, data=body, headers=headers, method=method)

        try:
            resp = urlopen(req, timeout=600)
        except HTTPError as e:
            self.send_response(e.code)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(e.read())
            return

        if is_messages and wants_stream:
            self._stream_forward(resp)
        else:
            resp_body = resp.read()
            self.send_response(200)
            for key, val in resp.getheaders():
                if key.lower() in ("content-type", "x-request-id"):
                    self.send_header(key, val)
            self.end_headers()
            self.wfile.write(resp_body)

    def _stream_forward(self, resp):
        """Forward SSE stream from LiteLLM, fixing input_json_delta on the fly."""
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()

        first_json_delta = {}
        event_lines = []

        for raw_line in resp:
            line = raw_line.decode("utf-8", errors="replace").rstrip("\r\n")

            if line:
                event_lines.append(line)
                continue

            if event_lines:
                self._flush_event(event_lines, first_json_delta)
                event_lines = []

        if event_lines:
            self._flush_event(event_lines, first_json_delta)

    def _flush_event(self, lines, first_json_delta):
        """Write one SSE event to the client, fixing the bug if needed."""
        for i, line in enumerate(lines):
            if not line.startswith("data: "):
                continue
            try:
                data = json.loads(line[6:])
            except (json.JSONDecodeError, ValueError):
                break

            if data.get("type") != "content_block_delta":
                break
            delta = data.get("delta", {})
            if delta.get("type") != "input_json_delta":
                break

            idx = data.get("index", 0)
            if idx not in first_json_delta:
                first_json_delta[idx] = True
                partial = delta.get("partial_json", "")
                if partial and not partial.startswith("{"):
                    delta["partial_json"] = "{" + partial
                    data["delta"] = delta
                    lines[i] = "data: " + json.dumps(data)
            break

        for line in lines:
            self.wfile.write((line + "\n").encode())
        self.wfile.write(b"\n")
        self.wfile.flush()

    def log_message(self, fmt, *args):
        sys.stderr.write(f"[proxy] {fmt % args}\n")


class ThreadedHTTPServer(ThreadingMixIn, HTTPServer):
    daemon_threads = True


if __name__ == "__main__":
    port = int(os.environ.get("PORT", "4001"))
    server = ThreadedHTTPServer(("0.0.0.0", port), ProxyHandler)
    print(f"Anthropic proxy listening on :{port} → {UPSTREAM}", flush=True)
    server.serve_forever()
