#!/usr/bin/env python3
"""Bounded, real MCP smoke check; emits metadata only, never returned source."""

from __future__ import annotations

import json
import os
from pathlib import Path
import re
import selectors
import signal
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
EXPECTED_TOOLS = {
    "codegraph_explore", "codegraph_node", "codegraph_search",
    "codegraph_callers", "codegraph_callees", "codegraph_impact",
    "codegraph_files", "codegraph_status",
}
TIMEOUT_SECONDS = 30
MAX_RESPONSE_BYTES = 4 * 1024 * 1024


def tool_text(response: dict) -> str:
    result = response.get("result", {})
    if "error" in response or result.get("isError"):
        raise RuntimeError("MCP returned an error; inspect the server with the documented CLI commands")
    return "\n".join(block.get("text", "") for block in result.get("content", [])
                     if block.get("type") == "text")


def check() -> None:
    configuration = json.loads((ROOT / ".mcp.json").read_text())["mcpServers"]["codegraph"]
    with tempfile.TemporaryFile() as stderr:
        process = subprocess.Popen(
            [configuration["command"], *configuration["args"]], cwd=ROOT,
            env={**os.environ, **configuration["env"]}, stdin=subprocess.PIPE,
            stdout=subprocess.PIPE, stderr=stderr, start_new_session=True,
        )
        selector = selectors.DefaultSelector()
        selector.register(process.stdout, selectors.EVENT_READ)
        pending = bytearray()
        request_id = 0

        def send(message: dict) -> None:
            process.stdin.write((json.dumps(message) + "\n").encode())
            process.stdin.flush()

        def request(method: str, params: dict) -> dict:
            nonlocal request_id
            request_id += 1
            send({"jsonrpc": "2.0", "id": request_id, "method": method, "params": params})
            deadline = time.monotonic() + TIMEOUT_SECONDS
            while time.monotonic() < deadline:
                while b"\n" in pending:
                    line, _, remainder = pending.partition(b"\n")
                    pending[:] = remainder
                    response = json.loads(line)
                    if response.get("id") == request_id:
                        if "error" in response:
                            raise RuntimeError(f"MCP rejected {method}")
                        return response
                if not selector.select(min(1, max(0, deadline - time.monotonic()))):
                    continue
                chunk = os.read(process.stdout.fileno(), 65536)
                if not chunk:
                    raise RuntimeError(f"MCP exited before completing {method}")
                pending.extend(chunk)
                if len(pending) > MAX_RESPONSE_BYTES:
                    raise RuntimeError("MCP response exceeded the smoke-check size limit")
            raise RuntimeError(f"MCP timed out during {method} after {TIMEOUT_SECONDS}s")

        def call(name: str, arguments: dict) -> str:
            return tool_text(request("tools/call", {"name": name, "arguments": arguments}))

        try:
            initialized = request("initialize", {
                "protocolVersion": "2024-11-05", "capabilities": {},
                "clientInfo": {"name": "wfform-codegraph-check", "version": "1.0"},
            })["result"]
            server = initialized.get("serverInfo", {})
            if server.get("name") != "codegraph" or server.get("version") != "1.6.2":
                raise RuntimeError("Unexpected CodeGraph server/version; review the pinned launcher")
            send({"jsonrpc": "2.0", "method": "notifications/initialized"})
            tools = {tool["name"] for tool in request("tools/list", {})["result"]["tools"]}
            if not EXPECTED_TOOLS.issubset(tools):
                raise RuntimeError("Required CodeGraph tools missing; run make codeg and inspect MCP configuration")
            status = call("codegraph_status", {})
            if not re.search(r"dart:\s*[1-9]\d*", status):
                raise RuntimeError("No Dart files reported in the CodeGraph index")
            source_file = "lib/features/chat/chat_controller.dart"
            search = call("codegraph_search", {"query": "ChatController", "limit": 3})
            if "ChatController" not in search or source_file not in search:
                raise RuntimeError("Dart symbol search did not find the expected application controller")
            exploration = call("codegraph_explore", {"query": "ChatController send", "maxFiles": 2})
            if source_file not in exploration or "```dart" not in exploration:
                raise RuntimeError("Dart exploration returned no application source")
            callers = call("codegraph_callers", {"symbol": "send", "file": source_file, "limit": 5})
            if "test/chat/" not in callers or "continueResponse" not in callers:
                raise RuntimeError("Dart caller query did not return expected test/application relationships")
            files = call("codegraph_files", {"format": "flat", "includeMetadata": False})
            for forbidden in ("config/local.json", ".local/", ".dart_tool/", "build/", "work/", "outputs/"):
                if re.search(r"(?:^|[\s`/])" + re.escape(forbidden), files, re.MULTILINE):
                    raise RuntimeError(f"Ignored path unexpectedly indexed: {forbidden}")
            if source_file not in files:
                raise RuntimeError("Indexed file listing did not contain the expected Dart source")
            print(f"PASS: CodeGraph {server['version']} stdio initialization and {len(tools)} advertised tools")
            print("PASS: Dart status, ChatController search, source exploration and send caller relationships")
            print("PASS: indexed-file listing excludes local configuration, runtime caches, builds and scratch output")
            for label in ("Files indexed", "Total nodes", "Total edges"):
                match = re.search(r"\*\*" + label + r":\*\*\s*([\d,]+)", status)
                if match:
                    print(f"{label}: {match.group(1)}")
            print("Client UI reload remains separate from this real MCP protocol check.")
        finally:
            selector.close()
            process.stdin.close()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()


if __name__ == "__main__":
    try:
        check()
    except (OSError, ValueError, KeyError, RuntimeError) as error:
        raise SystemExit(f"CodeGraph check failed: {error}") from None
