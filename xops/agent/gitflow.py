#!/usr/bin/env python3
"""Create an isolated Gitflow worktree, without committing or publishing."""
import argparse
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
SEMVER = r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)"


def plan(kind, name):
    if kind not in {"feature", "bugfix", "hotfix", "release"}:
        raise ValueError("Use feature, bugfix, hotfix or release.")
    pattern = SEMVER if kind == "release" else r"[a-z0-9]+(?:-[a-z0-9]+)*"
    if len(name) > 80 or not re.fullmatch(pattern, name):
        raise ValueError("Use a short lowercase slug; releases require plain MAJOR.MINOR.PATCH.")
    return f"{kind}/{name}", "origin/main" if kind == "hotfix" else "origin/develop"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("kind", choices=["feature", "bugfix", "hotfix", "release"])
    parser.add_argument("name")
    parser.add_argument("--agent", choices=["codex", "claude", "copilot"])
    parser.add_argument("--apply", action="store_true", help="Create the worktree; default prints the plan.")
    args = parser.parse_args()
    branch, base = plan(args.kind, args.name)
    if args.agent:
        branch = args.agent + "/" + branch
    target = ROOT / ".local" / "worktrees" / branch.replace("/", "-")
    print(f"🌱 {branch} ← {base}\n📁 {target}")
    if not args.apply:
        print("Add --apply to create this isolated checkout. Existing changes stay in the current checkout.")
        return
    # Fetch explicitly and fail on missing integration branch; never silently
    # substitute main, copy dirty files, reset a checkout or create a commit.
    subprocess.run(["git", "fetch", "origin"], cwd=ROOT, check=True)
    subprocess.run(["git", "rev-parse", "--verify", base + "^{commit}"], cwd=ROOT, check=True)
    target.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["git", "worktree", "add", "-b", branch, str(target), base], cwd=ROOT, check=True)


if __name__ == "__main__":
    main()
