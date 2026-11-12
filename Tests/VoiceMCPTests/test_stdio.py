"""Exercise the public stdio executable against an authenticated loopback service."""
import json
import os
from pathlib import Path
import subprocess
import sys
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

SCRIPT = Path(__file__).resolve().parents[2] / "Tools/VoiceMCP/luma_voice_mcp.py"
TOKEN = "local-protocol-fixture-only-1234567890"


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_GET(self):
        self.respond({"photoName": "fixture.jpg", "busy": False})

    def do_POST(self):
        command = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        self.server.commands.append(command)
        self.respond({"accepted": True, "status": "queued"})

    def respond(self, value):
        valid = self.headers.get("Authorization") == "Bearer " + TOKEN
        body = json.dumps(value if valid else {"error": "unauthorized"}).encode()
        self.send_response(200 if valid else 401)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


class StdioProtocolTests(unittest.TestCase):
    def run_adapter(self, requests, base, token=TOKEN):
        env = {**os.environ, "LUMA_VOICE_BASE_URL": base, "LUMA_VOICE_TOKEN": token}
        result = subprocess.run([sys.executable, str(SCRIPT)], input="".join(json.dumps(x) + "\n" for x in requests), capture_output=True, text=True, env=env, timeout=10, check=True)
        self.assertEqual(result.stderr, "")
        return [json.loads(x) for x in result.stdout.splitlines()]

    def test_stdio_discovery_and_authenticated_tool_dispatch(self):
        with ThreadingHTTPServer(("127.0.0.1", 0), Handler) as server:
            server.commands = []
            worker = threading.Thread(target=server.serve_forever, daemon=True)
            worker.start()
            try:
                requests = [
                    {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2024-11-05"}},
                    {"jsonrpc": "2.0", "method": "notifications/initialized"},
                    {"jsonrpc": "2.0", "id": 2, "method": "tools/list"},
                    {"jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": {"name": "lumastudio.get_status", "arguments": {}}},
                    {"jsonrpc": "2.0", "id": 4, "method": "tools/call", "params": {"name": "lumastudio.set_instruction", "arguments": {"text": "自然提亮，保留纹理"}}},
                ]
                replies = self.run_adapter(requests, f"http://127.0.0.1:{server.server_port}")
                self.assertEqual([r["id"] for r in replies], [1, 2, 3, 4])
                self.assertEqual(len(replies[1]["result"]["tools"]), 2)
                self.assertEqual(json.loads(replies[2]["result"]["content"][0]["text"])["photoName"], "fixture.jpg")
                self.assertFalse(replies[3]["result"]["isError"])
                self.assertEqual(server.commands, [{"text": "自然提亮，保留纹理", "source": "mcp-stdio", "final": True}])
            finally:
                server.shutdown()
                worker.join(timeout=2)

    def test_nonloopback_service_is_rejected_without_leaking_token(self):
        request = {"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": {"name": "lumastudio.get_status", "arguments": {}}}
        reply = self.run_adapter([request], "http://192.0.2.1:12345")[0]
        self.assertTrue(reply["result"]["isError"])
        self.assertNotIn(TOKEN, json.dumps(reply))

    def test_unknown_tool_is_rejected(self):
        request = {"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": {"name": "shell", "arguments": {"command": "unused"}}}
        reply = self.run_adapter([request], "http://127.0.0.1:12345")[0]
        self.assertEqual(reply["error"]["code"], -32602)


if __name__ == "__main__":
    unittest.main()
