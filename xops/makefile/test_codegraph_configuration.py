"""Project-local CodeGraph launcher and cross-client configuration contracts."""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import tomllib
import unittest

ROOT = Path(__file__).resolve().parents[2]


class CodegraphConfigurationTest(unittest.TestCase):
    def test_clients_use_one_launcher_and_repo_path(self) -> None:
        portable = json.loads((ROOT / ".mcp.json").read_text())["mcpServers"]["codegraph"]
        codex = tomllib.loads((ROOT / ".codex/config.toml").read_text())["mcp_servers"]["codegraph"]
        self.assertEqual(portable["command"], codex["command"])
        self.assertEqual(portable["args"], codex["args"])
        self.assertEqual(portable["env"], codex["env"])
        self.assertEqual(portable["command"], "bash")
        self.assertEqual(portable["args"][0], "-c")
        self.assertIn("git rev-parse --show-toplevel", portable["args"][1])
        self.assertNotIn("cwd", codex)
        self.assertNotIn("codegraph", json.loads((ROOT / ".vscode/mcp.json").read_text())["servers"])
        self.assertIn("status", portable["env"]["CODEGRAPH_MCP_TOOLS"].split(","))

    def test_both_clients_resolve_an_alternate_checkout_from_root_and_nested_cwd(self) -> None:
        (ROOT / "work").mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=ROOT / "work") as temp:
            directory = Path(temp)
            checkout = directory / "another checkout"
            (checkout / "xops/agent").mkdir(parents=True)
            nested = checkout / "lib/nested"
            nested.mkdir(parents=True)
            (checkout / ".codex").mkdir()
            shutil.copy2(ROOT / ".mcp.json", checkout / ".mcp.json")
            shutil.copy2(ROOT / ".codex/config.toml", checkout / ".codex/config.toml")
            shutil.copy2(ROOT / "xops/agent/codegraph.sh", checkout / "xops/agent/codegraph.sh")
            initialized = subprocess.run(["git", "init", "--quiet", str(checkout)],
                                         capture_output=True, text=True)
            self.assertEqual(initialized.returncode, 0, initialized.stderr)
            capture = directory / "capture.json"
            npm = directory / "npm"
            npm.write_text("#!/usr/bin/python3\nimport json,os,sys\n"
                           "with open(os.environ['CG_TEST_CAPTURE'],'w') as f:\n"
                           " json.dump({'args':sys.argv[1:],'cwd':os.getcwd()},f)\n")
            npm.chmod(0o755)
            portable = json.loads((checkout / ".mcp.json").read_text())["mcpServers"]["codegraph"]
            codex = tomllib.loads((checkout / ".codex/config.toml").read_text())["mcp_servers"]["codegraph"]
            for client in (portable, codex):
                for cwd in (checkout, nested):
                    with self.subTest(client=client["command"], cwd=cwd):
                        result = subprocess.run([client["command"], *client["args"]], cwd=cwd,
                                                env={**os.environ, **client["env"],
                                                     "PATH": f"{directory}:/usr/bin:/bin",
                                                     "CG_TEST_CAPTURE": str(capture)},
                                                capture_output=True, text=True)
                        self.assertEqual(result.returncode, 0, result.stderr)
                        recorded = json.loads(capture.read_text())
                        self.assertEqual(recorded["cwd"], str(checkout))
                        self.assertEqual(recorded["args"][-5:],
                                         ["codegraph", "serve", "--mcp", "--path", str(checkout)])

    def test_launcher_pins_package_keeps_arguments_and_anchors_cwd(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            capture = directory / "capture.json"
            npm = directory / "npm"
            npm.write_text("#!/usr/bin/python3\nimport json,os,sys\n"
                           "with open(os.environ['CG_TEST_CAPTURE'],'w') as f:\n"
                           " json.dump({'args':sys.argv[1:],'cwd':os.getcwd(),"
                           "'telemetry':os.environ.get('CODEGRAPH_TELEMETRY')},f)\n")
            npm.chmod(0o755)
            env = {**os.environ, "PATH": f"{directory}:/usr/bin:/bin", "CG_TEST_CAPTURE": str(capture)}
            result = subprocess.run([str(ROOT / "xops/agent/codegraph.sh"), "explore", "ChatController send"],
                                    cwd=directory, env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            recorded = json.loads(capture.read_text())
            self.assertEqual(recorded["cwd"], str(ROOT))
            self.assertEqual(recorded["telemetry"], "0")
            self.assertIn("--package=@colbymchenry/codegraph@1.6.2", recorded["args"])
            self.assertIn(str(ROOT / ".local/codegraph/npm-cache"), recorded["args"])
            self.assertEqual(recorded["args"][-3:], ["codegraph", "explore", "ChatController send"])

    def test_launcher_passes_failure_without_retry(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            npm = Path(temp) / "npm"
            npm.write_text("#!/bin/sh\nexit 43\n")
            npm.chmod(0o755)
            result = subprocess.run([str(ROOT / "xops/agent/codegraph.sh"), "version"],
                                    env={**os.environ, "PATH": f"{temp}:/usr/bin:/bin"},
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 43)

    def test_dart_scope_and_roles_enable_graph(self) -> None:
        instructions = (ROOT / ".github/instructions/codegraph.instructions.md").read_text()
        self.assertIn("dart", instructions)
        for path in (ROOT / ".codex").rglob("*.toml"):
            config = tomllib.loads(path.read_text())
            self.assertNotIn("MCP was explicitly disabled", config.get("developer_instructions", ""))
            self.assertIn("CodeGraph", config.get("developer_instructions", ""))


if __name__ == "__main__":
    unittest.main()
