"""
Tiny shared MCP-over-stdio harness for the sandbox HPC demo servers.

Both ``slurm-mcp`` and ``gpu-mcp`` are JSON-RPC 2.0 stdio servers that
speak the Model Context Protocol (revision 2024-11-05). Their handler
table is the only thing that differs — the envelope, dispatch loop,
and stdio wiring are identical, so they live here.

Pure stdlib so the dashboard pod (which spawns these as subprocesses
via the MCP card's "Connect" button) doesn't need any extra deps.
"""
from __future__ import annotations

import json
import sys
from typing import Any, Callable


PROTOCOL_VERSION = "2024-11-05"


def text_result(text: str) -> dict[str, Any]:
    return {"content": [{"type": "text", "text": text}]}


def error_result(text: str) -> dict[str, Any]:
    return {"content": [{"type": "text", "text": text}], "isError": True}


def _ok(msg_id: Any, result: Any) -> dict[str, Any]:
    return {"jsonrpc": "2.0", "id": msg_id, "result": result}


def _err(msg_id: Any, code: int, message: str) -> dict[str, Any]:
    return {"jsonrpc": "2.0", "id": msg_id, "error": {"code": code, "message": message}}


def dispatch(
    request: dict[str, Any],
    *,
    server_info: dict[str, str],
    tools: list[dict[str, Any]],
    handlers: dict[str, Callable[[dict[str, Any]], dict[str, Any]]],
) -> dict[str, Any] | None:
    method = request.get("method")
    msg_id = request.get("id")
    params = request.get("params") or {}
    if msg_id is None:
        # notifications/* — no response per spec
        return None
    if method == "initialize":
        return _ok(msg_id, {
            "protocolVersion": PROTOCOL_VERSION,
            "capabilities": {"tools": {}},
            "serverInfo": server_info,
        })
    if method == "tools/list":
        return _ok(msg_id, {"tools": tools})
    if method == "tools/call":
        name = params.get("name")
        arguments = params.get("arguments") or {}
        handler = handlers.get(name)
        if handler is None:
            return _ok(msg_id, error_result(f"unknown tool {name!r}"))
        try:
            return _ok(msg_id, handler(arguments))
        except Exception as exc:
            return _ok(msg_id, error_result(f"{type(exc).__name__}: {exc}"))
    return _err(msg_id, -32601, f"method not found: {method}")


def serve_stdio(
    *,
    server_info: dict[str, str],
    tools: list[dict[str, Any]],
    handlers: dict[str, Callable[[dict[str, Any]], dict[str, Any]]],
) -> int:
    """Read JSON-RPC lines off stdin, write responses to stdout.

    One request per line; one response per request. Line-buffer stdout
    so the dashboard's MCP client sees responses immediately.
    """
    sys.stdout.reconfigure(line_buffering=True)  # type: ignore[attr-defined]
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            request = json.loads(line)
        except json.JSONDecodeError as exc:
            sys.stdout.write(json.dumps({
                "jsonrpc": "2.0", "id": None,
                "error": {"code": -32700, "message": f"parse error: {exc}"},
            }) + "\n")
            sys.stdout.flush()
            continue
        response = dispatch(
            request, server_info=server_info, tools=tools, handlers=handlers,
        )
        if response is not None:
            sys.stdout.write(json.dumps(response) + "\n")
            sys.stdout.flush()
    return 0
