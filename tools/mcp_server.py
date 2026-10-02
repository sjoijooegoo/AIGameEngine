"""Optional local MCP stdio adapter. CLI works without registering this server."""
from __future__ import annotations
import base64
import json
from pathlib import Path
import sys

from lab import Client
from asset_jobs import Jobs
from asset_mcp import TOOLS as ASSET_TOOLS, dispatch as asset_dispatch

TOOLS = [
    {"name": "game_start", "description": "Start an isolated Godot development session. Rendered mode supports screenshots; headless is logic-only.", "inputSchema": {"type": "object", "properties": {"headless": {"type": "boolean", "default": False}, "scene": {"type": "string", "description": "lab, probe, or assembly:<scene_id>", "default": "lab"}}, "additionalProperties": False}},
    {"name": "game_command", "description": "Send a bounded command to the current game session. Capture returns actual rendered PNG pixels. act sends key/mouse events through normal input; reset is fixture setup, not evidence of gameplay success. Consult README for command arguments.", "inputSchema": {"type": "object", "properties": {"command": {"type": "string", "enum": ["describe", "state", "ui", "reset", "act", "step", "click", "capture", "sequence", "checkpoint", "restore", "animation", "view", "resize", "audit", "asset"]}, "args": {"type": "object"}}, "required": ["command"], "additionalProperties": False}},
    {"name": "game_stop", "description": "Stop this server's game session and preserve its evidence files.", "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False}},
]
TOOLS += ASSET_TOOLS


class Server:
    def __init__(self):
        self.client = None
        self.asset_jobs = Jobs()

    def stop(self):
        if self.client:
            try:
                self.client.close()
            finally:
                self.client = None

    def tool(self, name, args):
        try:
            if not isinstance(args, dict):
                raise ValueError("arguments must be an object")
            if name == "game_start":
                if self.client:
                    raise ValueError("Stop the current session before starting another")
                self.client = Client.launch(rendered=not args.get("headless", False), scene=args.get("scene", "lab"))
                result = {"session": str(self.client.session)}
            elif name == "game_stop":
                self.stop()
                result = {"stopped": True}
            elif name == "game_command":
                if not self.client:
                    raise ValueError("Call game_start first")
                if args.get("command") not in TOOLS[1]["inputSchema"]["properties"]["command"]["enum"]:
                    raise ValueError("Unsupported command")
                result = self.client.call(args["command"], **args.get("args", {}))
            elif name in {t["name"] for t in ASSET_TOOLS}:
                result = asset_dispatch(self.asset_jobs,name,args)
            else:
                raise ValueError("Unknown tool")
            content = [{"type": "text", "text": json.dumps(result, ensure_ascii=False)}]
            if name == "game_command" and args["command"] == "capture":
                content.append({"type": "image", "mimeType": "image/png", "data": base64.b64encode(Path(result["path"]).read_bytes()).decode("ascii")})
            if name == "asset_job_status" and result.get("status") == "completed":
                captures = result.get("result", {}).get("captures", [])
                if captures:
                    image_path = result["result"].get("contact_sheet",captures[0]["path"])
                    content.append({"type":"image","mimeType":"image/png","data":base64.b64encode(Path(image_path).read_bytes()).decode("ascii")})
            return {"content": content, "isError": False}
        except Exception as error:
            return {"content": [{"type": "text", "text": str(error)}], "isError": True}

    def dispatch(self, request):
        method = request.get("method")
        params = request.get("params", {})
        if method == "initialize":
            version = params.get("protocolVersion", "2025-06-18")
            supported = ("2024-11-05", "2025-03-26", "2025-06-18")
            return {"protocolVersion": version if version in supported else supported[-1], "capabilities": {"tools": {"listChanged": False}}, "serverInfo": {"name": "bank-crisis-lab", "version": "0.1.0"}}
        if method == "ping":
            return {}
        if method == "tools/list":
            return {"tools": TOOLS}
        if method == "tools/call":
            return self.tool(params.get("name"), params.get("arguments", {}))
        raise LookupError("Method not found")


def main():
    sys.stdin.reconfigure(encoding="utf-8")
    sys.stdout.reconfigure(encoding="utf-8")
    server = Server()
    try:
        for line in sys.stdin:
            request = None
            try:
                request = json.loads(line)
                if not isinstance(request, dict) or request.get("jsonrpc") != "2.0":
                    raise ValueError("Invalid request")
                if "id" not in request:
                    continue
                response = {"jsonrpc": "2.0", "id": request["id"], "result": server.dispatch(request)}
            except Exception as error:
                code = -32700 if isinstance(error, json.JSONDecodeError) else -32601 if isinstance(error, LookupError) else -32600
                response = {"jsonrpc": "2.0", "id": request.get("id") if isinstance(request, dict) else None, "error": {"code": code, "message": str(error)}}
            print(json.dumps(response, ensure_ascii=False), flush=True)
    finally:
        server.asset_jobs.close()
        server.stop()


if __name__ == "__main__":
    main()
