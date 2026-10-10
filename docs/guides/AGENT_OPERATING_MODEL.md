# Agent operating model

The repository keeps policy and recovery outside an individual model's session.
[AGENTS.md](../../AGENTS.md) is the shared rulebook; vendor entry points delegate to it.

1. Read rules, [context](../tracking/context.md), roadmap and ignored recovery state.
2. Use relevant [skills](../../.agents/skills/), preserve others' work and complete the
   authorized scope with matching tests.
3. Run risky commands through [safe-run](../../xops/agent/safe-run.sh); inspect its log,
   diagnose and repair failures before retrying.
4. The coordinating parent appends [tracking](../tracking/README.md), reviews/stages
   validated changes, checks `make git.dry`, publishes a Gitflow work branch via
   `make git`, and opens its PR. Delegates return evidence.
5. Respect required checks and the owner's final production approval. No direct
   main/develop writes, protection bypass or fabricated release claims.

Keep operational evidence in PR/CI/local logs, current contracts in concise guides,
and unfinished work in the [roadmap](../planning/ROADMAP.md). For client mechanics see
[Codex](CODEX_SETUP.md) and [client notes](MODEL_PROFILES.md).
