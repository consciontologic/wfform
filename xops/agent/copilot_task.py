#!/usr/bin/env python3
"""Prepare a Copilot task; explicit --submit sends it once using a user token."""
import argparse
import json
import os
import re
import http.client
from pathlib import Path
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
REPO = "consciontologic/wfform"
API = "https://api.github.com"


def payload(kind, prompt, model, release_version=None):
    policy = json.loads((ROOT / ".github/copilot-model-policy.json").read_text())
    if model not in policy["allowed_models"] or model.lower() == "auto":
        raise ValueError("Choose the explicitly reviewed low-cost model in copilot-model-policy.json; no Auto/fallback.")
    if kind not in {"feature", "bugfix", "hotfix", "release"}:
        raise ValueError("Unknown Gitflow work kind.")
    if not prompt.strip() or len(prompt) > 20000:
        raise ValueError("Provide a task description between 1 and 20000 characters.")
    base = "main" if kind == "hotfix" else "develop"
    followup = "For hotfixes, prepare a develop back-merge follow-up."
    if kind == "release":
        if not release_version or not re.fullmatch(r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)", release_version):
            raise ValueError("Release preparation requires --release-version MAJOR.MINOR.PATCH and its published release branch.")
        base = "release/" + release_version
        followup = ("This is the preparation PR into the existing release branch. "
                    "After it merges, a separate promotion PR from " + base +
                    " to main is required, followed by a develop back-merge.")
    return {
        "prompt": f"Work kind: {kind}. Read AGENTS.md and docs/guides/GITFLOW.md. "
                  f"Open a pull request targeting {base}; keep your platform-owned branch. "
                  "Implement, test, review and prepare release notes as applicable. "
                  "Do not merge, approve your own PR, bypass checks, publish a release or use a pricier model. "
                  + followup + "\n\n" + prompt,
        "base_ref": base,
        "model": model,
        "create_pull_request": True,
    }


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, msg, headers, newurl):
        return None


def submit(body, token, opener=None):
    headers = {"Authorization": "Bearer " + token,
               "Accept": "application/vnd.github+json", "Content-Type": "application/json",
               "X-GitHub-Api-Version": "2022-11-28"}
    opener = opener or urllib.request.build_opener(NoRedirect())
    query = {"query": 'query { repository(owner:"consciontologic",name:"wfform") { '
                      'suggestedActors(capabilities:[CAN_BE_ASSIGNED],first:100) { nodes { login } } } }'}
    request = urllib.request.Request(API + "/graphql", json.dumps(query).encode(), headers, method="POST")
    try:
        with opener.open(request, timeout=30) as response:
            capability = json.load(response)
        if not isinstance(capability, dict) or capability.get("errors"):
            raise ValueError("Invalid capability response")
        actors = capability["data"]["repository"]["suggestedActors"]["nodes"]
        available = isinstance(actors, list) and any(
            isinstance(actor, dict) and actor.get("login") == "copilot-swe-agent" for actor in actors)
        if not available:
            raise ValueError("Copilot unavailable")
    except (OSError, ValueError, TypeError, KeyError, http.client.HTTPException):
        raise SystemExit("Copilot capability was unavailable or could not be verified; no task was submitted.")
    request = urllib.request.Request(API + "/agents/repos/" + REPO + "/tasks",
                                     json.dumps(body).encode(), headers, method="POST")
    try:
        with opener.open(request, timeout=60) as response:
            result = json.load(response)
        states = {"queued", "in_progress", "completed", "failed", "idle",
                  "waiting_for_user", "timed_out", "cancelled"}
        if not (isinstance(result, dict) and isinstance(result.get("id"), str)
                and result["id"] and result.get("state") in states
                and isinstance(result.get("html_url"), str)
                and result["html_url"].startswith("https://github.com/" + REPO + "/")):
            raise ValueError("Invalid task receipt")
        return {key: result[key] for key in ("id", "state", "html_url")}
    except (OSError, ValueError, TypeError, http.client.HTTPException):
        # POST may already have been accepted. Never duplicate a task, or switch
        # models to conceal an availability/cost error.
        raise SystemExit("Task submission failed or its outcome is unknown. Inspect GitHub agent tasks before retrying; no automatic retry or model fallback was made.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("kind", choices=["feature", "bugfix", "hotfix", "release"])
    parser.add_argument("--prompt-file", required=True)
    parser.add_argument("--model", required=True, help="Explicit account-supported low-cost model; never Auto.")
    parser.add_argument("--release-version", help="Required for a release preparation PR.")
    parser.add_argument("--submit", action="store_true")
    args = parser.parse_args()
    body = payload(args.kind, Path(args.prompt_file).read_text(), args.model, args.release_version)
    if not args.submit:
        print(json.dumps(body, indent=2, ensure_ascii=False))
        return
    token = os.environ.get("WFFORM_GITHUB_TOKEN", "").strip()
    if not token:
        parser.error("WFFORM_GITHUB_TOKEN must be set for submission. It is never saved.")
    print(json.dumps(submit(body, token), indent=2))


if __name__ == "__main__":
    main()
