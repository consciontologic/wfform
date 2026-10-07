"""Tests for CodeGraph operation reporting."""

from __future__ import annotations

import unittest
from unittest.mock import patch

from codegraph_ops import CODEGRAPH_RUNNER, _is_noop_sync, _run_codegraph, cmd_update


class CodegraphOpsTest(unittest.TestCase):
    @patch("codegraph_ops._run", return_value=(0, "Indexed"))
    def test_uses_same_pinned_launcher_as_mcp(self, run) -> None:
        _run_codegraph("init")
        run.assert_called_once_with([str(CODEGRAPH_RUNNER), "init", "."])

    @patch("codegraph_ops._run_codegraph", return_value=(8, "Indexing failed"))
    @patch("codegraph_ops._action", return_value="sync")
    def test_failure_is_not_retried_with_another_runtime(self, _action, run) -> None:
        with self.assertRaises(SystemExit) as raised:
            cmd_update([])
        self.assertEqual(raised.exception.code, 8)
        run.assert_called_once_with("sync")

    def test_identifies_an_already_up_to_date_sync(self) -> None:
        self.assertTrue(_is_noop_sync("\nAlready up to date\n"))
        self.assertFalse(_is_noop_sync("\nIndexed 24 files\n"))

    @patch("codegraph_ops.ok")
    @patch("codegraph_ops._run_codegraph", return_value=(0, "Already up to date"))
    @patch("codegraph_ops._action", return_value="sync")
    def test_reports_an_unchanged_index(self, _action, _run_codegraph, ok) -> None:
        cmd_update([])

        ok.assert_called_once_with("CodeGraph: index already up to date")


if __name__ == "__main__":
    unittest.main()
