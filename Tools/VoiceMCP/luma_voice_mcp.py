#!/usr/bin/env python3
"""MCP stdio -> running LumaStudio loopback API. Python standard library only."""
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

MAX_LINE = 16384
TOOLS = [
    {"name": "lumastudio.get_status", "description": "Get current photo/task metadata; no image.",
     "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False}},
    {"name": "lumastudio.set_instruction", "description": "Queue a photo editing instruction in LumaStudio. Automatic execution is controlled by the app setting.",
     "inputSchema": {"type": "object", "properties": {"text": {"type": "string", "minLength": 1, "maxLength": 1000}, "id": {"type": "string"}}, "required": ["text"], "additionalProperties": False}},
]

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None

def app_request(path, body=None):
    base = os.environ.get("LUMA_VOICE_BASE_URL", "")
    token = os.environ.get("LUMA_VOICE_TOKEN", "")
    parsed = urllib.parse.urlsplit(base)
    if parsed.scheme != "http" or parsed.hostname not in ("127.0.0.1", "localhost", "::1") or not parsed.port or parsed.username or parsed.password or parsed.query or parsed.fragment or parsed.path not in ("", "/") or len(token) < 32:
        raise ValueError("Configure a loopback base URL and current session token")
    request = urllib.request.Request(base.rstrip("/") + path, data=None if body is None else json.dumps(body, ensure_ascii=False).encode(), headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"})
    with urllib.request.build_opener(NoRedirect).open(request, timeout=15) as response:
        data = response.read(1024 * 1024 + 1)
        if len(data) > 1024 * 1024:
            raise ValueError("Response too large")
        return json.loads(data)

def handle(request):
    rid = request.get("id")
    if "id" not in request:
        return None
    def result(value):
        return {"jsonrpc": "2.0", "id": rid, "result": value}
    def error(code, message):
        return {"jsonrpc": "2.0", "id": rid, "error": {"code": code, "message": message}}
    if request.get("jsonrpc") != "2.0":
        return error(-32600, "Invalid JSON-RPC request")
    method = request.get("method")
    if method == "initialize":
        version = request.get("params", {}).get("protocolVersion", "2024-11-05")
        if version not in ("2024-11-05", "2025-03-26", "2025-06-18"):
            version = "2024-11-05"
        return result({"protocolVersion": version, "capabilities": {"tools": {}}, "serverInfo": {"name": "LumaStudio-stdio", "version": "0.3.0"}})
    if method == "ping":
        return result({})
    if method == "tools/list":
        return result({"tools": TOOLS})
    if method != "tools/call":
        return error(-32601, "Method not found")
    params = request.get("params", {})
    arguments = params.get("arguments", {})
    name = params.get("name")
    try:
        if name == "lumastudio.get_status" and arguments == {}:
            output = app_request("/v1/status")
        elif name == "lumastudio.set_instruction" and isinstance(arguments, dict) and set(arguments) <= {"text", "id"} and isinstance(arguments.get("text"), str) and 1 <= len(arguments["text"].strip()) <= 1000:
            output = app_request("/v1/voice/commands", {**arguments, "source": "mcp-stdio", "final": True})
        else:
            return error(-32602, "Unknown tool or invalid arguments")
        return result({"content": [{"type": "text", "text": json.dumps(output, ensure_ascii=False)}], "isError": False})
    except Exception:
        # Never print a token, raw request, or provider response in errors.
        return result({"content": [{"type": "text", "text": "LumaStudio loopback request failed; check app, port and token."}], "isError": True})

def main():
    while True:
        line = sys.stdin.buffer.readline(MAX_LINE + 1)
        if not line:
            return
        try:
            if len(line) > MAX_LINE:
                raise ValueError("Oversized request")
            request = json.loads(line)
            if not isinstance(request, dict):
                raise ValueError("Expected object")
            response = handle(request)
        except Exception:
            response = {"jsonrpc": "2.0", "id": None, "error": {"code": -32700, "message": "Invalid bounded JSON request"}}
        if response is not None:
            print(json.dumps(response, ensure_ascii=False), flush=True)

if __name__ == "__main__":
    main()
