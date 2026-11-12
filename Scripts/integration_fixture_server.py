#!/usr/bin/env python3
"""LOCAL TEST ONLY: API + XiaoZhi MCP protocol fixtures, no real model/ASR service."""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import struct
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

EVENTS = {"kind": "LOCAL_PROTOCOL_FIXTURE_NOT_A_REAL_PROVIDER", "cloud_requests": 0, "cloud_probes": 0, "mcp_steps": []}
LOCK = threading.Lock()
REPORT = None

def record(key, value=None):
    with LOCK:
        if value is None:
            EVENTS[key] += 1
        else:
            EVENTS[key].append(value)
        if REPORT:
            REPORT.parent.mkdir(parents=True, exist_ok=True)
            REPORT.write_text(json.dumps(EVENTS, ensure_ascii=False, indent=2))

class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    def log_message(self, *args):
        pass
    def reply(self, value, code=200):
        data = json.dumps(value, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(data)
        self.close_connection = True
    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        if length > 65536:
            return self.reply({"error": "fixture request too large"}, 413)
        if self.headers.get("Authorization") != "Bearer luma-local-protocol-fixture":
            return self.reply({"error": "fixture authentication"}, 401)
        try:
            request = json.loads(self.rfile.read(length))
            responses = self.path == "/v1/responses"
            if self.path not in ("/v1/chat/completions", "/v1/responses"):
                return self.reply({"error": "unknown fixture route"}, 404)
            if responses:
                text = request["input"][0]["content"][0]["text"]
            else:
                text = request["messages"][-1]["content"][0]["text"]
            if 'Return {"ok":true}' in text:
                record("cloud_probes")
                recipe = {"ok": True}
            else:
                record("cloud_requests")
                recipe = {"version": 1, "global": {"exposure": 0.35, "temperature": 7200, "contrast": 1, "saturation": 1}, "color": {"lut": None, "intensity": 0}, "beauty": {"enabled": "不要美颜" not in text, "strength": 0.45, "skinTone": 0.2, "blemishRemoval": 0.2, "texturePreservation": 0.94}, "masks": [], "operations": [], "evaluation": {"automaticCorrection": True, "maxCorrections": 2, "preserveSkin": True}}
            output = json.dumps(recipe, ensure_ascii=False)
            if responses:
                return self.reply({"status": "completed", "output": [{"type": "message", "content": [{"type": "output_text", "text": output}]}]})
            return self.reply({"choices": [{"message": {"role": "assistant", "content": output}, "finish_reason": "stop"}]})
        except Exception:
            return self.reply({"error": "invalid fixture request"}, 400)
    def do_GET(self):
        if self.path == "/fixture/status":
            return self.reply(EVENTS)
        if self.path != "/mcp" or self.headers.get("Upgrade", "").lower() != "websocket":
            return self.reply({"error": "fixture route"}, 404)
        key = self.headers.get("Sec-WebSocket-Key", "")
        accept = base64.b64encode(hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest()).decode()
        self.send_response(101)
        self.send_header("Upgrade", "websocket")
        self.send_header("Connection", "Upgrade")
        self.send_header("Sec-WebSocket-Accept", accept)
        self.end_headers()
        self.connection.settimeout(60)
        try:
            steps = [
                {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2024-11-05", "capabilities": {}, "clientInfo": {"name": "LOCAL_XIAOZHI_PROTOCOL_FIXTURE", "version": "1"}}},
                {"jsonrpc": "2.0", "id": 2, "method": "tools/list"},
                {"jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": {"name": "lumastudio.get_status", "arguments": {}}},
                {"jsonrpc": "2.0", "id": 4, "method": "tools/call", "params": {"name": "lumastudio.set_instruction", "arguments": {"id": "9e17ea27-4792-408c-9c84-33cced907b39", "text": "自然美颜，保留皮肤纹理，暖一点，提亮一点"}}},
            ]
            for request in steps:
                self.send_frame(json.dumps(request, ensure_ascii=False).encode())
                response = json.loads(self.read_frame())
                record("mcp_steps", {"method": request["method"], "id_matches": response.get("id") == request["id"], "has_result": "result" in response})
            while self.read_frame() is not None:
                pass
        except Exception:
            pass
        self.close_connection = True
    def send_frame(self, payload, opcode=1):
        if len(payload) < 126:
            header = bytes([0x80 | opcode, len(payload)])
        else:
            header = bytes([0x80 | opcode, 126]) + struct.pack("!H", len(payload))
        self.wfile.write(header + payload)
        self.wfile.flush()
    def read_frame(self):
        header = self.rfile.read(2)
        if len(header) != 2 or header[0] & 15 == 8:
            return None
        length = header[1] & 127
        if length == 126:
            length = struct.unpack("!H", self.rfile.read(2))[0]
        elif length == 127:
            length = struct.unpack("!Q", self.rfile.read(8))[0]
        if length > 16384:
            raise ValueError("Fixture frame too large")
        mask = self.rfile.read(4) if header[1] & 128 else None
        payload = self.rfile.read(length)
        if mask:
            payload = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
        if header[0] & 15 == 9:
            self.send_frame(payload, opcode=10)
            return self.read_frame()
        return payload

def main():
    global REPORT
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8766)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    REPORT = args.report
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    print(json.dumps({"kind": EVENTS["kind"], "port": server.server_port}), flush=True)
    server.serve_forever()

if __name__ == "__main__":
    main()
