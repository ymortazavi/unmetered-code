"""
Thin proxy between Claude Code and LiteLLM that fixes a streaming bug.

LiteLLM 1.81.x drops the opening '{' from input_json_delta events when
converting OpenAI tool_calls to Anthropic streaming format.  This proxy
makes non-streaming requests to LiteLLM and converts the response into
a correct Anthropic SSE stream.
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
            data["stream"] = False
            body = json.dumps(data).encode()

        headers = {}
        for key in ("content-type", "x-api-key", "anthropic-version", "authorization", "accept"):
            val = self.headers.get(key)
            if val:
                headers[key] = val
        headers["Content-Type"] = "application/json"

        url = UPSTREAM + self.path
        req = Request(url, data=body, headers=headers, method=method)

        try:
            resp = urlopen(req, timeout=600)
            resp_body = resp.read()
        except HTTPError as e:
            self.send_response(e.code)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(e.read())
            return

        if not (is_messages and wants_stream):
            self.send_response(200)
            for key, val in resp.getheaders():
                if key.lower() in ("content-type", "x-request-id"):
                    self.send_header(key, val)
            self.end_headers()
            self.wfile.write(resp_body)
            return

        msg = json.loads(resp_body)
        self._stream_response(msg)

    def _stream_response(self, msg):
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()

        def sse(data):
            self.wfile.write(f"event: {data['type']}\n".encode())
            self.wfile.write(f"data: {json.dumps(data)}\n\n".encode())
            self.wfile.flush()

        sse(
            {
                "type": "message_start",
                "message": {
                    "id": msg.get("id", ""),
                    "type": "message",
                    "role": "assistant",
                    "model": msg.get("model", ""),
                    "content": [],
                    "stop_reason": None,
                    "stop_sequence": None,
                    "usage": {
                        "input_tokens": msg.get("usage", {}).get("input_tokens", 0),
                        "output_tokens": 0,
                    },
                },
            }
        )

        for idx, block in enumerate(msg.get("content", [])):
            btype = block.get("type")

            if btype == "thinking":
                sse(
                    {
                        "type": "content_block_start",
                        "index": idx,
                        "content_block": {"type": "thinking", "thinking": ""},
                    }
                )
                text = block.get("thinking", "")
                if text:
                    sse(
                        {
                            "type": "content_block_delta",
                            "index": idx,
                            "delta": {"type": "thinking_delta", "thinking": text},
                        }
                    )
                sse({"type": "content_block_stop", "index": idx})

            elif btype == "text":
                sse(
                    {
                        "type": "content_block_start",
                        "index": idx,
                        "content_block": {"type": "text", "text": ""},
                    }
                )
                text = block.get("text", "")
                if text:
                    sse(
                        {
                            "type": "content_block_delta",
                            "index": idx,
                            "delta": {"type": "text_delta", "text": text},
                        }
                    )
                sse({"type": "content_block_stop", "index": idx})

            elif btype == "tool_use":
                sse(
                    {
                        "type": "content_block_start",
                        "index": idx,
                        "content_block": {
                            "type": "tool_use",
                            "id": block.get("id", ""),
                            "name": block.get("name", ""),
                            "input": {},
                        },
                    }
                )
                inp = block.get("input", {})
                sse(
                    {
                        "type": "content_block_delta",
                        "index": idx,
                        "delta": {"type": "input_json_delta", "partial_json": json.dumps(inp)},
                    }
                )
                sse({"type": "content_block_stop", "index": idx})

        sse(
            {
                "type": "message_delta",
                "delta": {"stop_reason": msg.get("stop_reason", "end_turn"), "stop_sequence": None},
                "usage": {"output_tokens": msg.get("usage", {}).get("output_tokens", 0)},
            }
        )
        sse({"type": "message_stop"})

    def log_message(self, fmt, *args):
        sys.stderr.write(f"[proxy] {fmt % args}\n")


class ThreadedHTTPServer(ThreadingMixIn, HTTPServer):
    daemon_threads = True


if __name__ == "__main__":
    port = int(os.environ.get("PORT", "4001"))
    server = ThreadedHTTPServer(("0.0.0.0", port), ProxyHandler)
    print(f"Anthropic proxy listening on :{port} → {UPSTREAM}", flush=True)
    server.serve_forever()
