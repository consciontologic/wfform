"""Offline Gitflow/Copilot contract checks; no account or git writes."""
import importlib.util
import json
from pathlib import Path
import unittest
import sys
from io import BytesIO


def load(name):
    path = Path(__file__).parents[1] / "agent" / (name + ".py")
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class GitflowTest(unittest.TestCase):
    def test_release_preparation_targets_develop_quality_lane(self):
        agent = load("copilot_task")
        with self.assertRaises(ValueError):
            agent.payload("release", "Prepare release.", "gpt-5.3-codex")
        data = agent.payload("release", "Prepare release.", "gpt-5.3-codex", "1.0.0")
        self.assertEqual(data["base_ref"], "develop")
        self.assertIn("separate promotion PR", data["prompt"])

    def test_malformed_submission_is_uncertain_never_retried(self):
        agent = load("copilot_task")
        capability = json.dumps({"data": {"repository": {"suggestedActors": {
            "nodes": [{"login": "copilot-swe-agent"}]}}}}).encode()
        for bad in [b"{broken", b"[]", b"{}", b'{"id":"x","state":"queued"}']:
            class Fake:
                calls = []
                def open(self, request, timeout):
                    self.calls.append(request.full_url)
                    return BytesIO(capability if len(self.calls) == 1 else bad)
            fake = Fake()
            with self.subTest(bad=bad), self.assertRaisesRegex(SystemExit, "outcome is unknown"):
                agent.submit({"model": "gpt-5.3-codex"}, "test-only-token", fake)
            self.assertEqual(len(fake.calls), 2)

    def test_invalid_capability_never_submits_task(self):
        agent = load("copilot_task")
        for bad in [b"{broken", b"[]", b'{"data":{"repository":null}}', b'{"errors":[{}]}']:
            class Fake:
                calls = []
                def open(self, request, timeout):
                    self.calls.append(request.full_url)
                    return BytesIO(bad)
            fake = Fake()
            with self.subTest(bad=bad), self.assertRaisesRegex(SystemExit, "no task was submitted"):
                agent.submit({}, "test-only-token", fake)
            self.assertEqual(len(fake.calls), 1)

    def test_publication_refuses_integration_branches(self):
        sys.path.insert(0, str(Path(__file__).parent))
        import git_ops
        for branch in ["main", "develop", "HEAD", "random", "release/v1.0.0"]:
            self.assertFalse(git_ops.is_work_branch(branch), branch)
        for branch in ["feature/tools", "bugfix/wrap", "hotfix/crash",
                       "release/1.0.0", "codex/release/1.0.0", "copilot/fix-tool"]:
            self.assertTrue(git_ops.is_work_branch(branch), branch)

    def test_feature_and_hotfix_bases(self):
        flow = load("gitflow")
        self.assertEqual(flow.plan("feature", "better-tools"),
                         ("feature/better-tools", "origin/develop"))
        self.assertEqual(flow.plan("hotfix", "broken-startup"),
                         ("hotfix/broken-startup", "origin/main"))
        self.assertEqual(flow.plan("release", "1.0.0"),
                         ("release/1.0.0", "origin/develop"))

    def test_rejects_unsafe_names_and_non_semver(self):
        flow = load("gitflow")
        for kind, name in [("feature", "../main"), ("feature", "--force"),
                           ("release", "v1.0.0"), ("release", "01.0.0"),
                           ("release", "1.0.0-beta"), ("main", "anything")]:
            with self.subTest(kind=kind, name=name), self.assertRaises(ValueError):
                flow.plan(kind, name)

    def test_copilot_requires_explicit_low_cost_model(self):
        agent = load("copilot_task")
        for model in ["", "auto", "Auto", "gpt-6-astra", "gpt-6-luna"]:
            with self.subTest(model=model), self.assertRaises(ValueError):
                agent.payload("feature", "Add a tested feature.", model)
        result = agent.payload("hotfix", "Fix startup.", "gpt-5.3-codex")
        self.assertEqual(result["base_ref"], "main")
        self.assertEqual(result["model"], "gpt-5.3-codex")
        self.assertTrue(result["create_pull_request"])
        self.assertIn("hotfix", result["prompt"])
        self.assertIn("Do not merge", result["prompt"])

    def test_policy_is_explicit_and_not_auto(self):
        root = Path(__file__).parents[2]
        policy = json.loads((root / ".github/copilot-model-policy.json").read_text())
        self.assertEqual(policy["preferred_model"], "gpt-5.3-codex")
        self.assertFalse(policy["allow_auto"])
        self.assertFalse(policy["allow_paid_fallback"])


if __name__ == "__main__":
    unittest.main()
